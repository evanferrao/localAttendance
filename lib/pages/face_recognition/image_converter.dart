import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

class Point2D {
  final double x;
  final double y;
  const Point2D(this.x, this.y);

  @override
  String toString() => 'Point2D($x, $y)';
}

/// Precise 5-point ArcFace facial landmark alignment (norm_crop)
/// Matches Python InsightFace face alignment with mathematical sub-pixel accuracy.
class FaceLandmarkAligner {
  /// Canonical ArcFace 112x112 destination coordinates:
  /// 1. Left eye: (38.2946, 51.6963)
  /// 2. Right eye: (73.5318, 51.5014)
  /// 3. Nose tip: (56.0252, 71.7366)
  /// 4. Left mouth corner: (41.5493, 92.3655)
  /// 5. Right mouth corner: (70.7299, 92.2041)
  static const List<Point2D> arcfaceDst = [
    Point2D(38.2946, 51.6963),
    Point2D(73.5318, 51.5014),
    Point2D(56.0252, 71.7366),
    Point2D(41.5493, 92.3655),
    Point2D(70.7299, 92.2041),
  ];

  /// Estimates 2D similarity transform parameters [a, b, tx, ty] mapping src -> dst
  /// where dst_x = a * src_x - b * src_y + tx
  ///       dst_y = b * src_x + a * src_y + ty
  static List<double>? estimateSimilarityTransform(List<Point2D> src, List<Point2D> dst) {
    if (src.length != dst.length || src.length < 3) return null;

    final n = src.length;
    double srcMeanX = 0, srcMeanY = 0;
    double dstMeanX = 0, dstMeanY = 0;

    for (int i = 0; i < n; i++) {
      srcMeanX += src[i].x;
      srcMeanY += src[i].y;
      dstMeanX += dst[i].x;
      dstMeanY += dst[i].y;
    }
    srcMeanX /= n;
    srcMeanY /= n;
    dstMeanX /= n;
    dstMeanY /= n;

    double denom = 0.0;
    double numA = 0.0;
    double numB = 0.0;

    for (int i = 0; i < n; i++) {
      final sX = src[i].x - srcMeanX;
      final sY = src[i].y - srcMeanY;
      final dX = dst[i].x - dstMeanX;
      final dY = dst[i].y - dstMeanY;

      denom += (sX * sX + sY * sY);
      numA += (sX * dX + sY * dY);
      numB += (sX * dY - sY * dX);
    }

    if (denom == 0) return null;

    final a = numA / denom;
    final b = numB / denom;
    final tx = dstMeanX - (a * srcMeanX - b * srcMeanY);
    final ty = dstMeanY - (b * srcMeanX + a * srcMeanY);

    return [a, b, tx, ty];
  }

  /// Aligns and crops face from img.Image using 5 facial landmarks directly into
  /// a normalized [1, 3, 112, 112] NCHW float list with [-1.0, 1.0] range.
  static List<double> alignAndNormalize(
    img.Image image,
    List<Point2D> landmarks, {
    int inputSize = 112,
  }) {
    assert(landmarks.length == 5);
    final transform = estimateSimilarityTransform(landmarks, arcfaceDst);
    if (transform == null) {
      return ImageConverter.cropAndNormalizeFromImage(image, null, inputSize);
    }

    final a = transform[0];
    final b = transform[1];
    final tx = transform[2];
    final ty = transform[3];

    final det = a * a + b * b;
    if (det == 0) {
      return ImageConverter.cropAndNormalizeFromImage(image, null, inputSize);
    }

    final planeSize = inputSize * inputSize;
    final result = List<double>.filled(3 * planeSize, 0.0);
    final w = image.width;
    final h = image.height;

    int idx = 0;
    for (int yd = 0; yd < inputSize; yd++) {
      for (int xd = 0; xd < inputSize; xd++) {
        // Inverse mapping from dst (xd, yd) to src (xs, ys)
        final xDiff = xd - tx;
        final yDiff = yd - ty;
        final xs = (a * xDiff + b * yDiff) / det;
        final ys = (-b * xDiff + a * yDiff) / det;

        // Sub-pixel bilinear sampling
        final x0 = xs.floor();
        final x1 = x0 + 1;
        final y0 = ys.floor();
        final y1 = y0 + 1;

        double r = 0.0, g = 0.0, bVal = 0.0;

        if (x0 >= 0 && x1 < w && y0 >= 0 && y1 < h) {
          final p00 = image.getPixel(x0, y0);
          final p10 = image.getPixel(x1, y0);
          final p01 = image.getPixel(x0, y1);
          final p11 = image.getPixel(x1, y1);

          final wx = xs - x0;
          final wy = ys - y0;

          r = (1 - wx) * (1 - wy) * p00.r +
              wx * (1 - wy) * p10.r +
              (1 - wx) * wy * p01.r +
              wx * wy * p11.r;

          g = (1 - wx) * (1 - wy) * p00.g +
              wx * (1 - wy) * p10.g +
              (1 - wx) * wy * p01.g +
              wx * wy * p11.g;

          bVal = (1 - wx) * (1 - wy) * p00.b +
              wx * (1 - wy) * p10.b +
              (1 - wx) * wy * p01.b +
              wx * wy * p11.b;
        } else if (xs >= 0 && xs < w && ys >= 0 && ys < h) {
          final p = image.getPixel(xs.clamp(0, w - 1).toInt(), ys.clamp(0, h - 1).toInt());
          r = p.r.toDouble();
          g = p.g.toDouble();
          bVal = p.b.toDouble();
        }

        // ArcFace RGB normalization: [-1.0, 1.0]
        result[idx] = (r / 127.5) - 1.0;
        result[planeSize + idx] = (g / 127.5) - 1.0;
        result[2 * planeSize + idx] = (bVal / 127.5) - 1.0;
        idx++;
      }
    }

    return result;
  }
}

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

