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
  final Uint8List nv21Bytes; // full NV21 buffer (Y plane + interleaved VU)
  final Rect boundingBox;
  final int inputSize;

  CropNormalizeArgs({
    required this.width,
    required this.height,
    required this.nv21Bytes,
    required this.boundingBox,
    required this.inputSize,
  });
}

class ImageConverter {
  /// Builds args from a CameraImage (NV21 = 1 plane, or YUV420 = 3 planes)
  static CropNormalizeArgs buildArgs(CameraImage image, Face face, int inputSize) {
    final Uint8List nv21;

    if (image.planes.length == 1) {
      // NV21: single plane with Y followed by interleaved VU
      nv21 = image.planes[0].bytes;
    } else {
      // YUV420 (3 planes): manually pack into NV21 layout
      nv21 = _yuv420ToNv21(image);
    }

    return CropNormalizeArgs(
      width: image.width,
      height: image.height,
      nv21Bytes: nv21,
      boundingBox: face.boundingBox,
      inputSize: inputSize,
    );
  }

  /// Pack YUV420 3-plane into NV21 single buffer
  static Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(width * height + (width * height ~/ 2));

    // Copy Y plane row by row (may have padding)
    int dstIdx = 0;
    for (int row = 0; row < height; row++) {
      nv21.setRange(
        dstIdx,
        dstIdx + width,
        yPlane.bytes,
        row * yPlane.bytesPerRow,
      );
      dstIdx += width;
    }

    // Interleave V and U into NV21 (VU order)
    final int uvHeight = height ~/ 2;
    final int uvWidth = width ~/ 2;
    final int uvPixelStride = vPlane.bytesPerPixel ?? 1;

    for (int row = 0; row < uvHeight; row++) {
      for (int col = 0; col < uvWidth; col++) {
        final int uvIdx = row * vPlane.bytesPerRow + col * uvPixelStride;
        nv21[dstIdx++] = vPlane.bytes[uvIdx];
        nv21[dstIdx++] = uPlane.bytes[uvIdx];
      }
    }

    return nv21;
  }

  /// Top-level function — safe to run in compute() isolate
  static List<double> cropAndNormalizeIsolate(CropNormalizeArgs args) {
    final fullImage = _nv21ToRgb(args.width, args.height, args.nv21Bytes);
    return _cropAndNormalize(fullImage, args.boundingBox, args.inputSize);
  }

  /// Convert NV21 buffer to RGB image
  static img.Image _nv21ToRgb(int width, int height, Uint8List nv21) {
    final rgb = Uint8List(width * height * 3);
    final int frameSize = width * height;
    int idx = 0;

    for (int j = 0; j < height; j++) {
      for (int i = 0; i < width; i++) {
        final int yVal = nv21[j * width + i] & 0xFF;

        // NV21: VU interleaved starting at frameSize
        final int uvOffset = frameSize + (j ~/ 2) * width + (i & ~1);
        final int vVal = nv21[uvOffset] & 0xFF;
        final int uVal = nv21[uvOffset + 1] & 0xFF;

        final int r = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toInt();
        final int g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).clamp(0, 255).toInt();
        final int b = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();

        rgb[idx++] = r;
        rgb[idx++] = g;
        rgb[idx++] = b;
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
