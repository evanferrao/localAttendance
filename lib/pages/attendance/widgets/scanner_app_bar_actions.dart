import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

/// AppBar actions for the Attendance Scanner Screen:
/// Contains the Mode Toggle Chip (Single vs Classroom) and options menu.
class ScannerAppBarActions extends StatelessWidget {
  final bool isClassroomMode;
  final VoidCallback onToggleMode;
  final VoidCallback onScanFromGallery;
  final VoidCallback onTestDebugPhoto;
  final VoidCallback? onFlipCamera;

  const ScannerAppBarActions({
    super.key,
    required this.isClassroomMode,
    required this.onToggleMode,
    required this.onScanFromGallery,
    required this.onTestDebugPhoto,
    this.onFlipCamera,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mode Toggle Chip (Single vs Classroom Mode)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggleMode,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isClassroomMode
                      ? AppColors.present.withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isClassroomMode
                        ? AppColors.present.withValues(alpha: 0.6)
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isClassroomMode ? Icons.groups_rounded : Icons.person_rounded,
                      size: 16,
                      color: isClassroomMode ? AppColors.present : colorScheme.onSurface,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isClassroomMode ? "Classroom" : "Single",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isClassroomMode ? AppColors.present : colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Flip Camera Button
        if (onFlipCamera != null)
          IconButton(
            icon: Icon(Icons.flip_camera_ios_rounded, color: colorScheme.onSurface, size: 20),
            tooltip: "Flip Camera",
            onPressed: onFlipCamera,
          ),

        // Secondary options popup menu
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurface),
          tooltip: "More Options",
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: colorScheme.surfaceContainerHigh,
          onSelected: (val) {
            if (val == 'gallery') onScanFromGallery();
            if (val == 'debug') onTestDebugPhoto();
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'gallery',
              child: Row(
                children: [
                  Icon(Icons.photo_library_outlined, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    "Scan Photo from Gallery",
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'debug',
              child: Row(
                children: [
                  Icon(Icons.bug_report_outlined, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    "Test Debug Photo",
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
