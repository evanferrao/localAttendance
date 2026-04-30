import 'package:camera/camera.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/ml_service.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

List<CameraDescription>? cameras;

// How many samples to collect before finalizing registration
const int _kRegisterSamples = 5;

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

class _FaceScanScreenState extends State<FaceScanScreen> {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  final MLService _mlService = MLService();

  bool _isControllerInitialized = false;
  bool _isDetecting = false;
  bool _isProcessing = false;
  int _sensorOrientation = 0;

  // Registration sampling state
  final List<List<double>> _samples = [];
  String _statusMessage = "Position your face in the frame";
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);

  int get _sampleCount => _samples.length;
  bool get _isRegistering => !widget.isLogin;

  @override
  void initState() {
    super.initState();
    _faceDetector = GoogleMlKit.vision.faceDetector(
      FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: false,
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

    // Throttle — 800ms between samples during registration, 500ms for login
    final throttle = _isRegistering ? 800 : 500;
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
        if (mounted) setState(() => _statusMessage = "No face detected — look at the camera");
        _isDetecting = false;
        return;
      }

      final face = faces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);

      if (_isRegistering) {
        await _collectSample(image, face);
      } else {
        await _doLogin(image, face);
      }
    } catch (e) {
      debugPrint("Detection error: $e");
      if (mounted) setState(() => _statusMessage = "Error — try again");
    } finally {
      _isDetecting = false;
    }
  }

  /// Collect one embedding sample; finalize when enough are gathered
  Future<void> _collectSample(CameraImage image, Face face) async {
    final embedding = await _mlService.getEmbedding(image, face, _sensorOrientation);

    _samples.add(embedding);

    if (mounted) {
      setState(() {
        _statusMessage = _sampleCount < _kRegisterSamples ? "Hold still... ($_sampleCount/$_kRegisterSamples)" : "Processing...";
      });
    }

    if (_sampleCount >= _kRegisterSamples) {
      _isProcessing = true;
      await _cameraController.stopImageStream();
      await _finalizeRegistration();
    }
  }

  Future<void> _finalizeRegistration() async {
    // Average all samples element-wise for a stable embedding
    final size = _samples.first.length;
    final averaged = List<double>.generate(size, (i) {
      return _samples.map((s) => s[i]).reduce((a, b) => a + b) / _samples.length;
    });
    final normalized = _mlService.l2Normalize(averaged);

    final user = widget.registerUser!;
    user.array = normalized;
    await _mlService.saveUser(user);

    if (!mounted) return;
    _showSuccess("Face registered successfully!", () {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
        (_) => false,
      );
    });
  }

  Future<void> _doLogin(CameraImage image, Face face) async {
    _isProcessing = true;
    await _cameraController.stopImageStream();

    if (mounted) setState(() => _statusMessage = "Verifying...");

    final result = await _mlService.login(image, face, _sensorOrientation);

    if (!mounted) return;

    if (result != null) {
      _showSuccess("Welcome back, ${result.name}!", () {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(user: result)),
          (_) => false,
        );
      });
    } else {
      _showError("Face not recognized. Try again.");
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    }
  }

  InputImage? _buildInputImage(CameraImage image, CameraDescription camera) {
    final bytes = _concatenatePlanes(image.planes);
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

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final buf = WriteBuffer();
    for (final p in planes) buf.putUint8List(p.bytes);
    return buf.done().buffer.asUint8List();
  }

  void _showSuccess(String message, VoidCallback onDone) {
    setState(() => _statusMessage = message);
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
    if (mounted) {
      setState(() => _statusMessage = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
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
    final progress = _isRegistering ? (_sampleCount / _kRegisterSamples).clamp(0.0, 1.0) : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.isLogin ? "Face Login" : "Register Face"),
      ),
      body: Stack(
        children: [
          // Camera preview
          if (_isControllerInitialized)
            Positioned.fill(child: CameraPreview(_cameraController))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Oval overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _FaceOverlayPainter(
                borderColor: _isRegistering && _sampleCount > 0 ? Colors.greenAccent : Colors.white70,
              ),
            ),
          ),

          // Top instruction
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black45,
              child: Text(
                widget.isLogin ? "Look straight at the camera" : "Keep your face inside the oval — stay still",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),

          // Progress bar (registration only)
          if (_isRegistering)
            Positioned(
              bottom: 120,
              left: 40,
              right: 40,
              child: Column(
                children: [
                  Text(
                    "Scanning $_sampleCount / $_kRegisterSamples",
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
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
}

class _FaceOverlayPainter extends CustomPainter {
  final Color borderColor;
  const _FaceOverlayPainter({this.borderColor = Colors.greenAccent});

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
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
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_FaceOverlayPainter old) => old.borderColor != borderColor;
}
