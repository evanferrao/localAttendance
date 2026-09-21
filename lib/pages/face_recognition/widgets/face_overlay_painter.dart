import 'package:flutter/material.dart';

/// Custom painter that renders a darkened camera viewfinder overlay with a rounded rectangular cutout for face framing.
class FaceOverlayPainter extends CustomPainter {
  final Color borderColor;

  const FaceOverlayPainter({this.borderColor = Colors.greenAccent});

  @override
  void paint(Canvas canvas, Size size) {
    final boxRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: size.width * 0.72,
      height: size.height * 0.42,
    );
    final rrect = RRect.fromRectAndRadius(boxRect, const Radius.circular(20));

    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(rrect)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black54,
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );
  }

  @override
  bool shouldRepaint(FaceOverlayPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor;
}
