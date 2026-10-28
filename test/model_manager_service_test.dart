import 'dart:io';

import 'package:face_att/services/face_recognition/model_manager_service.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_manager_test_');
    Hive.init(tempDir.path);
    await HiveBoxes.initialize();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ModelDescriptor & ModelStatus tests', () {
    test('ModelDescriptor provides accurate formatted sizes', () {
      const descMbf = ModelDescriptor(
        id: 'w600k_mbf.onnx',
        name: 'MobileFaceNet',
        description: 'Fast mobile model',
        downloadUrl: 'https://example.com/mbf.onnx',
        estimatedSizeBytes: 13 * 1024 * 1024,
      );
      expect(descMbf.formattedSize, '13.0 MB');

      const descR50 = ModelDescriptor(
        id: 'w600k_r50.onnx',
        name: 'ResNet-50',
        description: 'Standard model',
        downloadUrl: 'https://example.com/r50.onnx',
        estimatedSizeBytes: 167 * 1024 * 1024,
      );
      expect(descR50.formattedSize, '167.0 MB');
    });

    test('ModelStatus formats source labels correctly', () {
      const status1 = ModelStatus(
        id: 'mbf.onnx',
        displayName: 'MobileFaceNet',
        source: ModelSourceType.downloaded,
        pathOrAsset: '/dummy/path',
        sizeBytes: 13812652,
        isActive: true,
      );
      expect(status1.sourceLabel, 'Downloaded');
      expect(status1.formattedSize, '13.2 MB');

      const status2 = ModelStatus(
        id: 'r50.onnx',
        displayName: 'ResNet-50',
        source: ModelSourceType.bundledAsset,
        pathOrAsset: 'assets/models/r50.onnx',
        sizeBytes: 174809796,
        isActive: false,
      );
      expect(status2.sourceLabel, 'Bundled in App');
      expect(status2.formattedSize, '166.7 MB');
    });

    test('ModelDownloadProgress calculates speed and percentage', () {
      const progress = ModelDownloadProgress(
        receivedBytes: 6500000,
        totalBytes: 13000000,
        speedBytesPerSecond: 2500000,
        progressPercent: 0.5,
      );
      expect(progress.formattedReceived, '6.2 MB');
      expect(progress.formattedTotal, '12.4 MB');
      expect(progress.formattedSpeed, '2.4 MB/s');
      expect(progress.progressPercent, 0.5);
    });

    test('DownloadCancellationToken properly flags cancellation', () {
      final token = DownloadCancellationToken();
      expect(token.isCancelled, isFalse);
      token.cancel();
      expect(token.isCancelled, isTrue);
    });
  });

  group('ModelManagerService discovery and active model loading', () {
    test('hasAnyModelAvailable returns true when local model or test model exists', () async {
      final service = ModelManagerService.instance;
      final available = await service.hasAnyModelAvailable();
      // On development host, assets/models/w600k_r50.onnx exists
      expect(available, isTrue);
    });

    test('loadActiveModel returns model bytes from configured or discovered file', () async {
      final service = ModelManagerService.instance;
      final result = await service.loadActiveModel();
      expect(result.bytes.isNotEmpty, isTrue);
      expect(result.path.isNotEmpty, isTrue);
    });

    test('Active model settings persistence updates Hive settings box', () async {
      final service = ModelManagerService.instance;
      const model = ModelStatus(
        id: 'custom_test.onnx',
        displayName: 'Custom Test Model',
        source: ModelSourceType.manuallySelected,
        pathOrAsset: '/tmp/custom_test.onnx',
        sizeBytes: 15000000,
        isActive: true,
      );

      await service.setActiveModel(model);
      expect(HiveBoxes.settings.get(ModelManagerService.settingsActiveModelPathKey), '/tmp/custom_test.onnx');
      expect(HiveBoxes.settings.get(ModelManagerService.settingsActiveModelNameKey), 'Custom Test Model');
    });
  });
}
