import 'package:google_ml_kit/google_ml_kit.dart';

class SpoofGuard {
  /// Basic geometric checks to reject obvious spoofs (photos, small faces)
  static String? check(Face face) {
    // Face too small — likely a photo held far away
    if (face.boundingBox.width < 80 || face.boundingBox.height < 80) {
      return "Move closer to the camera";
    }

    // Face completely still with zero movement — likely a static photo
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final roll = (face.headEulerAngleZ ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    if (yaw < 1.0 && roll < 1.0 && pitch < 1.0) {
      return "Move slightly — static image detected";
    }

    return null; // passed
  }
}
