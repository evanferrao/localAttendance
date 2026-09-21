import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modal dialog for previewing exported CSV or JSON data with monospace formatting and copy-to-clipboard.
class ExportPreviewDialog extends StatelessWidget {
  final String format;
  final String content;

  const ExportPreviewDialog({
    super.key,
    required this.format,
    required this.content,
  });

  /// Displays the export preview dialog.
  static Future<void> show(
    BuildContext context, {
    required String format,
    required String content,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ExportPreviewDialog(format: format, content: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCsv = format.toLowerCase() == 'csv';

    return AlertDialog(
      backgroundColor: colorScheme.surfaceContainer,
      title: Row(
        children: [
          Icon(isCsv ? Icons.table_chart : Icons.code, color: colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Text(
            "Exported ${format.toUpperCase()}",
            style: TextStyle(color: colorScheme.onSurface, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            content,
            style: TextStyle(color: colorScheme.primary, fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: content));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.present,
                  content: Text("${format.toUpperCase()} copied to clipboard!"),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text("Copy"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Close", style: TextStyle(color: colorScheme.primary)),
        ),
      ],
    );
  }
}
