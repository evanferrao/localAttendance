import 'dart:io';

/// Map of available models and their download URLs
const Map<String, String> modelUrls = {
  'w600k_r50.onnx':
      'https://huggingface.co/maze/faceX/resolve/main/w600k_r50.onnx',
  'w600k_mbf.onnx':
      'https://huggingface.co/deepghs/insightface/resolve/main/buffalo_s/w600k_mbf.onnx',
  'glintr100.onnx':
      'https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/glintr100.onnx',
};

/// Models required by default for face recognition
const List<String> defaultModels = [
  'w600k_r50.onnx',
  'w600k_mbf.onnx',
];

Future<void> main(List<String> args) async {
  final includeAll = args.contains('--all');
  final targetModels = includeAll ? modelUrls.keys.toList() : defaultModels;

  final projectRoot = Directory.current;
  final assetsDir = Directory('${projectRoot.path}/assets');
  if (!assetsDir.existsSync()) {
    assetsDir.createSync(recursive: true);
  }

  stdout.writeln('=== Checking Face Recognition Models ===');

  for (final modelName in targetModels) {
    final url = modelUrls[modelName]!;
    final targetFile = File('${assetsDir.path}/$modelName');

    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      final sizeMb = (targetFile.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
      stdout.writeln('✓ $modelName already exists ($sizeMb MB). Skipping.');
      continue;
    }

    stdout.writeln('⬇ Downloading $modelName from $url...');
    final tempFile = File('${assetsDir.path}/$modelName.tmp');

    try {
      await _downloadFile(url, tempFile);
      if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
        tempFile.renameSync(targetFile.path);
        final sizeMb = (targetFile.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
        stdout.writeln('✓ Successfully downloaded $modelName ($sizeMb MB)');
      } else {
        stderr.writeln('✗ Download completed but file is empty for $modelName');
      }
    } catch (e) {
      stderr.writeln('✗ Error downloading $modelName: $e');
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    }
  }

  stdout.writeln('=== Model Check Complete ===');
}

Future<void> _downloadFile(String urlString, File destination) async {
  final client = HttpClient();
  client.userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';

  try {
    var uri = Uri.parse(urlString);
    HttpClientRequest request;
    HttpClientResponse response;

    // Follow redirects (Hugging Face redirects to CDN)
    var redirectCount = 0;
    const maxRedirects = 5;

    while (true) {
      request = await client.getUrl(uri);
      request.followRedirects = false;
      response = await request.close();

      if (response.isRedirect && redirectCount < maxRedirects) {
        redirectCount++;
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw Exception('Redirect received without Location header');
        }
        uri = Uri.parse(location);
        continue;
      }
      break;
    }

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('Failed to download file: HTTP ${response.statusCode}');
    }

    final contentLength = response.contentLength;
    var downloadedBytes = 0;
    var lastPercent = -1;

    final outputSink = destination.openWrite();
    await for (final chunk in response) {
      outputSink.add(chunk);
      downloadedBytes += chunk.length;

      if (contentLength > 0) {
        final percent = ((downloadedBytes / contentLength) * 100).toInt();
        if (percent % 10 == 0 && percent != lastPercent) {
          final downMb = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
          final totalMb = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          stdout.writeln('  -> Progress: $percent% ($downMb MB / $totalMb MB)');
          lastPercent = percent;
        }
      }
    }

    await outputSink.flush();
    await outputSink.close();
  } finally {
    client.close();
  }
}
