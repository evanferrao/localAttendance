import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/image_converter.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

class RecognitionMatch {
  final String studentId;
  final String name;
  final double score;
  final int index;
  final User? user;

  const RecognitionMatch({
    required this.studentId,
    required this.name,
    required this.score,
    required this.index,
    this.user,
  });

  Map<String, dynamic> toMap() => {
        'student_id': studentId,
        'name': name,
        'score': score,
        'index': index,
      };
}

class RecognitionResult {
  final bool accepted;
  final String? studentId;
  final String name;
  final double score;
  final double secondScore;
  final double margin;
  final List<RecognitionMatch> matches;
  final User? user;

  const RecognitionResult({
    required this.accepted,
    this.studentId,
    required this.name,
    required this.score,
    required this.secondScore,
    required this.margin,
    required this.matches,
    this.user,
  });
}

class DetectedFaceData {
  final Rect boundingBox;
  final List<Point2D>? landmarks; // 5 landmarks: leftEye, rightEye, noseBase, leftMouth, rightMouth
  final Face? mlKitFace;
  final Uint8List? correctedImageBytes;

  const DetectedFaceData({
    required this.boundingBox,
    this.landmarks,
    this.mlKitFace,
    this.correctedImageBytes,
  });
}

class MLService {
  static const int inputSize = 112;
  static const int embeddingDimension = 512;

  // Pipeline configuration matching InsightFace Buffalo recognition settings
  double similarityThreshold = 0.35;
  double marginThreshold = 0.0001;

  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  bool _isInitialized = false;
  String _activeModelPath = 'assets/w600k_r50.onnx';

