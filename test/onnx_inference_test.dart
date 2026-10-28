import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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
  test('ONNX Runtime matches Python output on sample_face_112.png', () async {
    OrtEnv.instance.init();

    final modelFile = File('assets/models/w600k_r50.onnx').existsSync()
        ? File('assets/models/w600k_r50.onnx')
        : File('assets/w600k_r50.onnx');
    final modelBytes = await modelFile.readAsBytes();
    final sessionOptions = OrtSessionOptions();
    final session = OrtSession.fromBuffer(modelBytes, sessionOptions);

    final imageBytes = await File('test/sample_face_112.png').readAsBytes();
    final image = img.decodeImage(imageBytes)!;
    expect(image.width, 112);
    expect(image.height, 112);

    // Build NCHW float array [1, 3, 112, 112]
    final floatList = Float32List(1 * 3 * 112 * 112);
    const planeSize = 112 * 112;
    int idx = 0;
    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = image.getPixel(x, y);
        floatList[idx] = (pixel.r / 127.5) - 1.0;
        floatList[planeSize + idx] = (pixel.g / 127.5) - 1.0;
        floatList[2 * planeSize + idx] = (pixel.b / 127.5) - 1.0;
        idx++;
      }
    }

    final inputOrt = OrtValueTensor.createTensorWithDataList(floatList, [1, 3, 112, 112]);
    final inputs = {'input.1': inputOrt};
    final runOptions = OrtRunOptions();

    final outputs = await session.runAsync(runOptions, inputs);
    final rawList = (outputs![0]?.value as List<List<double>>)[0];

    // L2 normalize
    final norm = sqrt(rawList.fold(0.0, (s, e) => s + e * e));
    final dartEmbedding = rawList.map((e) => e / norm).toList();

    // Read python embedding
    final pyJson = await File('test/sample_embedding.json').readAsString();
    final List<double> pyEmbedding = (jsonDecode(pyJson) as List).map((e) => (e as num).toDouble()).toList();

    expect(dartEmbedding.length, 512);
    expect(pyEmbedding.length, 512);

    // Calculate cosine similarity between Dart and Python embedding
    double dot = 0.0;
    for (int i = 0; i < 512; i++) {
      dot += dartEmbedding[i] * pyEmbedding[i];
    }

    // ignore: avoid_print
    print('Cosine similarity between Dart and Python: $dot');
    // ignore: avoid_print
    print('Dart first 5: ${dartEmbedding.take(5).toList()}');
    // ignore: avoid_print
    print('Python first 5: ${pyEmbedding.take(5).toList()}');

    expect(dot, greaterThan(0.9999));

    inputOrt.release();
    runOptions.release();
    for (final element in outputs) {
      element?.release();
    }
    session.release();
    sessionOptions.release();
    OrtEnv.instance.release();
  }, skip: _isOnnxAvailable ? null : 'libonnxruntime not available on host');
}
