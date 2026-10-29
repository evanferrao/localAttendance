import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:face_att/models/recognition_result.dart';
import 'package:face_att/services/face_recognition/image_converter.dart';
import 'package:face_att/services/face_recognition/model_manager_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

/// Service responsible for ONNX Runtime session lifecycle, isolate-based image preprocessing, and ArcFace inference.
class ArcFaceEmbeddingService {
  static const int inputSize = 112;
  static const int embeddingDimension = 512;

  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  bool _isInitialized = false;
  String _activeModelPath = 'assets/w600k_r50.onnx';
  String _activeModelNameOverride = '';
  Future<void>? _activeInferenceFuture;

  bool get isInitialized => _isInitialized;
  String get activeModelPath => _activeModelPath;

  String get activeModelName {
    if (_activeModelNameOverride.isNotEmpty) {
      return _activeModelNameOverride;
    }
    if (_activeModelPath.contains('glintr100')) {
      return 'ArcFace ResNet-100 (Glint360K)';
    } else if (_activeModelPath.contains('r50')) {
      return 'ArcFace ResNet-50 (buffalo_l)';
    } else if (_activeModelPath.contains('mbf')) {
      return 'ArcFace MobileFaceNet (buffalo_s)';
    } else {
      final name = _activeModelPath.split('/').last.split('\\').last;
      return name.isNotEmpty ? name : 'ArcFace Neural Network';
    }
  }

  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    await initializeInterpreter();
  }

  Future<void> initializeInterpreter({Uint8List? explicitModelBytes, String? explicitModelPath}) async {
    try {
      OrtEnv.instance.init();
      _sessionOptions = OrtSessionOptions();
      // Restrict ONNX Runtime to 1 dedicated thread so it never starves Flutter's UI threads
      _sessionOptions?.setIntraOpNumThreads(1);
      _sessionOptions?.setInterOpNumThreads(1);

      Uint8List? bytes = explicitModelBytes;
      String modelPath = explicitModelPath ?? 'unknown';

      if (bytes == null) {
        final loaded = await ModelManagerService.instance.loadActiveModel();
        bytes = loaded.bytes;
        modelPath = loaded.path;
        _activeModelNameOverride = loaded.displayName;
      }

      _session?.release();
      _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
      _isInitialized = true;
      _activeModelPath = modelPath;
      debugPrint("[ArcFace] ONNX Runtime session initialized with $modelPath ($activeModelName)");
    } catch (e) {
      _isInitialized = false;
      debugPrint("[ArcFace] ONNX Runtime initialization error: $e");
    }
  }

  /// Extracts a 512-d embedding from image bytes using 5-point landmark alignment via background isolate.
  Future<List<double>> getEmbeddingFromImageBytes(
    Uint8List imageBytes, {
    Rect? boundingBox,
    List<Point2D>? landmarks,
  }) async {
    await ensureInitialized();
    final params = FacePreprocessParams(
      imageBytes: imageBytes,
      boundingBox: boundingBox,
      landmarks: landmarks,
      inputSize: inputSize,
    );
    final flat = await compute(ImageConverter.preprocessFaceInIsolate, params);
    return runInference(flat);
  }

  /// Extract embeddings for multiple detected faces from a single image using a background isolate.
  Future<List<List<double>>> getMultipleFaceEmbeddings(
    Uint8List imageBytes,
    List<DetectedFaceData> faces,
  ) async {
    await ensureInitialized();
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
      embeddings.add(await runInference(flat));
    }
    return embeddings;
  }

  /// Get embedding from live camera frame via compute isolate.
  Future<List<double>> getEmbeddingFromCamera(CameraImage image, Face face, int sensorOrientation) async {
    await ensureInitialized();
    final args = ImageConverter.buildArgs(image, face, inputSize, sensorOrientation);
    final flat = await compute(ImageConverter.cropAndNormalizeIsolate, args);
    return runInference(flat);
  }

  /// Get embedding from img.Image instance.
  Future<List<double>> getEmbeddingFromImage(
    img.Image image, {
    Rect? boundingBox,
    List<Point2D>? landmarks,
  }) async {
    await ensureInitialized();
    final flat = ImageConverter.processImageForArcFace(
      image,
      landmarks: landmarks,
      boundingBox: boundingBox,
      inputSize: inputSize,
    );
    return runInference(flat);
  }

  /// Executes ONNX tensor inference sequentially and safely releases native resources.
  /// Uses a FIFO async lock to strictly guarantee that concurrent inferences
  /// never execute simultaneously on the single underlying ONNX runtime session.
  Future<List<double>> runInference(List<double> flat) async {
    final prev = _activeInferenceFuture;
    final completer = Completer<void>();
    _activeInferenceFuture = completer.future;

    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }

    try {
      return await _executeInference(flat);
    } finally {
      completer.complete();
    }
  }

  Future<List<double>> _executeInference(List<double> flat) async {
    if (_session == null) {
      throw StateError("ArcFace ONNX session is not initialized");
    }

    final inputOrt = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(flat),
      [1, 3, inputSize, inputSize],
    );
    final inputs = {'input.1': inputOrt};
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;

    try {
      outputs = await _session!.runAsync(runOptions, inputs);
      final rawList = (outputs![0]?.value as List<List<double>>)[0];
      return _l2Normalize(rawList);
    } finally {
      inputOrt.release();
      runOptions.release();
      if (outputs != null) {
        for (final element in outputs) {
          element?.release();
        }
      }
    }
  }

  static List<double> _l2Normalize(List<double> v) {
    final norm = sqrt(v.fold(0.0, (s, e) => s + e * e));
    if (norm == 0.0) return v;
    return v.map((e) => e / norm).toList();
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
