```dart
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:models/user.dart';
import 'package:pages/face_recognition/ml_service.dart';
import 'package:pages/home_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
 
List<CameraDescription>? cameras;

const int _kRegisterSamples = 8;
const int _kLoginSamples = 5;

class FaceScanScreen extends StatefulWidget {
  final bool isLogin;
  final User? registerUser;

  const FaceScanScreen({
    super.key,
    this.isLogin = false,
    this.registerUser,
  });

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

enum LivenessStep { blink, left, right, done }

class _FaceScanScreenState extends State<FaceScanScreen> {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  final MLService _mlService = MLService();

  bool _isControllerInitialized = false;
  bool _isDetecting = false;
  bool _isProcessing = false;
  int _sensorOrientation = 0;

  final List<List<double>> _samples = [];
  final List<List<double>> _recentEmbeddings = [];

  String _statusMessage = "Position your face in the frame";
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _livenessStart = DateTime.now();

  LivenessStep _livenessStep = LivenessStep.blink;

  int get _sampleCount => _samples.length;
  bool get _isRegistering => !widget.isLogin;
  int get _targetSamples =>
      _isRegistering ? _kRegisterSamples : _kLoginSamples;

  @override
  void initState() {
    super.initState();
    _faceDetector = GoogleMlKit.vision.faceDetector(
      FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
      ),
    );
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras == null || cameras!.isEmpty) return;

    final camera = cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras!.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _cameraController.initialize();
    _sensorOrientation = camera.sensorOrientation;

    if (!mounted) return;
    setState(() => _isControllerInitialized = true);
    _cameraController.startImageStream(_processCameraImage);
  }

  void _processCameraImage(CameraImage image) async {
    if (_isDetecting || _isProcessing) return;

    final throttle = _isRegistering ? 800 : 500;
    if (DateTime.now().difference(_lastFrameTime).inMilliseconds < throttle) {
      return;
    }
    _lastFrameTime = DateTime.now();

    _isDetecting = true;

    try {
      final camera = cameras!.first;
      final inputImage = _buildInputImage(image, camera);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        _statusMessage = "No face detected";
        return;
      }

      final face = faces.reduce((a, b) =>
          a.boundingBox.width > b.boundingBox.width ? a : b);

      final isAlive = _processLiveness(face);
      if (!isAlive) return;

      final embedding =
          await _mlService.getEmbedding(image, face, _sensorOrientation);

      _recentEmbeddings.add(embedding);
      if (_recentEmbeddings.length > 5) {
        _recentEmbeddings.removeAt(0);
      }

      final variance = _computeVariance();
      if (variance < 0.05) {
        _statusMessage = "Spoof detected";
        _resetLiveness();
        return;
      }

      await _collectSample(embedding);
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  bool _processLiveness(Face face) {
    if (face.boundingBox.width < 100) {
      _statusMessage = "Move closer";
      return false;
    }

    final yaw = (face.headEulerAngleY ?? 0).abs();
    final roll = (face.headEulerAngleZ ?? 0).abs();

    if (yaw < 1 && roll < 1) {
      _statusMessage = "Move slightly";
      return false;
    }

    if (DateTime.now().difference(_livenessStart).inSeconds > 6) {
      _resetLiveness();
    }

    switch (_livenessStep) {
      case LivenessStep.blink:
        final l = face.leftEyeOpenProbability ?? 1.0;
        final r = face.rightEyeOpenProbability ?? 1.0;
        if (l < 0.3 && r < 0.3) {
          _livenessStep = LivenessStep.left;
          _statusMessage = "Turn LEFT";
        } else {
          _statusMessage = "Blink eyes";
        }
        return false;

      case LivenessStep.left:
        if ((face.headEulerAngleY ?? 0) < -15) {
          _livenessStep = LivenessStep.right;
          _statusMessage = "Turn RIGHT";
        }
        return false;

      case LivenessStep.right:
        if ((face.headEulerAngleY ?? 0) > 15) {
          _livenessStep = LivenessStep.done;
          _statusMessage = "Hold still";
        }
        return false;

      case LivenessStep.done:
        return true;
    }
  }

  double _computeVariance() {
    if (_recentEmbeddings.length < 2) return 0;

    double total = 0;
    for (int i = 1; i < _recentEmbeddings.length; i++) {
      total += _mlService.euclideanDistance(
        _recentEmbeddings[i],
        _recentEmbeddings[i - 1],
      );
    }
    return total / _recentEmbeddings.length;
  }

  Future<void> _collectSample(List<double> embedding) async {
    _samples.add(embedding);

    if (_sampleCount >= _targetSamples) {
      _isProcessing = true;
      await _cameraController.stopImageStream();

      final avg = _averageSamples();

      if (_isRegistering) {
        final user = widget.registerUser!;
        user.array = avg;
        await _mlService.saveUser(user);
        _navigateSuccess(user);
      } else {
        final result = await _mlService.loginWithEmbedding(avg);
        if (result != null) {
          _navigateSuccess(result);
        } else {
          _resetLiveness();
        }
      }
    }
  }

  List<double> _averageSamples() {
    final size = _samples.first.length;
    final avg = List.filled(size, 0.0);

    for (var s in _samples) {
      for (int i = 0; i < size; i++) {
        avg[i] += s[i];
      }
    }

    return avg.map((e) => e / _samples.length).toList();
  }

  void _resetLiveness() {
    _livenessStep = LivenessStep.blink;
    _recentEmbeddings.clear();
    _samples.clear();
    _livenessStart = DateTime.now();
  }

  void _navigateSuccess(User user) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
      (_) => false,
    );
  }

  InputImage? _buildInputImage(
      CameraImage image, CameraDescription camera) {
    final bytes = WriteBuffer()
      ..putUint8List(image.planes[0].bytes);

    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    return InputImage.fromBytes(
      bytes: bytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _faceDetector.close();
    _mlService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isControllerInitialized
          ? CameraPreview(_cameraController)
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
```
