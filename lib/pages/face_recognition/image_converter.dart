import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

class CropNormalizeArgs {
  final int width;
  final int height;
  final Uint8List nv21Bytes;
  final Rect boundingBox;
  final int inputSize;
  final int sensorOrientation; // degrees: 0, 90, 180, 270

  CropNormalizeArgs({
    required this.width,
    required this.height,
    required this.nv21Bytes,
    required this.boundingBox,
    required this.inputSize,
    required this.sensorOrientation,
  });
}

class ImageConverter {
  static CropNormalizeArgs buildArgs(CameraImage image, Face face, int inputSize, int sensorOrientation) {
    final Uint8List nv21;
    if (image.planes.length == 1) {
      nv21 = image.planes[0].bytes;
    } else {
      nv21 = _yuv420ToNv21(image);
    }

    return CropNormalizeArgs(
      width: image.width,
      height: image.height,
      nv21Bytes: nv21,
      boundingBox: face.boundingBox,
      inputSize: inputSize,
      sensorOrientation: sensorOrientation,
    );
  }

  static Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(width * height + (width * height ~/ 2));
    int dstIdx = 0;

    for (int row = 0; row < height; row++) {
      nv21.setRange(dstIdx, dstIdx + width, yPlane.bytes, row * yPlane.bytesPerRow);
      dstIdx += width;
    }

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

  static List<double> cropAndNormalizeIsolate(CropNormalizeArgs args) {
    img.Image fullImage = _nv21ToRgb(args.width, args.height, args.nv21Bytes);

    // Rotate image so it matches the orientation ML Kit used for detection
    fullImage = _rotateToUpright(fullImage, args.sensorOrientation);

    return _cropAndNormalize(fullImage, args.boundingBox, args.inputSize);
  }

  static img.Image _nv21ToRgb(int width, int height, Uint8List nv21) {
    final rgb = Uint8List(width * height * 3);
    final int frameSize = width * height;
    int idx = 0;

    for (int j = 0; j < height; j++) {
      for (int i = 0; i < width; i++) {
        final int yVal = nv21[j * width + i] & 0xFF;
        final int uvOffset = frameSize + (j ~/ 2) * width + (i & ~1);
        final int vVal = nv21[uvOffset] & 0xFF;
        final int uVal = nv21[uvOffset + 1] & 0xFF;

        rgb[idx++] = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toInt();
        rgb[idx++] = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).clamp(0, 255).toInt();
        rgb[idx++] = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();
      }
    }

    return img.Image.fromBytes(width: width, height: height, bytes: rgb.buffer, numChannels: 3);
  }

  /// Rotate image to upright so bounding box coords align with the image pixels
  static img.Image _rotateToUpright(img.Image image, int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return img.copyRotate(image, angle: 90);
      case 180:
        return img.copyRotate(image, angle: 180);
      case 270:
        return img.copyRotate(image, angle: 270);
      default:
        return image; // 0 degrees — no rotation needed
    }
  }

  static List<double> _cropAndNormalize(img.Image fullImage, Rect rect, int inputSize) {
    final double padding = rect.width * 0.2;
    final int x = max(0, (rect.left - padding).toInt());
    final int y = max(0, (rect.top - padding).toInt());
    final int w = min(fullImage.width - x, (rect.width + padding * 2).toInt());
    final int h = min(fullImage.height - y, (rect.height + padding * 2).toInt());

    // Guard against zero-size crop
    if (w <= 0 || h <= 0) {
      return List<double>.filled(inputSize * inputSize * 3, 0.0);
    }

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
