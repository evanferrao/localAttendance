import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

/// Data class passed into the isolate — no platform objects allowed
class CropNormalizeArgs {
  final int width;
  final int height;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final Rect boundingBox;
  final int inputSize;

  CropNormalizeArgs({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.boundingBox,
    required this.inputSize,
  });
}

class ImageConverter {
  /// Builds args to pass to the isolate from a CameraImage + Face
  static CropNormalizeArgs buildArgs(CameraImage image, Face face, int inputSize) {
    return CropNormalizeArgs(
      width: image.width,
      height: image.height,
      yBytes: image.planes[0].bytes,
      uBytes: image.planes[1].bytes,
      vBytes: image.planes[2].bytes,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
      boundingBox: face.boundingBox,
      inputSize: inputSize,
    );
  }

  /// Top-level function — safe to run in compute() isolate
  static List<double> cropAndNormalizeIsolate(CropNormalizeArgs args) {
    final fullImage = _convertYUV420(
      args.width,
      args.height,
      args.yBytes,
      args.uBytes,
      args.vBytes,
      args.yRowStride,
      args.uvRowStride,
      args.uvPixelStride,
    );
    return _cropAndNormalize(fullImage, args.boundingBox, args.inputSize);
  }

  static img.Image _convertYUV420(
    int width,
    int height,
    Uint8List yBytes,
    Uint8List uBytes,
    Uint8List vBytes,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
  ) {
    // Build a flat RGB byte buffer — much faster than setPixelRgb per pixel
    final rgb = Uint8List(width * height * 3);
    int idx = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yVal = yBytes[y * yRowStride + x];
        final int uvIdx = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
        final int uVal = uBytes[uvIdx];
        final int vVal = vBytes[uvIdx];

        rgb[idx++] = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toInt();
        rgb[idx++] = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).clamp(0, 255).toInt();
        rgb[idx++] = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();
      }
    }

    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgb.buffer,
      numChannels: 3,
    );
  }

  static List<double> _cropAndNormalize(img.Image fullImage, Rect rect, int inputSize) {
    final double padding = rect.width * 0.2;
    final int x = max(0, (rect.left - padding).toInt());
    final int y = max(0, (rect.top - padding).toInt());
    final int w = min(fullImage.width - x, (rect.width + padding * 2).toInt());
    final int h = min(fullImage.height - y, (rect.height + padding * 2).toInt());

    final cropped = img.copyCrop(fullImage, x: x, y: y, width: w, height: h);
    final resized = img.copyResize(cropped, width: inputSize, height: inputSize);

    final result = List<double>.filled(inputSize * inputSize * 3, 0.0);
    int i = 0;
    for (int py = 0; py < inputSize; py++) {
      for (int px = 0; px < inputSize; px++) {
        final pixel = resized.getPixel(px, py);
        result[i++] = (pixel.r / 127.5) - 1.0;
        result[i++] = (pixel.g / 127.5) - 1.0;
        result[i++] = (pixel.b / 127.5) - 1.0;
      }
    }
    return result;
  }
}