  FaceDetector? _faceDetector;
  FaceDetector get faceDetector {
    _faceDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: true,
        enableClassification: false,
        enableTracking: false,
      ),
    );
    return _faceDetector!;
  }

  String get activeModelName {
    if (_activeModelPath.contains('glintr100')) {
      return 'ArcFace ResNet-100 (Glint360K)';
    } else if (_activeModelPath.contains('r50')) {
      return 'ArcFace ResNet-50 (buffalo_l)';
    } else {
      return 'ArcFace MobileFaceNet (buffalo_s)';
    }
  }

  /// Parse student ID and name from filename (e.g. 23BRS1150_PIYUSH_R_SAINI.jpeg)
  static Map<String, String> parseIdentityFromFilename(String filename) {
    final basename = filename.split('/').last.split('\\').last;
    final nameWithoutExt = basename.contains('.')
        ? basename.substring(0, basename.lastIndexOf('.'))
        : basename;
    final parts = nameWithoutExt.split('_');
    final studentId = parts[0];
    final name = parts.length > 1 ? parts.sublist(1).join(' ') : studentId;
    return {
      'student_id': studentId,
      'name': name,
    };
  }

  /// Extract the canonical 5 ArcFace landmarks from a Google ML Kit Face:
  /// [leftEye, rightEye, noseBase, leftMouth, rightMouth]
  static List<Point2D>? extractArcFaceLandmarks(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final nose = face.landmarks[FaceLandmarkType.noseBase]?.position;
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;

    if (leftEye != null &&
        rightEye != null &&
        nose != null &&
        leftMouth != null &&
        rightMouth != null) {
      return [
        Point2D(leftEye.x.toDouble(), leftEye.y.toDouble()),
        Point2D(rightEye.x.toDouble(), rightEye.y.toDouble()),
        Point2D(nose.x.toDouble(), nose.y.toDouble()),
        Point2D(leftMouth.x.toDouble(), leftMouth.y.toDouble()),
        Point2D(rightMouth.x.toDouble(), rightMouth.y.toDouble()),
      ];
    }
    return null;
  }

  /// Load bundled or local debug photo: 23BRS1150_PIYUSH_R_SAINI.jpeg
  Future<Uint8List> loadDebugPhotoBytes() async {
    // 1. Try asset
    try {
      final data = await rootBundle.load('assets/23BRS1150_PIYUSH_R_SAINI.jpeg');
      return data.buffer.asUint8List();
    } catch (_) {}

    // 2. Try relative file
    final relFile = File('23BRS1150_PIYUSH_R_SAINI.jpeg');
    if (await relFile.exists()) {
      return await relFile.readAsBytes();
    }

    // 3. Try absolute path
    final absFile = File('/home/box/Documents/localAttendance/23BRS1150_PIYUSH_R_SAINI.jpeg');
    if (await absFile.exists()) {
      return await absFile.readAsBytes();
    }

    throw Exception("Debug photo 23BRS1150_PIYUSH_R_SAINI.jpeg not found");
  }

  /// Detect all face bounding boxes and 5 facial landmarks on image bytes using Google ML Kit.
  /// Features rotation-aware fallback so front-camera photos (oriented at 270°/90°) are detected reliably.
  Future<List<DetectedFaceData>> detectAllFacesOnImageBytes(
    Uint8List imageBytes, {
    int? sensorOrientation,
  }) async {
    File? tempFile;
    try {
      final detector = faceDetector;
      final tempDir = Directory.systemTemp;
      tempFile = File('${tempDir.path}/faces_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(imageBytes);

      // Attempt 1: Direct detection on captured image
      var inputImage = InputImage.fromFilePath(tempFile.path);
      var faces = await detector.processImage(inputImage);

      if (faces.isNotEmpty) {
        return faces.map((face) {
          final landmarks = extractArcFaceLandmarks(face);
          return DetectedFaceData(
            boundingBox: face.boundingBox,
            landmarks: landmarks,
            mlKitFace: face,
            correctedImageBytes: imageBytes,
          );
        }).toList();
      }

      // Attempt 2: If no face detected, handle camera sensor rotation and EXIF orientation
      final decoded = img.decodeImage(imageBytes);
      if (decoded != null) {
        var upright = img.bakeOrientation(decoded);
        // Downscale large camera photos to max 1024px for lightning-fast rotation and ML Kit detection
        if (upright.width > 1024 || upright.height > 1024) {
          final maxDim = max(upright.width, upright.height);
          final scale = 1024.0 / maxDim;
          upright = img.copyResize(
            upright,
            width: (upright.width * scale).round(),
            height: (upright.height * scale).round(),
            interpolation: img.Interpolation.linear,
          );
        }

        final rotationsToTry = <int>[0];
        if (sensorOrientation != null && sensorOrientation != 0 && !rotationsToTry.contains(sensorOrientation)) {
          rotationsToTry.add(sensorOrientation);
        }
        if (!rotationsToTry.contains(270)) rotationsToTry.add(270);
        if (!rotationsToTry.contains(90)) rotationsToTry.add(90);
        if (!rotationsToTry.contains(180)) rotationsToTry.add(180);

        for (final angle in rotationsToTry) {
          final img.Image rotated;
          if (angle == 90) {
            rotated = img.copyRotate(upright, angle: 90);
          } else if (angle == 180) {
            rotated = img.copyRotate(upright, angle: 180);
          } else if (angle == 270) {
            rotated = img.copyRotate(upright, angle: 270);
          } else {
            rotated = upright;
          }

          final rotatedBytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 85));
          await tempFile.writeAsBytes(rotatedBytes);
          inputImage = InputImage.fromFilePath(tempFile.path);
          faces = await detector.processImage(inputImage);

          if (faces.isNotEmpty) {
            return faces.map((face) {
              final landmarks = extractArcFaceLandmarks(face);
              return DetectedFaceData(
                boundingBox: face.boundingBox,
                landmarks: landmarks,
                mlKitFace: face,
                correctedImageBytes: rotatedBytes,
              );
            }).toList();
          }
        }
      }
    } catch (e) {
      debugPrint("Multiple face detection on image error: $e");
    } finally {
      if (tempFile != null && tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }
    return [];
  }

  /// Detect single face (largest face in frame) on image bytes.
  Future<DetectedFaceData?> detectFaceOnImageBytes(
    Uint8List imageBytes, {
    int? sensorOrientation,
  }) async {
    final allFaces = await detectAllFacesOnImageBytes(imageBytes, sensorOrientation: sensorOrientation);
    if (allFaces.isEmpty) return null;
    return allFaces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);
  }

  /// Detect face bounding box on image bytes (legacy helper)
  Future<Rect?> detectFaceBoundingBox(Uint8List imageBytes, {int? sensorOrientation}) async {
    final data = await detectFaceOnImageBytes(imageBytes, sensorOrientation: sensorOrientation);
    return data?.boundingBox;
  }

  /// Enroll a user directly from image bytes (e.g. from file, gallery, or camera photo)
  /// Automatically uses 5-point landmark alignment for 99%+ accuracy via background isolate
  Future<User> enrollFromImageBytes({
    required Uint8List bytes,
    required String studentId,
    required String name,
    String? email,
    String? phone,
    int? sensorOrientation,
  }) async {
    await _ensureInitialized();
    final faceData = await detectFaceOnImageBytes(bytes, sensorOrientation: sensorOrientation);
    final effectiveBytes = faceData?.correctedImageBytes ?? bytes;
    final embedding = await getEmbeddingFromImageBytes(
      effectiveBytes,
      boundingBox: faceData?.boundingBox,
      landmarks: faceData?.landmarks,
    );
    final user = User(
      id: studentId,
      name: name,
      email: email,
      phone: phone,
      array: embedding,
    );
    await saveUser(user);
    return user;
  }

  /// Recognize/match identity directly from image bytes using 5-point landmark alignment via background isolate
  Future<RecognitionResult> recognizeFromImageBytes(
    Uint8List bytes, {
    int k = 5,
    int? sensorOrientation,
    Set<String>? allowedStudentIds,
  }) async {
    await _ensureInitialized();
    final faceData = await detectFaceOnImageBytes(bytes, sensorOrientation: sensorOrientation);
    final effectiveBytes = faceData?.correctedImageBytes ?? bytes;
    final embedding = await getEmbeddingFromImageBytes(
      effectiveBytes,
      boundingBox: faceData?.boundingBox,
      landmarks: faceData?.landmarks,
    );
    return recognizeFace(embedding, k: k, allowedStudentIds: allowedStudentIds);
  }

  /// Get 512-dim ArcFace embedding directly from raw image bytes.
  /// Image decompression and 5-point landmark alignment/cropping execute in a background isolate (compute),
  /// completely eliminating UI freezes, logo stuttering, and animation lag on Flutter's main thread.
  Future<List<double>> getEmbeddingFromImageBytes(
    Uint8List imageBytes, {
    Rect? boundingBox,
    List<Point2D>? landmarks,
  }) async {
    await _ensureInitialized();
    final params = FacePreprocessParams(
      imageBytes: imageBytes,
      boundingBox: boundingBox,
      landmarks: landmarks,
      inputSize: inputSize,
    );
    final flat = await compute(ImageConverter.preprocessFaceInIsolate, params);
    return _runInference(flat);
  }

  /// Extract embeddings for multiple detected faces from a single image using a background isolate.
  Future<List<List<double>>> getMultipleFaceEmbeddings(
    Uint8List imageBytes,
    List<DetectedFaceData> faces,
  ) async {
    await _ensureInitialized();
    if (faces.isEmpty) return [];

    final params = MultiFacePreprocessParams(
      imageBytes: imageBytes,
      boundingBoxes: faces.map((f) => f.boundingBox).toList(),
      landmarksList: faces.map((f) => f.landmarks).toList(),
      inputSize: inputSize,
    );
    final flats = await compute(ImageConverter.preprocessMultipleFacesInIsolate, params);
    final embeddings = <List<double>>[];
    for (final flat in flats) {
      embeddings.add(await _runInference(flat));
    }
    return embeddings;
  }

  /// Get a single L2-normalized 512-d embedding for a face from live camera
  Future<List<double>> getEmbedding(CameraImage image, Face face, int sensorOrientation) async {
    await _ensureInitialized();
    final args = ImageConverter.buildArgs(image, face, inputSize, sensorOrientation);
    final flat = await compute(ImageConverter.cropAndNormalizeIsolate, args);
    return _runInference(flat);
  }

  /// Get embedding directly on-device from an img.Image instance with optional landmark alignment
  Future<List<double>> getEmbeddingFromImage(
    img.Image image, {
    Rect? boundingBox,
    List<Point2D>? landmarks,
  }) async {
    await _ensureInitialized();
    final flat = ImageConverter.processImageForArcFace(
      image,
      landmarks: landmarks,
      boundingBox: boundingBox,
      inputSize: inputSize,
    );
    return _runInference(flat);
  }

  Future<List<double>> _runInference(List<double> flat) async {
    final inputOrt = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(flat),
      [1, 3, inputSize, inputSize],
    );
    final inputs = {'input.1': inputOrt};
    final runOptions = OrtRunOptions();

    final outputs = await _session!.runAsync(runOptions, inputs);
    final rawList = (outputs![0]?.value as List<List<double>>)[0];

    inputOrt.release();
    runOptions.release();
    for (final element in outputs) {
      element?.release();
    }

    return l2Normalize(rawList);
  }

  /// Save user with embedding to local DB
  Future<void> saveUser(User user) async {
    await LocalDB.saveUser(user);
  }

  /// Search top-k matches against registered users via cosine similarity (dot product).
  /// If [allowedStudentIds] is provided, only students belonging to that set (e.g. the specific class) are evaluated.
  List<RecognitionMatch> searchEmbedding(
    List<double> queryEmbedding, {
    int k = 5,
    Set<String>? allowedStudentIds,
  }) {
    final normQuery = l2Normalize(queryEmbedding);
    final users = LocalDB.getUsers();
    if (users.isEmpty) return [];

    // Map to keep only the highest scoring entry per distinct student
    final studentBestMatch = <String, RecognitionMatch>{};

    for (int idx = 0; idx < users.length; idx++) {
      final u = users[idx];
      if (u.array == null || u.array!.isEmpty) continue;

      // Filter: if allowedStudentIds is specified, only consider students in this active class!
      if (allowedStudentIds != null && allowedStudentIds.isNotEmpty) {
        final uIdTrimmed = u.id.trim();
        final uNameTrimmed = (u.name ?? '').trim();
        final matchesId = allowedStudentIds.contains(uIdTrimmed) ||
            allowedStudentIds.contains(uIdTrimmed.toUpperCase()) ||
            allowedStudentIds.contains(uIdTrimmed.toLowerCase());
        final matchesName = uNameTrimmed.isNotEmpty &&
            (allowedStudentIds.contains(uNameTrimmed) ||
                allowedStudentIds.contains(uNameTrimmed.toLowerCase()));
        if (!matchesId && !matchesName) {
          continue; // Exclude students not in this class!
        }
      }

      // Safety guard against legacy non-512 embeddings
      if (u.array!.length != embeddingDimension) {
        debugPrint("⚠️ Skipping user ${u.name} with incompatible embedding size (${u.array!.length})");
        continue;
      }
      final stored = l2Normalize(List<double>.from(u.array!));
      final score = dotProduct(normQuery, stored);

      // Student key: group by normalized name if present, else by student id
      final studentKey = (u.name != null && u.name!.trim().isNotEmpty)
          ? u.name!.trim().toLowerCase()
          : u.id.trim().toLowerCase();

      final existing = studentBestMatch[studentKey];
      if (existing == null || score > existing.score) {
        studentBestMatch[studentKey] = RecognitionMatch(
          studentId: u.id,
          name: u.name ?? "Unknown",
          score: score,
          index: idx,
          user: u,
        );
      }
    }

    final scored = studentBestMatch.values.toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(k).toList();
  }

  /// Recognize face using InsightFace pipeline logic.
  /// If [allowedStudentIds] is provided, only compares against enrolled students for the active class.
  RecognitionResult recognizeFace(
    List<double> faceEmbedding, {
    int k = 5,
    Set<String>? allowedStudentIds,
  }) {
    final results = searchEmbedding(faceEmbedding, k: k, allowedStudentIds: allowedStudentIds);

    if (results.isEmpty) {
      return const RecognitionResult(
        accepted: false,
        studentId: null,
        name: "Unknown",
        score: 0.0,
        secondScore: 0.0,
        margin: 0.0,
        matches: [],
      );
    }

    final best = results[0];

    // If only one candidate matched or only one student enrolled in class
    if (results.length < 2) {
      final accepted = best.score >= similarityThreshold;
      return RecognitionResult(
        accepted: accepted,
        studentId: accepted ? best.studentId : null,
        name: accepted ? best.name : "Unknown",
        score: best.score,
        secondScore: 0.0,
        margin: 0.0,
        matches: results,
        user: accepted ? best.user : null,
      );
    }

    final second = results[1];
    final bestScore = best.score;
    final secondScore = second.score;
    final margin = bestScore - secondScore;

    // A candidate is accepted when:
    // 1. bestScore exceeds the similarity threshold (>= 0.35)
    // 2. AND either the second student is NOT a match (secondScore < similarityThreshold)
    //    OR the margin between top candidate and runner-up is sufficient (>= marginThreshold)
    final accepted = bestScore >= similarityThreshold &&
        (secondScore < similarityThreshold || margin >= marginThreshold);

    return RecognitionResult(
      accepted: accepted,
      studentId: accepted ? best.studentId : null,
      name: accepted ? best.name : "Unknown",
      score: bestScore,
      secondScore: secondScore,
      margin: margin,
      matches: results,
      user: accepted ? best.user : null,
    );
  }

  /// Compare a pre-computed embedding against all registered users (convenience method)
  Future<User?> loginWithEmbedding(List<double> embedding) async {
    final result = recognizeFace(embedding);
    return result.accepted ? result.user : null;
  }

  /// Compare face against all registered users, return best match or null
  Future<User?> login(CameraImage image, Face face, int sensorOrientation) async {
    final embedding = await getEmbedding(image, face, sensorOrientation);
    return loginWithEmbedding(embedding);
  }

  List<double> l2Normalize(List<double> v) {
    final norm = sqrt(v.fold(0.0, (s, e) => s + e * e));
    if (norm == 0.0) return v;
    return v.map((e) => e / norm).toList();
  }

  double dotProduct(List<double> a, List<double> b) {
    double sum = 0.0;
    final len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  double euclideanDistance(List<double> a, List<double> b) {
    double sum = 0.0;
    final len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sqrt(sum);
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    await initializeInterpreter();
  }

  Future<void> initializeInterpreter() async {
    try {
      OrtEnv.instance.init();
      _sessionOptions = OrtSessionOptions();
      // Restrict ONNX Runtime to 1 dedicated thread so it never saturates all CPU cores
      // or starves Flutter's UI and raster rendering threads.
      _sessionOptions?.setIntraOpNumThreads(1);
      _sessionOptions?.setInterOpNumThreads(1);

      // Prefer fast and accurate w600k_r50.onnx (ResNet-50 Buffalo_L, 99.97% accuracy),
      // fallback to w600k_mbf.onnx (MobileFaceNet Buffalo_S), or glintr100.onnx
      ByteData? rawAsset;
      String modelPath = 'assets/w600k_r50.onnx';
      try {
        rawAsset = await rootBundle.load(modelPath);
      } catch (_) {
        modelPath = 'assets/w600k_mbf.onnx';
        try {
          rawAsset = await rootBundle.load(modelPath);
        } catch (_) {
          modelPath = 'assets/glintr100.onnx';
          rawAsset = await rootBundle.load(modelPath);
        }
      }

      final bytes = rawAsset.buffer.asUint8List();
      _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
      _isInitialized = true;
      _activeModelPath = modelPath;
      debugPrint("✅ ONNX Runtime ArcFace session initialized with $modelPath ($activeModelName) on 1 dedicated thread");
    } catch (e) {
      debugPrint("❌ ONNX Runtime initialization error: $e");
    }
  }

  void dispose() {
    if (_isInitialized) {
      _session?.release();
      _sessionOptions?.release();
      OrtEnv.instance.release();
      _isInitialized = false;
    }
  }
}
