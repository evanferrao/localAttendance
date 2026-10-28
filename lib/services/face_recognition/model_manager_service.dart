import 'dart:async';
import 'dart:io';

import 'package:face_att/utils/local_db.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Descriptor for a supported face recognition ONNX model
class ModelDescriptor {
  final String id;
  final String name;
  final String description;
  final String downloadUrl;
  final int estimatedSizeBytes;
  final bool isDefault;

  const ModelDescriptor({
    required this.id,
    required this.name,
    required this.description,
    required this.downloadUrl,
    required this.estimatedSizeBytes,
    this.isDefault = false,
  });

  String get formattedSize {
    final mb = estimatedSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Source location where a model is loaded from
enum ModelSourceType {
  downloaded,
  manuallySelected,
  bundledAsset,
  hostFilesystem,
}

/// Detailed information about an installed or available model
class ModelStatus {
  final String id;
  final String displayName;
  final ModelSourceType source;
  final String pathOrAsset;
  final int sizeBytes;
  final bool isActive;

  const ModelStatus({
    required this.id,
    required this.displayName,
    required this.source,
    required this.pathOrAsset,
    required this.sizeBytes,
    required this.isActive,
  });

  String get formattedSize {
    if (sizeBytes <= 0) return 'Unknown size';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get sourceLabel {
    switch (source) {
      case ModelSourceType.downloaded:
        return 'Downloaded';
      case ModelSourceType.manuallySelected:
        return 'Manually Imported';
      case ModelSourceType.bundledAsset:
        return 'Bundled in App';
      case ModelSourceType.hostFilesystem:
        return 'Local Filesystem';
    }
  }
}

/// Progress details emitted during model download
class ModelDownloadProgress {
  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSecond;
  final double progressPercent;

  const ModelDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.speedBytesPerSecond,
    required this.progressPercent,
  });

  String get formattedReceived {
    final mb = receivedBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get formattedTotal {
    if (totalBytes <= 0) return 'Unknown';
    final mb = totalBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get formattedSpeed {
    if (speedBytesPerSecond <= 0) return 'Calculating...';
    final mbps = speedBytesPerSecond / (1024 * 1024);
    return '${mbps.toStringAsFixed(1)} MB/s';
  }
}

/// Token to allow callers to cancel an in-flight download
class DownloadCancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

/// Service managing discovery, download, manual import, and active selection
/// of face recognition ONNX models.
class ModelManagerService {
  ModelManagerService._();
  static final ModelManagerService instance = ModelManagerService._();
  factory ModelManagerService() => instance;

  static const String settingsActiveModelPathKey = 'active_model_path';
  static const String settingsActiveModelNameKey = 'active_model_name';

  /// Pre-configured supported models from authoritative Hugging Face repositories
  static const List<ModelDescriptor> supportedModels = [
    ModelDescriptor(
      id: 'w600k_mbf.onnx',
      name: 'ArcFace MobileFaceNet',
      description: 'Lightweight & fast inference (~13 MB). Recommended for low-power mobile devices and quick downloads.',
      downloadUrl: 'https://huggingface.co/deepghs/insightface/resolve/main/buffalo_s/w600k_mbf.onnx',
      estimatedSizeBytes: 13812652,
      isDefault: true,
    ),
    ModelDescriptor(
      id: 'w600k_r50.onnx',
      name: 'ArcFace ResNet-50',
      description: 'High-accuracy benchmark model (~167 MB). Standard model for difficult lighting and camera angles.',
      downloadUrl: 'https://huggingface.co/maze/faceX/resolve/main/w600k_r50.onnx',
      estimatedSizeBytes: 174809796,
      isDefault: false,
    ),
    ModelDescriptor(
      id: 'glintr100.onnx',
      name: 'ArcFace ResNet-100',
      description: 'Maximum accuracy Glint360K model (~249 MB). Demanding on storage and device memory.',
      downloadUrl: 'https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/glintr100.onnx',
      estimatedSizeBytes: 260865038,
      isDefault: false,
    ),
  ];

  /// Get the app persistent directory reserved for downloaded/imported models
  Future<Directory> getModelsDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'models'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      // Fallback for tests or environments where path_provider is not mocked
      final dir = Directory('.models_cache');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }
  }

  /// Check whether any model is available on device (local files, bundled assets, or host tests)
  Future<bool> hasAnyModelAvailable() async {
    // 1. Check local models directory
    try {
      final modelsDir = await getModelsDirectory();
      if (await modelsDir.exists()) {
        final entries = modelsDir.listSync();
        for (final entry in entries) {
          if (entry is File && entry.path.endsWith('.onnx') && entry.lengthSync() > 1024 * 1024) {
            return true;
          }
        }
      }
    } catch (_) {}

    // 2. Check bundled asset candidates
    final assetCandidates = [
      'assets/models/w600k_mbf.onnx',
      'assets/models/w600k_r50.onnx',
      'assets/w600k_mbf.onnx',
      'assets/w600k_r50.onnx',
      'assets/models/glintr100.onnx',
      'assets/glintr100.onnx',
    ];

    for (final assetPath in assetCandidates) {
      try {
        await rootBundle.load(assetPath);
        return true;
      } catch (_) {}
    }

    // 3. Check host test filesystem
    final hostCandidates = [
      'assets/models/w600k_r50.onnx',
      'assets/w600k_r50.onnx',
      'assets/models/w600k_mbf.onnx',
      'assets/w600k_mbf.onnx',
      'models/w600k_r50.onnx',
      'models/w600k_mbf.onnx',
    ];

    for (final hostPath in hostCandidates) {
      final f = File(hostPath);
      if (f.existsSync() && f.lengthSync() > 1024 * 1024) {
        return true;
      }
    }

    return false;
  }

  /// Load model bytes and path for the currently active model.
  /// Throws [StateError] if no model is found.
  Future<({Uint8List bytes, String path, String displayName, ModelSourceType source})> loadActiveModel() async {
    // 1. Check explicitly configured active model path in settings
    String? configuredPath;
    try {
      configuredPath = HiveBoxes.settings.get(settingsActiveModelPathKey) as String?;
    } catch (_) {}

    if (configuredPath != null && configuredPath.isNotEmpty) {
      final file = File(configuredPath);
      if (await file.exists() && await file.length() > 1024 * 1024) {
        final bytes = await file.readAsBytes();
        final name = (HiveBoxes.settings.get(settingsActiveModelNameKey) as String?) ??
            p.basenameWithoutExtension(configuredPath);
        return (
          bytes: bytes,
          path: configuredPath,
          displayName: name,
          source: ModelSourceType.downloaded,
        );
      }
    }

    // 2. Check local models directory for existing .onnx files
    try {
      final modelsDir = await getModelsDirectory();
      if (await modelsDir.exists()) {
        final files = modelsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.onnx') && f.lengthSync() > 1024 * 1024)
            .toList();

        if (files.isNotEmpty) {
          // Prefer default model if present
          final preferred = files.firstWhere(
            (f) => f.path.contains('w600k_mbf') || f.path.contains('w600k_r50'),
            orElse: () => files.first,
          );
          final bytes = await preferred.readAsBytes();
          final name = p.basenameWithoutExtension(preferred.path);
          return (
            bytes: bytes,
            path: preferred.path,
            displayName: name,
            source: ModelSourceType.downloaded,
          );
        }
      }
    } catch (_) {}

    // 3. Check bundled assets
    final assetCandidates = [
      ('assets/models/w600k_r50.onnx', 'ArcFace ResNet-50 (Bundled)'),
      ('assets/w600k_r50.onnx', 'ArcFace ResNet-50 (Bundled)'),
      ('assets/models/w600k_mbf.onnx', 'ArcFace MobileFaceNet (Bundled)'),
      ('assets/w600k_mbf.onnx', 'ArcFace MobileFaceNet (Bundled)'),
      ('assets/models/glintr100.onnx', 'ArcFace ResNet-100 (Bundled)'),
      ('assets/glintr100.onnx', 'ArcFace ResNet-100 (Bundled)'),
    ];

    for (final candidate in assetCandidates) {
      try {
        final data = await rootBundle.load(candidate.$1);
        return (
          bytes: data.buffer.asUint8List(),
          path: candidate.$1,
          displayName: candidate.$2,
          source: ModelSourceType.bundledAsset,
        );
      } catch (_) {}
    }

    // 4. Check host filesystem (for tests)
    final hostCandidates = [
      'assets/models/w600k_r50.onnx',
      'assets/w600k_r50.onnx',
      'assets/models/w600k_mbf.onnx',
      'assets/w600k_mbf.onnx',
      'models/w600k_r50.onnx',
      'models/w600k_mbf.onnx',
    ];

    for (final hostPath in hostCandidates) {
      final f = File(hostPath);
      if (f.existsSync() && f.lengthSync() > 1024 * 1024) {
        final bytes = await f.readAsBytes();
        return (
          bytes: bytes,
          path: hostPath,
          displayName: p.basenameWithoutExtension(hostPath),
          source: ModelSourceType.hostFilesystem,
        );
      }
    }

    throw StateError(
      'No face recognition model available. Please download a model or select a model file manually.',
    );
  }

  /// Download a supported model with streaming progress and redirect handling
  Future<File> downloadModel(
    ModelDescriptor model, {
    void Function(ModelDownloadProgress progress)? onProgress,
    DownloadCancellationToken? cancellationToken,
  }) async {
    final modelsDir = await getModelsDirectory();
    final targetFile = File(p.join(modelsDir.path, model.id));
    final tempFile = File(p.join(modelsDir.path, '${model.id}.download.tmp'));

    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      var currentUrl = Uri.parse(model.downloadUrl);
      HttpClientResponse? response;
      const maxRedirects = 5;
      var redirectCount = 0;

      while (redirectCount < maxRedirects) {
        if (cancellationToken?.isCancelled == true) {
          throw Exception('Download cancelled by user.');
        }

        final request = await client.getUrl(currentUrl);
        request.headers.set('User-Agent', 'localAttendance-App/1.0 (Linux; Android)');
        response = await request.close();

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location != null && location.isNotEmpty) {
            currentUrl = currentUrl.resolve(location);
            redirectCount++;
            continue;
          }
        }
        break;
      }

