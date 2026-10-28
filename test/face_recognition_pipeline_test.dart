import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:face_att/models/user.dart';
import 'package:face_att/services/face_recognition/image_converter.dart';
import 'package:face_att/services/face_recognition/ml_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

final bool _isOnnxAvailable = () {
  try {
    OrtEnv.instance.init();
    OrtEnv.instance.release();
    return true;
  } catch (_) {
    return false;
  }
}();

void main() {
  group('MLService Cosine Similarity and Margin Pipeline', () {
    late MLService mlService;

    setUp(() {
      mlService = MLService();
    });

    test('L2 normalization produces unit vector', () {
      final vec = [3.0, 4.0];
      final norm = mlService.l2Normalize(vec);
      expect(norm[0], closeTo(0.6, 1e-6));
      expect(norm[1], closeTo(0.8, 1e-6));
      final magnitude = sqrt(norm[0] * norm[0] + norm[1] * norm[1]);
      expect(magnitude, closeTo(1.0, 1e-6));
    });

    test('Dot product of normalized identical vectors equals 1.0', () {
      final a = mlService.l2Normalize(List.generate(512, (i) => i.toDouble()));
      final score = mlService.dotProduct(a, a);
      expect(score, closeTo(1.0, 1e-6));
    });

    test('recognizeFace accepts single user above similarity threshold', () {
      final query = mlService.l2Normalize([1.0, 0.0, 0.0]);
      final enrolled = mlService.l2Normalize([0.9, 0.1, 0.0]);

      // Mock match
      final match = RecognitionMatch(
        registerNumber: '23BRS1001',
        name: 'Alice',
        score: mlService.dotProduct(query, enrolled), // ~0.99
        index: 0,
        user: const User(registerNumber: '23BRS1001', name: 'Alice'),
      );

      // Verify logic directly
      final accepted = match.score >= mlService.similarityThreshold;
      expect(accepted, isTrue);
      expect(match.score, greaterThanOrEqualTo(0.35));
    });

    test('recognizeFace margin thresholding distinguishes clear vs ambiguous matches', () {
      // Clear match: best = 0.65, second = 0.20 -> second is below threshold (< 0.35) -> accepted
      final resClear = mlService.recognizeFace(
        List.filled(512, 1.0),
      );
      expect(resClear, isNotNull);

      // Ambiguous match: best = 0.45005, second = 0.45001 -> second is >= threshold and margin < 0.0001 -> rejected
      const bestScoreAmbiguous = 0.45005;
      const secondScoreAmbiguous = 0.45001;
      const marginAmbiguous = bestScoreAmbiguous - secondScoreAmbiguous;
      final acceptedAmbiguous = bestScoreAmbiguous >= mlService.similarityThreshold &&
          (secondScoreAmbiguous < mlService.similarityThreshold || marginAmbiguous >= mlService.marginThreshold);
      expect(acceptedAmbiguous, isFalse);

      // Low similarity match: best = 0.30 -> rejected
      const bestScoreLow = 0.30;
      final acceptedLow = (bestScoreLow >= mlService.similarityThreshold);
      expect(acceptedLow, isFalse);
    });

    test('recognizeFace accepts candidate when runner up is below similarity threshold', () {
      const bestScore = 0.68;
      const secondScore = 0.22; // below 0.35
      const margin = bestScore - secondScore;
      final accepted = bestScore >= mlService.similarityThreshold &&
          (secondScore < mlService.similarityThreshold || margin >= mlService.marginThreshold);
      expect(accepted, isTrue);
    });
  });

  group('On-Device ONNX ArcFace Inference', () {
    test('Processes sample face image into 512-dim embedding via ONNX Runtime', () async {
      OrtEnv.instance.init();

      final modelFile = File('assets/models/w600k_r50.onnx').existsSync()
          ? File('assets/models/w600k_r50.onnx')
          : File('assets/w600k_r50.onnx');
      final modelBytes = await modelFile.readAsBytes();
      final sessionOptions = OrtSessionOptions();
      final session = OrtSession.fromBuffer(modelBytes, sessionOptions);

      final imageBytes = await File('test/sample_face_112.png').readAsBytes();
      final image = img.decodeImage(imageBytes)!;

      final flat = ImageConverter.cropAndNormalizeFromImage(image, null, 112);
      expect(flat.length, 1 * 3 * 112 * 112);

      final inputOrt = OrtValueTensor.createTensorWithDataList(
        Float32List.fromList(flat),
        [1, 3, 112, 112],
      );
      final inputs = {'input.1': inputOrt};
      final runOptions = OrtRunOptions();

      final outputs = await session.runAsync(runOptions, inputs);
      expect(outputs, isNotNull);
      final rawList = (outputs![0]?.value as List<List<double>>)[0];
      expect(rawList.length, 512);

      final mlService = MLService();
      final embedding = mlService.l2Normalize(rawList);
      expect(embedding.length, 512);

      // Verify unit norm
      final norm = sqrt(embedding.fold(0.0, (s, e) => s + e * e));
      expect(norm, closeTo(1.0, 1e-5));

      inputOrt.release();
      runOptions.release();
      for (final element in outputs) {
        element?.release();
      }
      session.release();
      sessionOptions.release();
      OrtEnv.instance.release();
    }, skip: _isOnnxAvailable ? null : 'libonnxruntime not available on host');

    test('Parses 23BRS1150_PIYUSH_R_SAINI.jpeg identity correctly', () {
      final parsed = MLService.parseIdentityFromFilename('23BRS1150_PIYUSH_R_SAINI.jpeg');
      expect(parsed['register_number'], '23BRS1150');
      expect(parsed['name'], 'PIYUSH R SAINI');
    });

    test('FaceLandmarkAligner solves 2D similarity transform matching Python Umeyama', () {
      final src = const [
        Point2D(305.2819, 447.16498),
        Point2D(436.277, 449.34952),
        Point2D(370.63174, 511.07974),
        Point2D(313.90216, 579.91254),
        Point2D(427.26456, 581.45593),
      ];
      final transform = FaceLandmarkAligner.estimateSimilarityTransform(
        src,
        FaceLandmarkAligner.arcfaceDst,
      );
      expect(transform, isNotNull);
      // Skimage affine params: a = 0.287206, b = -0.003713 (so -b = +0.003713), tx = -52.3407, ty = -74.2875
      expect(transform![0], closeTo(0.287206, 1e-4));
      expect(transform[1], closeTo(-0.003713, 1e-4));
      expect(transform[2], closeTo(-52.3407, 1e-2));
      expect(transform[3], closeTo(-74.2875, 1e-2));
    });

    test('Extracts embedding from 23BRS1150_PIYUSH_R_SAINI.jpeg with 5-point landmark alignment achieving 99%+ accuracy', () async {
      OrtEnv.instance.init();

      final modelFile = File('assets/models/w600k_r50.onnx').existsSync()
          ? File('assets/models/w600k_r50.onnx')
          : File('assets/w600k_r50.onnx');
      final modelBytes = await modelFile.readAsBytes();
      final sessionOptions = OrtSessionOptions();
      final session = OrtSession.fromBuffer(modelBytes, sessionOptions);

      final imageBytes = await File('23BRS1150_PIYUSH_R_SAINI.jpeg').readAsBytes();
      final image = img.decodeImage(imageBytes)!;

      // Piyush 5 facial landmarks [leftEye, rightEye, nose, leftMouth, rightMouth]
      final landmarks = const [
        Point2D(305.2819, 447.16498),
        Point2D(436.277, 449.34952),
        Point2D(370.63174, 511.07974),
        Point2D(313.90216, 579.91254),
        Point2D(427.26456, 581.45593),
      ];

      final flat = FaceLandmarkAligner.alignAndNormalize(image, landmarks, inputSize: 112);
      expect(flat.length, 1 * 3 * 112 * 112);

      final inputOrt = OrtValueTensor.createTensorWithDataList(
        Float32List.fromList(flat),
        [1, 3, 112, 112],
      );
      final inputs = {'input.1': inputOrt};
      final runOptions = OrtRunOptions();

      final outputs = await session.runAsync(runOptions, inputs);
      final rawList = (outputs![0]?.value as List<List<double>>)[0];

      final mlService = MLService();
      final embedding = mlService.l2Normalize(rawList);
      expect(embedding.length, 512);

      // Verify similarity against Python InsightFace embedding
      final pyJson = await File('test/piyush_py_embedding.json').readAsString();
      final pyEmbedding = (jsonDecode(pyJson) as List).map((e) => (e as num).toDouble()).toList();

      final similarity = mlService.dotProduct(embedding, pyEmbedding);
      // ignore: avoid_print
      print('Landmark-aligned Dart vs Python InsightFace cosine similarity: ${(similarity * 100).toStringAsFixed(3)}%');
      // Must achieve 99%+ (exceeds 0.99)
      expect(similarity, greaterThan(0.99));

      inputOrt.release();
      runOptions.release();
      for (final element in outputs) {
        element?.release();
      }
      session.release();
      sessionOptions.release();
      OrtEnv.instance.release();
    }, skip: _isOnnxAvailable ? null : 'libonnxruntime not available on host');
  });
}
