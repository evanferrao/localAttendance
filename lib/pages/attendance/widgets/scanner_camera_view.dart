import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Renders the camera feed with proper aspect ratio fitting and an initialization fallback.
class ScannerCameraView extends StatelessWidget {
  final CameraController? controller;
  final bool isInitialized;

  const ScannerCameraView({
    super.key,
    required this.controller,
    required this.isInitialized,
  });

  @override
  Widget build(BuildContext context) {
    if (isInitialized && controller != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller!.value.previewSize?.height ?? 1,
              height: controller!.value.previewSize?.width ?? 1,
              child: CameraPreview(controller!),
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.black54,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded, size: 44, color: Colors.white30),
            SizedBox(height: 8),
            Text(
              "Camera initializing...",
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