      if (response == null || response.statusCode != 200) {
        throw Exception(
          'Failed to download model (HTTP ${response?.statusCode ?? "no response"}).',
        );
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : model.estimatedSizeBytes;

      var receivedBytes = 0;
      final sink = tempFile.openWrite();
      final stopwatch = Stopwatch()..start();
      var lastEmittedBytes = 0;
      var lastEmittedTimeMs = 0;
      var smoothedSpeed = 0.0;

      await for (final chunk in response) {
        if (cancellationToken?.isCancelled == true) {
          await sink.close();
          if (tempFile.existsSync()) tempFile.deleteSync();
          throw Exception('Download cancelled by user.');
        }

        sink.add(chunk);
        receivedBytes += chunk.length;

        final elapsedMs = stopwatch.elapsedMilliseconds;
        if (elapsedMs - lastEmittedTimeMs >= 200 || receivedBytes >= totalBytes) {
          final deltaBytes = receivedBytes - lastEmittedBytes;
          final deltaTimeSec = (elapsedMs - lastEmittedTimeMs) / 1000.0;
          if (deltaTimeSec > 0) {
            final instantSpeed = deltaBytes / deltaTimeSec;
            smoothedSpeed = smoothedSpeed == 0.0
                ? instantSpeed
                : (smoothedSpeed * 0.7 + instantSpeed * 0.3);
          }

          final progress = ModelDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            speedBytesPerSecond: smoothedSpeed,
            progressPercent: totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0,
          );
          onProgress?.call(progress);

          lastEmittedBytes = receivedBytes;
          lastEmittedTimeMs = elapsedMs;
        }
      }

