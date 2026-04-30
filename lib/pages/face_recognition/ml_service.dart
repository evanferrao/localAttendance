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
  static const double threshold = 0.7;

  Interpreter? _interpreter;
  bool _isInitialized = false;

  /// Get a single L2-normalized embedding for a face
  Future<List<double>> getEmbedding(CameraImage image, Face face, int sensorOrientation) async {
    await _ensureInitialized();
    final args = ImageConverter.buildArgs(image, face, inputSize, sensorOrientation);
    final flat = await compute(ImageConverter.cropAndNormalizeIsolate, args);

    final inputBytes = Float32List.fromList(flat);
    final embeddingSize = _interpreter!.getOutputTensor(0).shape.reduce((a, b) => a * b);
    final outputBytes = Float32List(embeddingSize);

    _interpreter!.run(inputBytes.buffer, outputBytes.buffer);
    return l2Normalize(outputBytes.toList());
  }

  /// Save user with embedding to local DB
  Future<void> saveUser(User user) async {
    await LocalDB.saveUser(user);
  }

  /// Compare face against all registered users, return best match or null
  Future<User?> login(CameraImage image, Face face, int sensorOrientation) async {
    final embedding = await getEmbedding(image, face, sensorOrientation);
    final users = LocalDB.getUsers();
    if (users.isEmpty) return null;

    User? bestMatch;
    double bestDist = double.infinity;

    for (final u in users) {
      if (u.array == null || u.array!.isEmpty) continue;
      final stored = l2Normalize(List<double>.from(u.array!));
      final dist = euclideanDistance(embedding, stored);
      debugPrint("Distance to ${u.name}: $dist");
      if (dist < bestDist) {
        bestDist = dist;
        bestMatch = u;
      }
    }

    debugPrint("Best: ${bestMatch?.name} dist=$bestDist threshold=$threshold");
    return bestDist < threshold ? bestMatch : null;
  }

  List<double> l2Normalize(List<double> v) {
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
