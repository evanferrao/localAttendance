import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_att/models/point2d.dart';
import 'package:face_att/models/recognition_result.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/services/face_recognition/arcface_embedding_service.dart';
import 'package:face_att/services/face_recognition/face_detector_service.dart';
import 'package:face_att/services/face_recognition/face_matcher.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

export 'package:face_att/models/point2d.dart';
export 'package:face_att/models/recognition_result.dart';

/// Unified Facade for Face Recognition operations.
/// Delegates specialized concerns to [FaceDetectorService], [ArcFaceEmbeddingService], and [FaceMatcher].
class MLService {
  static const int inputSize = ArcFaceEmbeddingService.inputSize;
  static const int embeddingDimension = ArcFaceEmbeddingService.embeddingDimension;

  final FaceDetectorService _detectorService;
  final ArcFaceEmbeddingService _embeddingService;
  final FaceMatcher _matcher;

  MLService({
    FaceDetectorService? detectorService,
    ArcFaceEmbeddingService? embeddingService,
    FaceMatcher? matcher,
  })  : _detectorService = detectorService ?? FaceDetectorService(),
        _embeddingService = embeddingService ?? ArcFaceEmbeddingService(),
        _matcher = matcher ?? FaceMatcher();

  double get similarityThreshold => _matcher.similarityThreshold;
  set similarityThreshold(double val) => _matcher.similarityThreshold = val;

  double get marginThreshold => _matcher.marginThreshold;
  set marginThreshold(double val) => _matcher.marginThreshold = val;

  FaceDetector get faceDetector => _detectorService.detector;
  String get activeModelName => _embeddingService.activeModelName;

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

  /// Extract the canonical 5 ArcFace landmarks from a Google ML Kit Face
  static List<Point2D>? extractArcFaceLandmarks(Face face) {
    return FaceDetectorService.extractArcFaceLandmarks(face);
  }

  /// Load bundled debug photo: 23BRS1150_PIYUSH_R_SAINI.jpeg (debug only)
  Future<Uint8List> loadDebugPhotoBytes() async {
    assert(kDebugMode, 'loadDebugPhotoBytes should only be called in debug mode');

    try {
      final data = await rootBundle.load('assets/23BRS1150_PIYUSH_R_SAINI.jpeg');
      return data.buffer.asUint8List();
    } catch (_) {}

    final relFile = File('23BRS1150_PIYUSH_R_SAINI.jpeg');
    if (await relFile.exists()) {
      return await relFile.readAsBytes();
    }

    throw Exception("Debug photo 23BRS1150_PIYUSH_R_SAINI.jpeg not found in assets or working directory");
  }

  /// Detect all faces on image bytes using Google ML Kit with rotation fallback
  Future<List<DetectedFaceData>> detectAllFacesOnImageBytes(
    Uint8List imageBytes, {
    int? sensorOrientation,
  }) {
    return _detectorService.detectAllFaces(imageBytes, sensorOrientation: sensorOrientation);
  }

  /// Detect single face (largest face in frame) on image bytes
  Future<DetectedFaceData?> detectFaceOnImageBytes(
    Uint8List imageBytes, {
    int? sensorOrientation,
  }) {
    return _detectorService.detectPrimaryFace(imageBytes, sensorOrientation: sensorOrientation);
  }

  /// Legacy helper for bounding box detection
  Future<Rect?> detectFaceBoundingBox(Uint8List imageBytes, {int? sensorOrientation}) async {
    final data = await detectFaceOnImageBytes(imageBytes, sensorOrientation: sensorOrientation);
    return data?.boundingBox;
  }

  /// Enroll a user directly from image bytes
  Future<User> enrollFromImageBytes({
    required Uint8List bytes,
    required String studentId,
    required String name,
    String? email,
    String? phone,
    int? sensorOrientation,
  }) async {
    await _embeddingService.ensureInitialized();
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

  /// Match identity directly from image bytes
  Future<RecognitionResult> recognizeFromImageBytes(
    Uint8List bytes, {
    int k = 5,
    int? sensorOrientation,
    Set<String>? allowedStudentIds,
  }) async {
    await _embeddingService.ensureInitialized();
    final faceData = await detectFaceOnImageBytes(bytes, sensorOrientation: sensorOrientation);
    final effectiveBytes = faceData?.correctedImageBytes ?? bytes;
    final embedding = await getEmbeddingFromImageBytes(
      effectiveBytes,
      boundingBox: faceData?.boundingBox,
      landmarks: faceData?.landmarks,
    );
    return recognizeFace(embedding, k: k, allowedStudentIds: allowedStudentIds);
  }

  /// Get 512-dim ArcFace embedding directly from raw image bytes via compute isolate
  Future<List<double>> getEmbeddingFromImageBytes(
    Uint8List imageBytes, {
    Rect? boundingBox,
    List<Point2D>? landmarks,
  }) {
    return _embeddingService.getEmbeddingFromImageBytes(
      imageBytes,
      boundingBox: boundingBox,
      landmarks: landmarks,
    );
  }

  /// Extract embeddings for multiple detected faces from a single image via compute isolate
  Future<List<List<double>>> getMultipleFaceEmbeddings(
    Uint8List imageBytes,
    List<DetectedFaceData> faces,
  ) {
    return _embeddingService.getMultipleFaceEmbeddings(imageBytes, faces);
  }

  /// Get embedding from live camera frame
  Future<List<double>> getEmbedding(CameraImage image, Face face, int sensorOrientation) {
    return _embeddingService.getEmbeddingFromCamera(image, face, sensorOrientation);
  }

  /// Get embedding from img.Image instance
  Future<List<double>> getEmbeddingFromImage(
    img.Image image, {
    Rect? boundingBox,
    List<Point2D>? landmarks,
  }) {
    return _embeddingService.getEmbeddingFromImage(
      image,
      boundingBox: boundingBox,
      landmarks: landmarks,
    );
  }

  /// Save user with embedding to local DB
  Future<void> saveUser(User user) async {
    await LocalDB.saveUser(user);
  }

  /// Search top-k matches against registered users via cosine similarity
  List<RecognitionMatch> searchEmbedding(
    List<double> queryEmbedding, {
    int k = 5,
    Set<String>? allowedStudentIds,
  }) {
    return _matcher.search(queryEmbedding, k: k, allowedStudentIds: allowedStudentIds);
  }

  /// Recognize face using ArcFace pipeline logic
  RecognitionResult recognizeFace(
    List<double> faceEmbedding, {
    int k = 5,
    Set<String>? allowedStudentIds,
  }) {
    return _matcher.match(faceEmbedding, k: k, allowedStudentIds: allowedStudentIds);
  }

  /// Compare embedding against registered users
  Future<User?> loginWithEmbedding(List<double> embedding) async {
    final result = recognizeFace(embedding);
    return result.accepted ? result.user : null;
  }

  /// Compare face from camera image against registered users
  Future<User?> login(CameraImage image, Face face, int sensorOrientation) async {
    final embedding = await getEmbedding(image, face, sensorOrientation);
    return loginWithEmbedding(embedding);
  }

  List<double> l2Normalize(List<double> v) => FaceMatcher.l2Normalize(v);
  double dotProduct(List<double> a, List<double> b) => FaceMatcher.dotProduct(a, b);
  double euclideanDistance(List<double> a, List<double> b) => FaceMatcher.euclideanDistance(a, b);

  Future<void> initializeInterpreter() => _embeddingService.initializeInterpreter();

  void dispose() {
    _detectorService.dispose();
    _embeddingService.dispose();
  }
}