      await sink.flush();
      await sink.close();

      if (!tempFile.existsSync() || tempFile.lengthSync() < 1024 * 1024) {
        throw Exception('Downloaded file is invalid or incomplete.');
      }

      // Atomically replace target
      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      tempFile.renameSync(targetFile.path);

      // Persist active model in settings
      await HiveBoxes.settings.put(settingsActiveModelPathKey, targetFile.path);
      await HiveBoxes.settings.put(settingsActiveModelNameKey, model.name);

      debugPrint('[ModelManager] Model ${model.id} downloaded successfully to ${targetFile.path}');
      return targetFile;
    } catch (e) {
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Manually select and import a local .onnx model file from device storage via system file picker
  Future<File?> pickAndImportModelFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['onnx', 'bin'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty || result.files.single.path == null) {
      return null;
    }

    final sourcePath = result.files.single.path!;
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      throw Exception('Selected file could not be found.');
    }

    final length = await sourceFile.length();
    if (length < 1024 * 1024) {
      throw Exception('Selected file is smaller than 1 MB and does not appear to be a valid ONNX model.');
    }

    final filename = result.files.single.name;
    final modelsDir = await getModelsDirectory();
    final targetFile = File(p.join(modelsDir.path, filename));

    // Copy to persistent storage
    await sourceFile.copy(targetFile.path);

    // Save in settings
    await HiveBoxes.settings.put(settingsActiveModelPathKey, targetFile.path);
    await HiveBoxes.settings.put(settingsActiveModelNameKey, p.basenameWithoutExtension(filename));

    debugPrint('[ModelManager] Manually imported model $filename to ${targetFile.path}');
    return targetFile;
  }

  /// List all models currently available or installed on device
  Future<List<ModelStatus>> getInstalledModels() async {
    final list = <ModelStatus>[];
    String? activePath;
    try {
      activePath = HiveBoxes.settings.get(settingsActiveModelPathKey) as String?;
    } catch (_) {}

    // Check local models directory
    try {
      final modelsDir = await getModelsDirectory();
      if (await modelsDir.exists()) {
        for (final entry in modelsDir.listSync()) {
          if (entry is File && entry.path.endsWith('.onnx')) {
            final size = entry.lengthSync();
            final name = p.basenameWithoutExtension(entry.path);
            list.add(
              ModelStatus(
                id: p.basename(entry.path),
                displayName: name,
                source: ModelSourceType.downloaded,
                pathOrAsset: entry.path,
                sizeBytes: size,
                isActive: activePath == entry.path,
              ),
            );
          }
        }
      }
    } catch (_) {}

    // Check bundled assets
    final assetCandidates = [
      ('assets/models/w600k_r50.onnx', 'ArcFace ResNet-50'),
      ('assets/w600k_r50.onnx', 'ArcFace ResNet-50'),
      ('assets/models/w600k_mbf.onnx', 'ArcFace MobileFaceNet'),
      ('assets/w600k_mbf.onnx', 'ArcFace MobileFaceNet'),
    ];

    for (final candidate in assetCandidates) {
      try {
        final data = await rootBundle.load(candidate.$1);
        final isAlreadyListed = list.any((m) => m.pathOrAsset == candidate.$1);
        if (!isAlreadyListed) {
          list.add(
            ModelStatus(
              id: p.basename(candidate.$1),
              displayName: candidate.$2,
              source: ModelSourceType.bundledAsset,
              pathOrAsset: candidate.$1,
              sizeBytes: data.lengthInBytes,
              isActive: activePath == null || activePath == candidate.$1,
            ),
          );
        }
      } catch (_) {}
    }

    return list;
  }

  /// Delete a locally downloaded or imported model file
  Future<void> deleteModel(String modelId) async {
    final modelsDir = await getModelsDirectory();
    final file = File(p.join(modelsDir.path, modelId));
    if (await file.exists()) {
      await file.delete();
    }

    final activePath = HiveBoxes.settings.get(settingsActiveModelPathKey) as String?;
    if (activePath != null && activePath.endsWith(modelId)) {
      await HiveBoxes.settings.delete(settingsActiveModelPathKey);
      await HiveBoxes.settings.delete(settingsActiveModelNameKey);
    }
  }

  /// Switch active model to an installed path or asset
  Future<void> setActiveModel(ModelStatus model) async {
    await HiveBoxes.settings.put(settingsActiveModelPathKey, model.pathOrAsset);
    await HiveBoxes.settings.put(settingsActiveModelNameKey, model.displayName);
  }
}
