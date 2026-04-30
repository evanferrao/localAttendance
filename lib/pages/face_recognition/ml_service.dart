import 'dart:math';

import 'package:camera/camera.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/image_converter.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  static const int inputSize = 112;
  // L2-normalized same-person distance is typically < 0.6,
  // different-person > 0.8. 0.7 gives a safe margin.
  static const double threshold = 0.7;

  Interpreter? _interpreter;
  bool _isInitialized = false;

  Future<User?> predict(
    CameraImage cameraImage,
    Face face,
    bool loginUser,
    User registerUser,
    int sensorOrientation,
  ) async {
    await _ensureInitialized();
    if (_interpreter == null) {
      debugPrint("❌ Interpreter not available");
      return null;
    }

    final embedding = await _getEmbedding(cameraImage, face, sensorOrientation);

    if (!loginUser) {
      registerUser.array = embedding;
      await LocalDB.setUserDetails(registerUser);
      return registerUser;
    } else {
      final user = LocalDB.getUser();
      if (user.array == null || user.array!.isEmpty) return null;

      final stored = _l2Normalize(List<double>.from(user.array!));
      final dist = euclideanDistance(embedding, stored);
      debugPrint("Face distance: $dist (threshold: $threshold)");

      return dist < threshold ? user : null;
    }
  }

  Future<List<double>> _getEmbedding(CameraImage image, Face face, int sensorOrientation) async {
    final args = ImageConverter.buildArgs(image, face, inputSize, sensorOrientation);
    final flatInput = await compute(ImageConverter.cropAndNormalizeIsolate, args);

    final inputBytes = Float32List.fromList(flatInput);
    final embeddingSize = _interpreter!.getOutputTensor(0).shape.reduce((a, b) => a * b);
    final outputBytes = Float32List(embeddingSize);

    _interpreter!.run(inputBytes.buffer, outputBytes.buffer);
    return _l2Normalize(outputBytes.toList());
  }

  List<double> _l2Normalize(List<double> v) {
    final norm = sqrt(v.fold(0.0, (s, e) => s + e * e));
    if (norm == 0.0) return v;
    return v.map((e) => e / norm).toList();
  }

  double euclideanDistance(List<double> a, List<double> b) {
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
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
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/mobilefacenet.tflite',
        options: options,
      );
      _isInitialized = true;
      debugPrint(
          "✅ Interpreter initialized — input: ${_interpreter!.getInputTensor(0).shape}  output: ${_interpreter!.getOutputTensor(0).shape}");
    } catch (e) {
      debugPrint("❌ Interpreter initialization error: $e");
    }
  }

  void dispose() {
    if (_isInitialized) _interpreter?.close();
  }
}
