import 'package:camera/camera.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/frame_buffer.dart';
import 'package:face_att/pages/face_recognition/liveness_service.dart';
import 'package:face_att/pages/face_recognition/ml_service.dart';
import 'package:face_att/pages/face_recognition/spoof_guard.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

List<CameraDescription>? cameras;

const int _kRegisterSamples = 8;
const int _kLoginSamples = 5;

// Minimum motion variance to reject static-image spoofs
const double _kMinVariance = 0.02;

class FaceScanScreen extends StatefulWidget {
  final bool isLogin;
  final User? registerUser;

  const FaceScanScreen({super.key, this.isLogin = false, this.registerUser});

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  final MLService _mlService = MLService();
  final LivenessService _liveness = LivenessService();
  final FrameBuffer _frameBuffer = FrameBuffer(maxFrames: 6);

  bool _isControllerInitialized = false;
  bool _isDetecting = false;
  bool _isProcessing = false;
  int _sensorOrientation = 0;

  final List<List<double>> _samples = [];
  String _statusMessage = "Position your face in the frame";
  String _livenessInstruction = "";
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isRegistering => !widget.isLogin;
  int get _sampleCount => _samples.length;
  int get _targetSamples => _isRegistering ? _kRegisterSamples : _kLoginSamples;

  @override
  void initState() {
    super.initState();
    _faceDetector = GoogleMlKit.vision.faceDetector(
      FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        // Must enable classification for eye open probability
        enableClassification: true,
        enableTracking: false,
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
    _cameraController.setFlashMode(FlashMode.off);
    _sensorOrientation = camera.sensorOrientation;

    if (!mounted) return;
    setState(() => _isControllerInitialized = true);
    _cameraController.startImageStream(_processCameraImage);
  }

  void _processCameraImage(CameraImage image) async {
    if (_isDetecting || _isProcessing) return;

    final throttle = _isRegistering ? 700 : 500;
    final now = DateTime.now();
    if (now.difference(_lastFrameTime).inMilliseconds < throttle) return;
    _lastFrameTime = now;
    _isDetecting = true;

    try {
      final camera = cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras!.first,
      );

      final inputImage = _buildInputImage(image, camera);
      if (inputImage == null) {
        _isDetecting = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _update(status: "No face detected — look at the camera");
        _isDetecting = false;
        return;
      }

      final face = faces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);

      // ── 1. Spoof guard (geometry check) ──────────────────────────────
      final spoofMsg = SpoofGuard.check(face);
      if (spoofMsg != null) {
        _update(status: spoofMsg);
        _isDetecting = false;
        return;
      }

      // ── 2. Liveness check ────────────────────────────────────────────
      final livenessOk = _liveness.process(face);
      _update(
        liveness: _liveness.currentInstruction,
        status: livenessOk ? "Liveness confirmed — scanning..." : "",
      );

      if (!livenessOk) {
        _isDetecting = false;
        return;
      }

      // ── 3. Get embedding ─────────────────────────────────────────────
      final embedding = await _mlService.getEmbedding(image, face, _sensorOrientation);

      // ── 4. Motion variance anti-spoof ────────────────────────────────
      _frameBuffer.add(embedding);
      if (_frameBuffer.isFull && _frameBuffer.motionVariance < _kMinVariance) {
        _update(status: "Static image detected — please move naturally");
        _frameBuffer.reset();
        _isDetecting = false;
        return;
      }

      // ── 5. Collect sample ────────────────────────────────────────────
      await _collectSample(embedding);
    } catch (e) {
      debugPrint("Detection error: $e");
      _update(status: "Error — try again");
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _collectSample(List<double> embedding) async {
    _samples.add(embedding);
    _update(
      status: _sampleCount < _targetSamples
          ? (_isRegistering ? "Hold still... ($_sampleCount/$_targetSamples)" : "Scanning... ($_sampleCount/$_targetSamples)")
          : "Processing...",
    );

    if (_sampleCount < _targetSamples) return;

    _isProcessing = true;
    await _cameraController.stopImageStream();

    final averaged = _averageSamples();

    if (_isRegistering) {
      final user = widget.registerUser!;
      user.array = averaged;
      await _mlService.saveUser(user);
      if (!mounted) return;
      _showSuccess("Face registered!", () {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => HomeScreen(user: user)), (_) => false);
      });
    } else {
      final result = await _mlService.loginWithEmbedding(averaged);
      if (!mounted) return;
      if (result != null) {
        _showSuccess("Welcome back, ${result.name}!", () {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => HomeScreen(user: result)), (_) => false);
        });
      } else {
        _showError("Face not recognized. Try again.");
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          // Reset and try again instead of popping
          _samples.clear();
          _frameBuffer.reset();
          _liveness.reset();
          _isProcessing = false;
          _cameraController.startImageStream(_processCameraImage);
          _update(status: "Try again", liveness: _liveness.currentInstruction);
        }
      }
    }
  }

  List<double> _averageSamples() {
    final size = _samples.first.length;
    final avg = List<double>.generate(size, (i) => _samples.map((s) => s[i]).reduce((a, b) => a + b) / _samples.length);
    return _mlService.l2Normalize(avg);
  }

  void _update({String? status, String? liveness}) {
    if (!mounted) return;
    setState(() {
      if (status != null && status.isNotEmpty) _statusMessage = status;
      if (liveness != null) _livenessInstruction = liveness;
    });
  }

  InputImage? _buildInputImage(CameraImage image, CameraDescription camera) {
    final buf = WriteBuffer();
    for (final p in image.planes) buf.putUint8List(p.bytes);
    final bytes = buf.done().buffer.asUint8List();

    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  void _showSuccess(String message, VoidCallback onDone) {
    _update(status: message);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDone();
            },
            child: const Text("Continue"),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    _update(status: message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
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
    final progress = (_sampleCount / _targetSamples).clamp(0.0, 1.0);
    final livenessComplete = _liveness.isDone;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.isLogin ? "Face Login" : "Register Face"),
      ),
      body: Stack(
        children: [
          // Camera
          if (_isControllerInitialized)
            Positioned.fill(child: CameraPreview(_cameraController))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Oval overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _FaceOverlayPainter(
                borderColor: livenessComplete ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
          ),

          // Liveness instruction banner (top)
          if (!livenessComplete)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                color: Colors.orange.withValues(alpha: 0.85),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.face_retouching_natural, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _livenessInstruction.isEmpty ? _liveness.currentInstruction : _livenessInstruction,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),

          // Liveness steps indicator
          if (!livenessComplete)
            Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StepDot(done: _liveness.isDone || _currentStepIndex > 0, label: "Blink"),
                  const SizedBox(width: 8),
                  _StepDot(done: _currentStepIndex > 1, label: "Left"),
                  const SizedBox(width: 8),
                  _StepDot(done: _currentStepIndex > 2, label: "Right"),
                ],
              ),
            ),

          // Progress bar (shown after liveness)
          if (livenessComplete)
            Positioned(
              bottom: 120,
              left: 40,
              right: 40,
              child: Column(
                children: [
                  Text(
                    _isRegistering ? "Registering $_sampleCount / $_targetSamples" : "Scanning $_sampleCount / $_targetSamples",
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(
                        _isRegistering ? Colors.greenAccent : Colors.blueAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Status message
          Positioned(
            bottom: 52,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int get _currentStepIndex => _liveness.stepIndex;
}

class _StepDot extends StatelessWidget {
  final bool done;
  final String label;
  const _StepDot({required this.done, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? Colors.greenAccent : Colors.white24,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: done ? Colors.greenAccent : Colors.white38, fontSize: 10)),
      ],
    );
  }
}

class _FaceOverlayPainter extends CustomPainter {
  final Color borderColor;
  const _FaceOverlayPainter({this.borderColor = Colors.greenAccent});

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: size.width * 0.65,
      height: size.height * 0.42,
    );

    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addOval(ovalRect)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black54,
    );

    canvas.drawOval(
        ovalRect,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0);
  }

  @override
  bool shouldRepaint(_FaceOverlayPainter old) => old.borderColor != borderColor;
}