class FacePreprocessParams {
  final Uint8List imageBytes;
  final Rect? boundingBox;
  final List<Point2D>? landmarks;
  final int inputSize;

  FacePreprocessParams({
    required this.imageBytes,
    this.boundingBox,
    this.landmarks,
    this.inputSize = 112,
  });
}

class ImageConverter {
  /// Entry point for running heavy image decoding and landmark alignment in a background isolate (compute).
  /// Frees the Flutter UI isolate from 300-800ms of synchronous JPEG decoding and pixel iteration.
  static List<double> preprocessFaceInIsolate(FacePreprocessParams params) {
    final decoded = img.decodeImage(params.imageBytes);
    if (decoded == null) {
      throw Exception("Failed to decode image bytes in isolate");
    }
    return processImageForArcFace(
      decoded,
      landmarks: params.landmarks,
      boundingBox: params.boundingBox,
      inputSize: params.inputSize,
    );
  }
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

  /// Process an image for ArcFace inference:
  /// Uses 5-point landmark alignment if provided; falls back to bounding-box crop or full-image resize.
  static List<double> processImageForArcFace(
    img.Image fullImage, {
    List<Point2D>? landmarks,
    Rect? boundingBox,
    int inputSize = 112,
  }) {
    if (landmarks != null && landmarks.length == 5) {
      return FaceLandmarkAligner.alignAndNormalize(fullImage, landmarks, inputSize: inputSize);
    }
    return cropAndNormalizeFromImage(fullImage, boundingBox, inputSize);
  }

  /// Crop and normalize directly from an existing img.Image (e.g. from file/gallery)
  static List<double> cropAndNormalizeFromImage(img.Image fullImage, Rect? rect, int inputSize) {
    if (rect == null) {
      final resized = img.copyResize(fullImage, width: inputSize, height: inputSize);
      final result = List<double>.filled(inputSize * inputSize * 3, 0.0);
      final planeSize = inputSize * inputSize;
      int idx = 0;
      for (int py = 0; py < inputSize; py++) {
        for (int px = 0; px < inputSize; px++) {
          final pixel = resized.getPixel(px, py);
          result[idx] = (pixel.r / 127.5) - 1.0;
          result[planeSize + idx] = (pixel.g / 127.5) - 1.0;
          result[2 * planeSize + idx] = (pixel.b / 127.5) - 1.0;
          idx++;
        }
      }
      return result;
    }
    return _cropAndNormalize(fullImage, rect, inputSize);
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

    // NCHW format [1, 3, inputSize, inputSize]: R plane, G plane, B plane
    final result = List<double>.filled(inputSize * inputSize * 3, 0.0);
    final planeSize = inputSize * inputSize;
    int idx = 0;
    for (int py = 0; py < inputSize; py++) {
      for (int px = 0; px < inputSize; px++) {
        final pixel = resized.getPixel(px, py);
        result[idx] = (pixel.r / 127.5) - 1.0;
        result[planeSize + idx] = (pixel.g / 127.5) - 1.0;
        result[2 * planeSize + idx] = (pixel.b / 127.5) - 1.0;
        idx++;
      }
    }
    return result;
  }
}
