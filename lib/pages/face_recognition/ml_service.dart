import 'dart:io';
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
  static const double threshold = 1.0;

  Interpreter? _interpreter;
  bool _isInitialized = false;
  List<double>? predictedArray;
  Delegate? _delegate;

  Future<User?> predict(
    CameraImage cameraImage,
    Face face,
    bool loginUser,
    String name,
  ) async {
    await _ensureInitialized();

    if (_interpreter == null) {
      debugPrint("❌ Interpreter not available");
      return null;
    }

    // Heavy YUV conversion + crop runs in a background isolate
    final args = ImageConverter.buildArgs(cameraImage, face, inputSize);
    final flatInput = await compute(ImageConverter.cropAndNormalizeIsolate, args);

    // Build properly typed 4D input [1][112][112][3]
    final input = _buildInput4D(flatInput);
    final output = {0: List.generate(1, (_) => List.filled(192, 0.0))};

    _interpreter!.runForMultipleInputs([input], output);

    predictedArray = List<double>.from(output[0]![0]);

    if (!loginUser) {
      LocalDB.setUserDetails(User(name: name, array: predictedArray));
      return null;
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
      final options = InterpreterOptions();

      if (Platform.isAndroid) {
        try {
          _delegate = GpuDelegateV2(
            options: GpuDelegateOptionsV2(isPrecisionLossAllowed: true),
          );
          options.addDelegate(_delegate!);
          debugPrint("✅ Android GPU Delegate enabled");
        } catch (e) {
          debugPrint("❌ Android GPU failed, fallback to CPU: $e");
        }
      } else if (Platform.isIOS) {
        try {
          _delegate = GpuDelegate(
            options: GpuDelegateOptions(allowPrecisionLoss: true),
          );
          options.addDelegate(_delegate!);
          debugPrint("✅ iOS GPU Delegate enabled");
        } catch (e) {
          debugPrint("❌ iOS GPU failed, fallback to CPU: $e");
        }
      }

      _interpreter = await Interpreter.fromAsset(
        'assets/mobilefacenet.tflite',
        options: options,
      );
      _isInitialized = true;
      debugPrint("✅ Interpreter initialized");
    } catch (e) {
      debugPrint("❌ Interpreter initialization error: $e");
    }
  }

  /// Converts flat [H*W*C] list into [1][H][W][C] nested list for tflite
  List _buildInput4D(List<double> flat) {
    int idx = 0;
    return [List.generate(inputSize, (_) => List.generate(inputSize, (_) => List.generate(3, (_) => flat[idx++])))];
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
    _delegate?.delete();
  }
}
