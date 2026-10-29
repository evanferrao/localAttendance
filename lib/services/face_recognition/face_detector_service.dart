import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:face_att/models/point2d.dart';
import 'package:face_att/models/recognition_result.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Service responsible for Google ML Kit face and landmark detection with rotation-aware fallbacks.
class FaceDetectorService {
  FaceDetector? _faceDetector;
  Future<void>? _activeDetectionFuture;

  FaceDetector get detector {
    _faceDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.02,
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
  /// Bakes EXIF orientation and handles camera rotation so all detected faces
  /// and landmarks match the image pixels precisely.
  /// Securely ensures all temporary files are erased even on exceptions.
  /// Uses a FIFO async lock to prevent concurrent executions from colliding on ML Kit.
  Future<List<DetectedFaceData>> detectAllFaces(
    Uint8List imageBytes, {
    int? sensorOrientation,
  }) async {
    final prev = _activeDetectionFuture;
    final completer = Completer<void>();
    _activeDetectionFuture = completer.future;

    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }

    try {
      return await _executeDetectAllFaces(imageBytes, sensorOrientation: sensorOrientation);
    } finally {
      completer.complete();
    }
  }

  Future<List<DetectedFaceData>> _executeDetectAllFaces(
    Uint8List imageBytes, {
    int? sensorOrientation,
  }) async {
    if (imageBytes.isEmpty) return [];

    File? tempFile;
    try {
      final d = detector;
      final tempDir = Directory.systemTemp;
      final uniqueId = DateTime.now().microsecondsSinceEpoch ^ Random.secure().nextInt(1000000);
      tempFile = File('${tempDir.path}/face_det_$uniqueId.jpg');

      // 1. Decode image and bake EXIF orientation so image pixels are physically upright.
      // This ensures ML Kit bounding boxes and landmarks match the image pixels 1:1.
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return [];
      var upright = img.bakeOrientation(decoded);

      // Downscale very large photos (e.g. > 1600px) to prevent OOM while keeping enough resolution
      // for smaller faces across a classroom.
      if (upright.width > 1600 || upright.height > 1600) {
        final maxDim = max(upright.width, upright.height);
        final scale = 1600.0 / maxDim;
        upright = img.copyResize(
          upright,
          width: (upright.width * scale).round(),
          height: (upright.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      final uprightBytes = Uint8List.fromList(img.encodeJpg(upright, quality: 90));
      await tempFile.writeAsBytes(uprightBytes);

      // Attempt 1: Direct detection on upright image
      var inputImage = InputImage.fromFilePath(tempFile.path);
      var faces = await d.processImage(inputImage);

      if (faces.isNotEmpty) {
        return faces.map((face) {
          final landmarks = extractArcFaceLandmarks(face);
          return DetectedFaceData(
            boundingBox: face.boundingBox,
            landmarks: landmarks,
            mlKitFace: face,
            correctedImageBytes: uprightBytes,
          );
        }).toList();
      }

      // Attempt 2: If no faces found at 0°, try rotations based on sensor orientation
      final rotationsToTry = <int>[];
      if (sensorOrientation != null && sensorOrientation != 0) {
        rotationsToTry.add(sensorOrientation);
      }
      for (final a in [90, 180, 270]) {
        if (!rotationsToTry.contains(a)) rotationsToTry.add(a);
      }

      for (final angle in rotationsToTry) {
        final img.Image rotated = img.copyRotate(upright, angle: angle);
        final rotatedBytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 90));
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
    try {
      _faceDetector?.close();
    } catch (_) {}
    _faceDetector = null;
  }
}
