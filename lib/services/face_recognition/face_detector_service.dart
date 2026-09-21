import 'dart:io';
import 'dart:math';

import 'package:face_att/models/point2d.dart';
import 'package:face_att/models/recognition_result.dart';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

/// Service responsible for Google ML Kit face and landmark detection with rotation-aware fallbacks.
class FaceDetectorService {
  FaceDetector? _faceDetector;

  FaceDetector get detector {
    _faceDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: true,
        enableClassification: false,
        enableTracking: false,
      ),
    );
    return _faceDetector!;
  }

  /// Extract the canonical 5 ArcFace landmarks from a Google ML Kit Face:
  /// [leftEye, rightEye, noseBase, leftMouth, rightMouth]
  static List<Point2D>? extractArcFaceLandmarks(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final nose = face.landmarks[FaceLandmarkType.noseBase]?.position;
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;

    if (leftEye != null &&
        rightEye != null &&
        nose != null &&
        leftMouth != null &&
        rightMouth != null) {
      return [
        Point2D(leftEye.x.toDouble(), leftEye.y.toDouble()),
        Point2D(rightEye.x.toDouble(), rightEye.y.toDouble()),
        Point2D(nose.x.toDouble(), nose.y.toDouble()),
        Point2D(leftMouth.x.toDouble(), leftMouth.y.toDouble()),
        Point2D(rightMouth.x.toDouble(), rightMouth.y.toDouble()),
      ];
    }
    return null;
  }

  /// Detect all faces and their 5 ArcFace landmarks from raw image bytes.
  /// Features rotation-aware fallback so front-camera photos (oriented at 270°/90°) are detected reliably.
  /// Securely ensures all temporary files are erased even on exceptions.
  Future<List<DetectedFaceData>> detectAllFaces(
    Uint8List imageBytes, {
    int? sensorOrientation,
  }) async {
    File? tempFile;
    try {
      final d = detector;
      final tempDir = Directory.systemTemp;
      final uniqueId = DateTime.now().microsecondsSinceEpoch ^ Random.secure().nextInt(1000000);
      tempFile = File('${tempDir.path}/face_det_$uniqueId.jpg');
      await tempFile.writeAsBytes(imageBytes);

      // Attempt 1: Direct detection on captured image
      var inputImage = InputImage.fromFilePath(tempFile.path);
      var faces = await d.processImage(inputImage);

      if (faces.isNotEmpty) {
        return faces.map((face) {
          final landmarks = extractArcFaceLandmarks(face);
          return DetectedFaceData(
            boundingBox: face.boundingBox,
            landmarks: landmarks,
            mlKitFace: face,
            correctedImageBytes: imageBytes,
          );
        }).toList();
      }

      // Attempt 2: Handle camera sensor rotation and EXIF orientation
      final decoded = img.decodeImage(imageBytes);
      if (decoded != null) {
        var upright = img.bakeOrientation(decoded);
        // Downscale large camera photos to max 1024px for fast rotation and ML Kit detection
        if (upright.width > 1024 || upright.height > 1024) {
          final maxDim = max(upright.width, upright.height);
          final scale = 1024.0 / maxDim;
          upright = img.copyResize(
            upright,
            width: (upright.width * scale).round(),
            height: (upright.height * scale).round(),
            interpolation: img.Interpolation.linear,
          );
        }

        final rotationsToTry = <int>[0];
        if (sensorOrientation != null && sensorOrientation != 0 && !rotationsToTry.contains(sensorOrientation)) {
          rotationsToTry.add(sensorOrientation);
        }
        if (!rotationsToTry.contains(270)) rotationsToTry.add(270);
        if (!rotationsToTry.contains(90)) rotationsToTry.add(90);
        if (!rotationsToTry.contains(180)) rotationsToTry.add(180);

        for (final angle in rotationsToTry) {
          final img.Image rotated;
          if (angle == 90) {
            rotated = img.copyRotate(upright, angle: 90);
          } else if (angle == 180) {
            rotated = img.copyRotate(upright, angle: 180);
          } else if (angle == 270) {
            rotated = img.copyRotate(upright, angle: 270);
          } else {
            rotated = upright;
          }

          final rotatedBytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 85));
          await tempFile.writeAsBytes(rotatedBytes);
          inputImage = InputImage.fromFilePath(tempFile.path);
          faces = await d.processImage(inputImage);

          if (faces.isNotEmpty) {
            return faces.map((face) {
              final landmarks = extractArcFaceLandmarks(face);
              return DetectedFaceData(
                boundingBox: face.boundingBox,
                landmarks: landmarks,
                mlKitFace: face,
                correctedImageBytes: rotatedBytes,
              );
            }).toList();
          }
        }
      }
    } catch (e) {
      debugPrint("Face detection error: $e");
    } finally {
      // Security: Always purge temporary image files from storage
      if (tempFile != null && tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }
    return [];
  }

  /// Detect the single primary (largest) face in the image bytes.
  Future<DetectedFaceData?> detectPrimaryFace(
    Uint8List imageBytes, {
    int? sensorOrientation,
  }) async {
    final allFaces = await detectAllFaces(imageBytes, sensorOrientation: sensorOrientation);
    if (allFaces.isEmpty) return null;
    return allFaces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);
  }

  /// Release underlying resources
  void dispose() {
    _faceDetector?.close();
    _faceDetector = null;
  }
}
