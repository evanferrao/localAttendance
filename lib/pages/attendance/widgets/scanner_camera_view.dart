import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Renders the camera feed with proper aspect ratio fitting and an initialization fallback.
class ScannerCameraView extends StatelessWidget {
  final CameraController? controller;
  final bool isInitialized;
  final BoxFit fit;

  const ScannerCameraView({
    super.key,
    required this.controller,
    required this.isInitialized,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    if (isInitialized && controller != null && controller!.value.isInitialized) {
      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
      final previewSize = controller!.value.previewSize;

      // On Android/iOS, previewSize.width is the longer sensor dimension (e.g. 1280 or 1920)
      // and previewSize.height is the shorter dimension (e.g. 720 or 1080).
      // When in landscape, width is the longer edge; in portrait, height is the longer edge.
      final previewWidth = previewSize != null
          ? (isLandscape ? previewSize.width : previewSize.height)
          : (isLandscape ? 16.0 : 9.0);
      final previewHeight = previewSize != null
          ? (isLandscape ? previewSize.height : previewSize.width)
          : (isLandscape ? 9.0 : 16.0);

      return Container(
        color: Colors.black,
        child: Center(
          child: FittedBox(
            fit: fit,
            child: SizedBox(
              width: previewWidth,
              height: previewHeight,
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
