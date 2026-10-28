import 'dart:io';

/// Utility to configure the Flutter project between a Smaller Build (Slim)
/// where models are downloaded on first app setup or loaded manually,
/// and a Bundled Build (Full) where models are pre-packaged into the APK.
void main(List<String> args) {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('[Error] pubspec.yaml not found in current directory.');
    exit(1);
  }

  final isSlim = args.contains('--slim') || args.contains('--smaller') || args.contains('--lean');
  final isBundled = args.contains('--bundled') || args.contains('--full');
  final isStatus = args.contains('--status') || args.isEmpty;

  final content = pubspecFile.readAsStringSync();
  final hasBundledModels = content.contains('- assets/models/');

  if (isStatus && !isSlim && !isBundled) {
    stdout.writeln('=== Local Attendance Build Configuration ===');
    if (hasBundledModels) {
      stdout.writeln('Current Mode: BUNDLED BUILD (Full Offline)');
      stdout.writeln('Assets: Models in assets/models/ are packaged directly inside the APK/AAB.');
      stdout.writeln('Estimated APK Size: ~200 MB - 450 MB');
      stdout.writeln('App Behavior: Runs out-of-the-box with bundled models.');
    } else {
      stdout.writeln('Current Mode: SMALLER BUILD (Slim / Lean)');
      stdout.writeln('Assets: Only lightweight app assets are packaged. Models are NOT bundled.');
      stdout.writeln('Estimated APK Size: ~20 MB - 25 MB');
      stdout.writeln('App Behavior: Prompts user to download models on first setup or select .onnx file manually.');
    }
    stdout.writeln('\nUsage:');
    stdout.writeln('  fvm dart run tool/configure_build.dart --slim     # Configure smaller build (~25 MB)');
    stdout.writeln('  fvm dart run tool/configure_build.dart --bundled  # Configure bundled build (~200+ MB)');
    return;
  }

  if (isSlim) {
    if (!hasBundledModels) {
      stdout.writeln('[Build Config] Already configured for Smaller Build (Slim).');
      stdout.writeln('[Build Config] APK size will be minimized (~25 MB). Models are excluded from package.');
      return;
    }

    // Remove - assets/models/
    final updated = content
        .replaceAll(RegExp(r'\n\s*-\s*assets/models/'), '')
        .replaceAll(RegExp(r'\n\s*-\s*assets/models'), '');

    pubspecFile.writeAsStringSync(updated);
    stdout.writeln('[Build Config] Successfully configured for SMALLER BUILD (Slim / Lean).');
    stdout.writeln('[Build Config] Models removed from APK assets.');
    stdout.writeln('[Build Config] Resulting APK size: ~20 MB - 25 MB.');
    stdout.writeln('[Build Config] On first setup, the app will download models or ask user to select .onnx file.');
    stdout.writeln('\nNext Step: Run `fvm flutter build apk --release` (or `fvm flutter build appbundle --release`).');
    return;
  }

  if (isBundled) {
    if (hasBundledModels) {
      stdout.writeln('[Build Config] Already configured for Bundled Build (Full Offline).');
      stdout.writeln('[Build Config] Models in assets/models/ are included in the package.');
      return;
    }

    // Add - assets/models/ after - assets/
    if (content.contains('- assets/')) {
      final updated = content.replaceFirst(
        '- assets/',
        '- assets/\n    - assets/models/',
      );
      pubspecFile.writeAsStringSync(updated);
    } else {
      stderr.writeln('[Error] Could not find "- assets/" in pubspec.yaml.');
      exit(1);
    }

    stdout.writeln('[Build Config] Successfully configured for BUNDLED BUILD (Full Offline).');
    stdout.writeln('[Build Config] Models from assets/models/ will be pre-packaged into APK assets.');
    stdout.writeln('[Build Config] Resulting APK size: ~200 MB+.');
    stdout.writeln('[Build Config] Works out-of-the-box offline without first-setup downloads.');
    stdout.writeln('\nNext Step: Run `fvm flutter build apk --release` (or `fvm flutter build appbundle --release`).');
    return;
  }
}
