import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/ml_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

List<CameraDescription>? cameras;

class FaceScanScreen extends StatefulWidget {
  final bool isLogin;
  final User? registerUser;

  const FaceScanScreen({super.key, this.isLogin = false, this.registerUser});

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> {
  static const int kCaptureIntervalSeconds = 5;

  late CameraController _cameraController;
  final MLService _mlService = MLService();

  bool _isControllerInitialized = false;
  bool _isCapturing = false;
  bool _isProcessing = false;
  bool _faceDetected = false;

  int _countdown = kCaptureIntervalSeconds;
  Timer? _intervalTimer;

  String _statusMessage = "Position your face in the oval frame";

  bool get _isRegistering => !widget.isLogin;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras == null || cameras!.isEmpty) return;

    final camera = cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras!.first,
    );

    // Use ResolutionPreset.medium for sharp, clean photo capture with smooth preview
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController.initialize();
      await _cameraController.setFlashMode(FlashMode.off);

      if (!mounted) return;
      setState(() => _isControllerInitialized = true);

      // Start 5-second periodic capture loop
      _startCountdownLoop();
    } catch (e) {
      debugPrint("Camera init error: $e");
      _update(status: "Camera initialization failed: $e");
    }
  }

  void _startCountdownLoop() {
    _intervalTimer?.cancel();
    _countdown = kCaptureIntervalSeconds;
    _intervalTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_isCapturing || _isProcessing) return;

      setState(() {
        if (_countdown > 1) {
          _countdown--;
          _statusMessage = "Align face in oval • Auto-scan in ${_countdown}s";
        } else {
          _countdown = kCaptureIntervalSeconds;
          _triggerPhotoCapture();
        }
      });
    });
  }

  /// Trigger photo capture and landmark-aligned ArcFace inference
  Future<void> _triggerPhotoCapture() async {
    if (_isCapturing || _isProcessing || !_isControllerInitialized) return;
    if (_cameraController.value.isTakingPicture) return;

    setState(() {
      _isCapturing = true;
      _statusMessage = "📸 Capturing photo for high-accuracy scan...";
    });

    XFile? pictureFile;
    try {
      pictureFile = await _cameraController.takePicture();
      final bytes = await pictureFile.readAsBytes();

      // Clean up temp file immediately
      try {
        await File(pictureFile.path).delete();
      } catch (_) {}

      if (!mounted) return;
      setState(() => _statusMessage = "Analyzing photo with ArcFace ResNet-50...");

      final faceData = await _mlService.detectFaceOnImageBytes(
        bytes,
        sensorOrientation: _cameraController.description.sensorOrientation,
      );

      if (faceData == null) {
        if (mounted) {
          setState(() {
            _faceDetected = false;
            _statusMessage = "No face detected in photo • Next scan in ${kCaptureIntervalSeconds}s";
            _countdown = kCaptureIntervalSeconds;
          });
        }
        return;
      }

      if (mounted) {
        setState(() => _faceDetected = true);
      }

      final effectiveBytes = faceData.correctedImageBytes ?? bytes;
      final embedding = await _mlService.getEmbeddingFromImageBytes(
        effectiveBytes,
        boundingBox: faceData.boundingBox,
        landmarks: faceData.landmarks,
      );

      await _processSingleFace(embedding);
    } catch (e) {
      debugPrint("Photo capture/inference error: $e");
      if (mounted) {
        setState(() {
          _statusMessage = "Scan error. Retrying in ${kCaptureIntervalSeconds}s...";
          _countdown = kCaptureIntervalSeconds;
        });
        _showError("Scan error: $e");
      }
    } finally {
      if (mounted && !_isProcessing) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _processSingleFace(List<double> embedding) async {
    _intervalTimer?.cancel();
    setState(() {
      _isProcessing = true;
      _statusMessage = _isRegistering ? "Registering face..." : "Matching identity...";
    });

    if (_isRegistering && widget.registerUser != null) {
      final user = widget.registerUser!;
      user.array = embedding;
      await _mlService.saveUser(user);
      if (!mounted) return;
      _showSuccess("Face registered successfully with high-accuracy ArcFace!", () {
        Navigator.pop(context, true);
      });
      return;
    }

    if (!mounted) return;
    _showSuccess("Face scan completed successfully!", () {
      Navigator.pop(context, true);
    });
  }

  void _update({String? status}) {
    if (!mounted) return;
    setState(() {
      if (status != null && status.isNotEmpty) _statusMessage = status;
    });
  }

  void _showSuccess(String message, VoidCallback onDone) {
    if (!mounted) return;
    _update(status: message);
    bool proceeded = false;
    void proceed() {
      if (!proceeded && mounted) {
        proceeded = true;
        Navigator.of(context, rootNavigator: true).pop();
        onDone();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Icon(Icons.check_circle, color: AppColors.present, size: 52),
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: proceed,
            child: const Text("Continue", style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    Future.delayed(const Duration(milliseconds: 1500), proceed);
  }

  void _showError(String message) {
    if (!mounted) return;
    _update(status: message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  void dispose() {
    _intervalTimer?.cancel();
    if (_isControllerInitialized) {
      _cameraController.dispose();
    }
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
        title: Text(widget.isLogin ? "Face Login (5s Photo Scan)" : "Register Face (5s Photo Scan)"),
      ),
      body: Stack(
        children: [
          // 1. Camera preview
          if (_isControllerInitialized)
            Positioned.fill(child: CameraPreview(_cameraController))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // 2. Oval face guide overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _FaceOverlayPainter(
                borderColor: _faceDetected
                    ? Colors.greenAccent
                    : (_isCapturing ? Colors.amberAccent : Colors.white54),
              ),
            ),
          ),

          // 3. Top information chips
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Model & Interval Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.memory, color: Colors.cyanAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _mlService.activeModelName,
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text("5s Interval", style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Face detected status chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _faceDetected ? Colors.greenAccent : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _faceDetected ? Icons.check_circle : Icons.face,
                        color: _faceDetected ? Colors.greenAccent : Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _faceDetected ? "Face in Frame" : "Keep face inside oval",
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Bottom action panel
          Positioned(
            bottom: 32,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status message banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isCapturing ? Colors.amberAccent : Colors.white12,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isCapturing) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isCapturing ? Colors.amberAccent : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Manual "Scan Now" button with countdown badge
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_isCapturing || _isProcessing) ? null : _triggerPhotoCapture,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade800,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isCapturing || _isProcessing)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        else ...[
                          const Icon(Icons.camera_alt, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            "Scan Now",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              "${_countdown}s",
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
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
      center: Offset(size.width / 2, size.height * 0.44),
      width: size.width * 0.68,
      height: size.height * 0.44,
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
        ..strokeWidth = 3.0,
    );
  }

  @override
  bool shouldRepaint(_FaceOverlayPainter old) => old.borderColor != borderColor;
}
