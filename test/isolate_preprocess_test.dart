import 'dart:io';
import 'package:face_att/pages/face_recognition/image_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ImageConverter.preprocessFaceInIsolate processes image bytes into normalized tensor', () async {
    final imageBytes = await File('test/sample_face_112.png').readAsBytes();
    final params = FacePreprocessParams(
      imageBytes: imageBytes,
      boundingBox: null,
      landmarks: null,
      inputSize: 112,
    );

    // Run via Flutter's compute (worker isolate)
    final tensor = await compute(ImageConverter.preprocessFaceInIsolate, params);

    expect(tensor.length, 112 * 112 * 3);
    // Values should be normalized between -1.0 and 1.0
    for (int i = 0; i < 100; i++) {
      expect(tensor[i], greaterThanOrEqualTo(-1.0));
      expect(tensor[i], lessThanOrEqualTo(1.0));
    }
  });

  test('ImageConverter.preprocessFaceInIsolate handles 5-point landmark alignment in isolate', () async {
    final imageBytes = await File('test/sample_face_112.png').readAsBytes();
    const landmarks = [
      Point2D(38.2946, 51.6963),
      Point2D(73.5318, 51.5014),
      Point2D(56.0252, 71.7366),
      Point2D(41.5493, 92.3655),
      Point2D(70.7299, 92.2041),
    ];
    final params = FacePreprocessParams(
      imageBytes: imageBytes,
      boundingBox: null,
      landmarks: landmarks,
      inputSize: 112,
    );

    final tensor = await compute(ImageConverter.preprocessFaceInIsolate, params);

    expect(tensor.length, 112 * 112 * 3);
    for (int i = 0; i < 100; i++) {
      expect(tensor[i], greaterThanOrEqualTo(-1.0));
      expect(tensor[i], lessThanOrEqualTo(1.0));
    }
  });
}
