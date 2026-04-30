import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/image_converter.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  static const int inputSize = 112;
  static const double threshold = 1.0;

  Interpreter? _interpreter;
  bool _isInitialized = false;
  List<double>? predictedArray;

  Future<User?> predict(
    CameraImage cameraImage,
    Face face,
    bool loginUser,
    User registerUser,
  ) async {
    await _ensureInitialized();

    if (_interpreter == null) {
      debugPrint("❌ Interpreter not available");
      return null;
    }

    // Heavy YUV conversion + crop runs in a background isolate
    final args = ImageConverter.buildArgs(cameraImage, face, inputSize);
    final flatInput = await compute(ImageConverter.cropAndNormalizeIsolate, args);

    // Pass input as Float32List — bypasses nested list shape checks entirely
    final inputBytes = Float32List.fromList(flatInput);

    // Get embedding size from actual tensor shape
    final outTensor = _interpreter!.getOutputTensor(0);
    final embeddingSize = outTensor.shape.reduce((a, b) => a * b); // flatten all dims
    final outputBytes = Float32List(embeddingSize);

    _interpreter!.run(inputBytes.buffer, outputBytes.buffer);

    predictedArray = outputBytes.toList();

    if (!loginUser) {
      registerUser.array = predictedArray;
      await LocalDB.setUserDetails(registerUser);
      return registerUser;
    } else {
      final user = LocalDB.getUser();
      if (user.array == null || user.array!.isEmpty) return null;

      final dist = euclideanDistance(predictedArray!, user.array!);
      debugPrint("Face distance: $dist");

      return dist < threshold ? user : null;
    }
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
      // Log actual tensor shapes so we can verify
      final inShape = _interpreter!.getInputTensor(0).shape;
      final outShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint("✅ Interpreter initialized — input: $inShape  output: $outShape");
    } catch (e) {
      debugPrint("❌ Interpreter initialization error: $e");
    }
  }

  double euclideanDistance(List a, List b) {
    if (a.length != b.length) throw ArgumentError('Vectors must be same length');
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  void dispose() {
    if (_isInitialized) _interpreter?.close();
  }
}
