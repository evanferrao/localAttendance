import 'package:camera/camera.dart';

/// Centralized camera hardware discovery and provider service.
/// Encapsulates device camera enumeration with safe initialization and directional getters.
class CameraProvider {
  CameraProvider._();

  static List<CameraDescription>? _cameras;

  /// Available cameras on the device. Call [initialize] before accessing.
  static List<CameraDescription>? get cameras => _cameras;

  /// Whether camera hardware is available on this device.
  static bool get hasCamera => _cameras != null && _cameras!.isNotEmpty;

  /// Initialize the camera list. Safe to call multiple times concurrently or sequentially.
  static Future<void> initialize() async {
    if (_cameras != null && _cameras!.isNotEmpty) return;
    try {
      _cameras = await availableCameras();
    } catch (_) {
      _cameras = [];
    }
  }

  /// Returns the front-facing camera, or the first available camera if no front camera exists.
  /// Returns `null` if no camera hardware is present.
  static CameraDescription? get frontCamera {
    if (_cameras == null || _cameras!.isEmpty) return null;
    return _cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras!.first,
    );
  }

  /// Returns the back-facing camera, or the first available camera if no back camera exists.
  /// Returns `null` if no camera hardware is present.
  static CameraDescription? get backCamera {
    if (_cameras == null || _cameras!.isEmpty) return null;
    return _cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras!.first,
    );
  }

  /// Returns the recommended camera description for the given attendance mode.
  /// Uses [backCamera] for multiple student / classroom mode, and [frontCamera] for single student mode.
  static CameraDescription? cameraForMode({required bool isMultipleStudentMode}) {
    if (isMultipleStudentMode) {
      return backCamera ?? frontCamera;
    } else {
      return frontCamera ?? backCamera;
    }
  }

  /// Injects cameras for unit or integration testing.
  static void setCamerasForTesting(List<CameraDescription>? testCameras) {
    _cameras = testCameras;
  }
}
