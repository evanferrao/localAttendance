import 'dart:ui';
import 'package:face_att/pages/attendance/widgets/corner_bracket_painter.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

/// Camera HUD Overlay containing the viewfinder reticle, floating shutter/countdown badge, and unified status capsule
class ScannerHudOverlay extends StatelessWidget {
  final bool isLandscape;
  final bool isProcessing;
  final bool isCapturing;
  final bool isEasyMode;
  final int countdown;
  final String statusMessage;
  final Color feedbackColor;
  final VoidCallback? onTriggerScan;
  final bool compact;

  const ScannerHudOverlay({
    super.key,
    required this.isLandscape,
    required this.isProcessing,
    required this.isCapturing,
    required this.isEasyMode,
    required this.countdown,
    required this.statusMessage,
    required this.feedbackColor,
    this.onTriggerScan,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        // Viewfinder Reticle
        _buildViewfinder(context),

        // Floating Shutter Badge (Top Right)
        _buildFloatingShutterBadge(context),

        // Unified Status Capsule (Bottom)
        _buildUnifiedStatusCapsule(context),
      ],
    );
  }

  Widget _buildViewfinder(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = isLandscape
            ? (constraints.maxWidth * 0.90).clamp(240.0, 1200.0)
            : (constraints.maxWidth * 0.68).clamp(200.0, 280.0);
        final boxHeight = isLandscape
            ? (constraints.maxHeight * 0.82).clamp(180.0, 800.0)
            : (constraints.maxHeight * 0.68).clamp(220.0, 320.0);

        final frameColor = isProcessing
            ? Theme.of(context).colorScheme.primary
            : (isEasyMode
                ? AppColors.present.withValues(alpha: 0.8)
                : feedbackColor.withValues(alpha: 0.8));

        return Center(
          child: CustomPaint(
            size: Size(boxWidth, boxHeight),
            painter: CornerBracketPainter(
              color: frameColor,
              cornerLength: 28,
              strokeWidth: 3.0,
              borderRadius: 16,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingShutterBadge(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (isCapturing || isProcessing) ? null : onTriggerScan,
          borderRadius: BorderRadius.circular(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCapturing || isProcessing) ...[
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "Scanning",
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ] else ...[
                      const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        "${countdown}s",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedStatusCapsule(BuildContext context) {
    return Positioned(
      bottom: compact ? 10 : 14,
      left: compact ? 12 : 20,
      right: compact ? 12 : 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 7 : 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: feedbackColor.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isProcessing || isCapturing) ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (feedbackColor == AppColors.present) ...[
                  const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.present),
                  const SizedBox(width: 8),
                ] else if (feedbackColor == AppColors.warning) ...[
                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                ] else if (feedbackColor == AppColors.absent) ...[
                  const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.absent),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    statusMessage,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: feedbackColor,
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
