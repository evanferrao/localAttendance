import 'package:face_att/database/repositories/attendance_record_repository.dart';
import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/models/attendance_record.dart';
import 'package:face_att/models/attendance_session.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:face_att/services/attendance_export_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AttendanceSummaryScreen extends StatefulWidget {
  final int sessionId;
  const AttendanceSummaryScreen({super.key, required this.sessionId});

  @override
  State<AttendanceSummaryScreen> createState() => _AttendanceSummaryScreenState();
}

class _AttendanceSummaryScreenState extends State<AttendanceSummaryScreen> {
  final AttendanceSessionRepository _sessionRepo = AttendanceSessionRepository();
  final AttendanceRecordRepository _recordRepo = AttendanceRecordRepository();
  final AttendanceExportService _exportService = AttendanceExportService();

  AttendanceSession? _session;
  List<AttendanceRecord> _records = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String? _exportingFormat;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoading = true);
    final session = await _sessionRepo.getSessionById(widget.sessionId);
    final records = await _recordRepo.getRecordsForSession(widget.sessionId);

    if (mounted) {
      setState(() {
        _session = session;
        _records = records;
        _isLoading = false;
      });
    }
  }

  Future<void> _exportAndShare({required String format}) async {
    final isCsv = format.toLowerCase() == 'csv';
    setState(() {
      _isExporting = true;
      _exportingFormat = format.toLowerCase();
    });
    try {
      final file = isCsv
          ? await _exportService.exportSessionToCsvFile(widget.sessionId)
          : await _exportService.exportSessionToFile(widget.sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.present,
          content: Text("Saved ${format.toUpperCase()} to: ${file.path}"),
          action: SnackBarAction(
            label: "Share",
            textColor: Colors.white,
            onPressed: () => isCsv
                ? _exportService.shareSessionCsv(widget.sessionId)
                : _exportService.shareSessionJson(widget.sessionId),
          ),
        ),
      );
      if (isCsv) {
        await _exportService.shareSessionCsv(widget.sessionId);
      } else {
        await _exportService.shareSessionJson(widget.sessionId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.absent, content: Text("Export failed: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportingFormat = null;
        });
      }
    }
  }

  Future<void> _viewPreview({required String format}) async {
    final isCsv = format.toLowerCase() == 'csv';
    final contentStr = isCsv
        ? await _exportService.exportSessionAsCsvString(widget.sessionId)
        : await _exportService.exportSessionAsJsonString(widget.sessionId);
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
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
              contentStr,
              style: TextStyle(color: colorScheme.primary, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: contentStr));
              if (mounted) {
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
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return "--";
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: colorScheme.primary)),
      );
    }

    final presentList = _records.where((r) => r.isPresent).toList();
    final absentList = _records.where((r) => r.isAbsent).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Attendance Completed"),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Icon & Heading
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(Icons.check_circle, size: 50, color: colorScheme.primary),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                "Attendance Completed",
                style: TextStyle(color: colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  _statRow("Class", _session?.className ?? "Class #${_session?.classId}", colorScheme),
                  Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3), height: 20),
                  _statRow("Teacher", _session?.teacherName ?? "Teacher #${_session?.teacherId}", colorScheme),
                  Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3), height: 20),
                  _statRow("Date", _session?.attendanceDate ?? "--", colorScheme),
                  Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3), height: 20),
                  _statRow("Started", _formatTime(_session?.startedAt), colorScheme),
                  Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3), height: 20),
                  _statRow("Ended", _formatTime(_session?.endedAt), colorScheme),
                  Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3), height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _countBadge("Present", presentList.length, AppColors.present, colorScheme),
                      _countBadge("Absent", absentList.length, AppColors.absent, colorScheme),
                      _countBadge("Total", _records.length, colorScheme.onSurfaceVariant, colorScheme),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Toggle Details List
            OutlinedButton.icon(
              onPressed: () => setState(() => _showDetails = !_showDetails),
              icon: Icon(_showDetails ? Icons.expand_less : Icons.expand_more, color: colorScheme.primary),
              label: Text(_showDetails ? "Hide Student List" : "View Attendance Details (${_records.length})"),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.primary,
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            if (_showDetails) ...[
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: _records.map((r) {
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        r.isPresent ? Icons.check_circle : Icons.cancel,
                        color: r.isPresent ? AppColors.present : AppColors.absent,
                        size: 20,
                      ),
                      title: Text(r.studentName, style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        "${r.studentRegisterNumber}${r.attendanceTime != null ? ' • ${_formatTime(r.attendanceTime)}' : ''}",
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      trailing: Text(
                        r.status.toUpperCase(),
                        style: TextStyle(
                          color: r.isPresent ? AppColors.present : AppColors.absent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isExporting ? null : () => _exportAndShare(format: 'csv'),
                    icon: _isExporting && _exportingFormat == 'csv'
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                          )
                        : const Icon(Icons.table_chart),
                    label: const Text("Export CSV", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting ? null : () => _exportAndShare(format: 'json'),
                    icon: _isExporting && _exportingFormat == 'json'
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                          )
                        : const Icon(Icons.code),
                    label: const Text("Export JSON", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.primary, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => _viewPreview(format: 'csv'),
                  icon: Icon(Icons.table_view, color: colorScheme.primary, size: 18),
                  label: Text("Preview CSV", style: TextStyle(color: colorScheme.primary)),
                ),
                const SizedBox(width: 8),
                Text("•", style: TextStyle(color: colorScheme.outlineVariant)),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _viewPreview(format: 'json'),
                  icon: Icon(Icons.code, color: colorScheme.primary, size: 18),
                  label: Text("Preview JSON", style: TextStyle(color: colorScheme.primary)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (_) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.surfaceContainerHigh,
                foregroundColor: colorScheme.onSurface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Done"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
        Text(value, style: TextStyle(color: colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _countBadge(String label, int count, Color color, ColorScheme colorScheme) {
    return Column(
      children: [
        Text(
          "$count",
          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }
}
