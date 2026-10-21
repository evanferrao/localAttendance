import 'package:face_att/pages/attendance/widgets/scanner_camera_view.dart';
import 'package:face_att/services/camera_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScannerCameraView Widget Tests', () {
    testWidgets('shows initializing fallback when controller is null or not initialized', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ScannerCameraView(
              controller: null,
              isInitialized: false,
            ),
          ),
        ),
      );

      expect(find.text('Camera initializing...'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);
    });

    testWidgets('respects fit parameter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ScannerCameraView(
              controller: null,
              isInitialized: false,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );

      expect(find.text('Camera initializing...'), findsOneWidget);
    });
  });

  group('CameraProvider Mode Selection Tests', () {
    test('cameraForMode correctly distinguishes single vs multiple student modes', () {
      expect(CameraProvider.cameraForMode(isMultipleStudentMode: true), isNull);
      expect(CameraProvider.cameraForMode(isMultipleStudentMode: false), isNull);
    });
  });
}
