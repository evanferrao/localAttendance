import 'package:camera/camera.dart';
import 'package:face_att/services/camera_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameraProvider Tests', () {
    tearDown(() {
      CameraProvider.setCamerasForTesting(null);
    });

    test('returns null when no cameras are configured', () {
      CameraProvider.setCamerasForTesting([]);
      expect(CameraProvider.hasCamera, isFalse);
      expect(CameraProvider.frontCamera, isNull);
      expect(CameraProvider.backCamera, isNull);
    });

    test('correctly detects front and back cameras', () {
      const front = CameraDescription(
        name: 'front_camera',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      );
      const back = CameraDescription(
        name: 'back_camera',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );

      CameraProvider.setCamerasForTesting([back, front]);

      expect(CameraProvider.hasCamera, isTrue);
      expect(CameraProvider.frontCamera, equals(front));
      expect(CameraProvider.backCamera, equals(back));
    });
  });
}
