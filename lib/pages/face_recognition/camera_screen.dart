import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/ml_service.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

List<CameraDescription>? cameras;

class FaceScanScreen extends StatefulWidget {
  final User? user;
  final bool isLogin;
  final String? registerName;
  final User? registerUser; // full user object for registration

  const FaceScanScreen({
    super.key,
    this.user,
    this.isLogin = false,
    this.registerName,
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
  String _statusMessage = "Position your face in the frame";
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);

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

    // Prefer front camera
    final camera = cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras!.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.low, // smaller frames = less memory pressure
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _cameraController.initialize();
    _cameraController.setFlashMode(FlashMode.off);

    if (!mounted) return;
    setState(() => _isControllerInitialized = true);

    _cameraController.startImageStream(_processCameraImage);
  }

  void _processCameraImage(CameraImage image) async {
    if (_isDetecting || _isProcessing) return;

    // Throttle: process at most one frame every 500ms
    final now = DateTime.now();
    if (now.difference(_lastFrameTime).inMilliseconds < 500) return;
    _lastFrameTime = now;

    _isDetecting = true;

    try {
      // Convert to InputImage for ML Kit
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
        if (mounted) setState(() => _statusMessage = "No face detected");
        _isDetecting = false;
        return;
      }

      if (mounted) setState(() => _statusMessage = "Face detected! Hold still...");

      // Take the largest face
      final face = faces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);

      _isProcessing = true;
      await _cameraController.stopImageStream();

      final result = await _mlService.predict(
        image,
        face,
        widget.isLogin,
        widget.registerUser ?? User(name: widget.registerName ?? ''),
      );

      if (!mounted) return;

      if (widget.isLogin) {
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
      } else {
        // Register success — go home
        _showSuccess("Face registered successfully!", () {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => HomeScreen(user: widget.registerUser ?? User(name: widget.registerName))),
            (_) => false,
          );
        });
      }
    } catch (e) {
      debugPrint("Detection error: $e");
      if (mounted) setState(() => _statusMessage = "Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  InputImage? _buildInputImage(CameraImage image, CameraDescription camera) {
    // Concatenate all planes into a single byte array (required for NV21)
    final bytes = _concatenatePlanes(image.planes);

    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
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
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
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
    setState(() => _statusMessage = message);
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

          // Face oval overlay
          Positioned.fill(
            child: CustomPaint(painter: _FaceOverlayPainter()),
          ),

          // Status message
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),

          // Mode label
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black38,
              child: Text(
                widget.isLogin ? "Look at the camera to log in" : "Register your face — look straight at the camera",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a semi-transparent overlay with a clear oval cutout
class _FaceOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.65,
      height: size.height * 0.42,
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Green border around oval
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
