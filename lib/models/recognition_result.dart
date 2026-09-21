import 'dart:ui';
import 'package:face_att/models/point2d.dart';
import 'package:face_att/models/user.dart';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class RecognitionMatch {
  final String studentId;
  final String name;
  final double score;
  final int index;
  final User? user;

  const RecognitionMatch({
    required this.studentId,
    required this.name,
    required this.score,
    required this.index,
    this.user,
  });

  Map<String, dynamic> toMap() => {
        'student_id': studentId,
        'name': name,
        'score': score,
        'index': index,
      };
}

class RecognitionResult {
  final bool accepted;
  final String? studentId;
  final String name;
  final double score;
  final double secondScore;
  final double margin;
  final List<RecognitionMatch> matches;
  final User? user;

  const RecognitionResult({
    required this.accepted,
    this.studentId,
    required this.name,
    required this.score,
    required this.secondScore,
    required this.margin,
    required this.matches,
    this.user,
  });
}

class DetectedFaceData {
  final Rect boundingBox;
  final List<Point2D>? landmarks; // 5 landmarks: leftEye, rightEye, noseBase, leftMouth, rightMouth
  final Face? mlKitFace;
  final Uint8List? correctedImageBytes;

  const DetectedFaceData({
    required this.boundingBox,
    this.landmarks,
    this.mlKitFace,
    this.correctedImageBytes,
  });
}
