import 'package:face_att/services/student_import_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

class StudentImportDialogs {
  StudentImportDialogs._();

  /// Shows the final results dialog after ZIP import is completed
  static Future<void> showSummaryDialog(
    BuildContext context, {
    required StudentImportSummary summary,
  }) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                summary.failedCount == 0 ? Icons.check_circle : Icons.info_outline,
                color: summary.failedCount == 0 ? AppColors.present : AppColors.warning,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text("Import Results", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatColumn(
                        label: "Total",
                        count: summary.totalCount,
                        color: colorScheme.primary,
                      ),
                      _StatColumn(
                        label: "Enrolled",
                        count: summary.successCount,
                        color: AppColors.present,
                      ),
                      _StatColumn(
                        label: "Failed",
                        count: summary.failedCount,
                        color: summary.failedCount > 0 ? AppColors.absent : colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (summary.hasFailures) ...[
                  Text(
                    "Issues Encountered (${summary.failedCount}):",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: summary.results.where((r) => !r.success).length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (ctx, index) {
                        final failedItem = summary.results.where((r) => !r.success).toList()[index];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.cancel_outlined, color: AppColors.absent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    failedItem.name.isNotEmpty
                                        ? '${failedItem.registerNumber} (${failedItem.name})'
                                        : failedItem.registerNumber,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    failedItem.errorMessage ?? 'Unknown error',
                                    style: TextStyle(
                                      color: colorScheme.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ] else ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        "All ${summary.totalCount} students and face embeddings enrolled successfully!",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.present,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Done"),
            ),
          ],
        );
      },
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatColumn({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          "$count",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
