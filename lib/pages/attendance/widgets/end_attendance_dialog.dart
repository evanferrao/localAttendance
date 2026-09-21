import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

/// Confirmation dialog presented when ending an active attendance session.
class EndAttendanceDialog extends StatelessWidget {
  final String className;
  final int presentCount;
  final int totalCount;

  const EndAttendanceDialog({
    super.key,
    required this.className,
    required this.presentCount,
    required this.totalCount,
  });

  /// Displays the confirmation dialog and returns true if the user confirmed ending the session.
  static Future<bool?> show(
    BuildContext context, {
    required String className,
    required int presentCount,
    required int totalCount,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => EndAttendanceDialog(
        className: className,
        presentCount: presentCount,
        totalCount: totalCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final absentCount = totalCount - presentCount;

    return AlertDialog(
      backgroundColor: colorScheme.surfaceContainer,
      title: Text(
        "End Attendance Session?",
        style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Class: $className",
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      "$presentCount",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.present,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text("Present", style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
                Container(height: 30, width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                Column(
                  children: [
                    Text(
                      "$absentCount",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.absent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text("Absent", style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
                Container(height: 30, width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                Column(
                  children: [
                    Text(
                      "$totalCount",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text("Total", style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Are you sure you want to complete this session? This will finalize the attendance records.",
            style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text("Cancel", style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.absent,
            foregroundColor: Colors.white,
          ),
          child: const Text("End Session"),
        ),
      ],
    );
  }
}
