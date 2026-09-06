import 'package:face_att/database/repositories/attendance_record_repository.dart';
import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/models/attendance_record.dart';
import 'package:face_att/models/attendance_session.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:face_att/services/attendance_export_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

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

  Future<void> _exportAndShare() async {
    setState(() => _isExporting = true);
    try {
      final file = await _exportService.exportSessionToFile(widget.sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.greenAccent.shade700,
          content: Text("Saved JSON to: ${file.path}"),
          action: SnackBarAction(
            label: "Share",
            textColor: Colors.black,
            onPressed: () => _exportService.shareSessionJson(widget.sessionId),
          ),
        ),
      );
      await _exportService.shareSessionJson(widget.sessionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Export failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _viewRawJson() async {
    final jsonStr = await _exportService.exportSessionAsJsonString(widget.sessionId);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text("Exported JSON", style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              jsonStr,
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: Colors.white70)),
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
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.navyBackground,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
      );
    }

    final presentList = _records.where((r) => r.isPresent).toList();
    final absentList = _records.where((r) => r.isAbsent).toList();

    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
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
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: const Icon(Icons.check_circle, size: 50, color: AppColors.primaryLight),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                "Attendance Completed",
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _statRow("Class", _session?.className ?? "Class #${_session?.classId}"),
                  const Divider(color: Colors.white12, height: 20),
                  _statRow("Teacher", _session?.teacherName ?? "Teacher #${_session?.teacherId}"),
                  const Divider(color: Colors.white12, height: 20),
                  _statRow("Date", _session?.attendanceDate ?? "--"),
                  const Divider(color: Colors.white12, height: 20),
                  _statRow("Started", _formatTime(_session?.startedAt)),
                  const Divider(color: Colors.white12, height: 20),
                  _statRow("Ended", _formatTime(_session?.endedAt)),
                  const Divider(color: Colors.white12, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _countBadge("Present", presentList.length, Colors.greenAccent),
                      _countBadge("Absent", absentList.length, Colors.redAccent),
                      _countBadge("Total", _records.length, Colors.white70),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Toggle Details List
            OutlinedButton.icon(
              onPressed: () => setState(() => _showDetails = !_showDetails),
              icon: Icon(_showDetails ? Icons.expand_less : Icons.expand_more, color: Colors.greenAccent),
              label: Text(_showDetails ? "Hide Student List" : "View Attendance Details (${_records.length})"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            if (_showDetails) ...[
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: _records.map((r) {
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        r.isPresent ? Icons.check_circle : Icons.cancel,
                        color: r.isPresent ? Colors.greenAccent : Colors.redAccent,
                        size: 20,
                      ),
                      title: Text(r.studentName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        "${r.studentRegisterNumber}${r.attendanceTime != null ? ' • ${_formatTime(r.attendanceTime)}' : ''}",
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: Text(
                        r.status.toUpperCase(),
                        style: TextStyle(
                          color: r.isPresent ? Colors.greenAccent : Colors.redAccent,
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
            ElevatedButton.icon(
              onPressed: _isExporting ? null : _exportAndShare,
              icon: const Icon(Icons.share),
              label: _isExporting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text("Export & Share JSON", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),

            TextButton.icon(
              onPressed: _viewRawJson,
              icon: const Icon(Icons.code, color: Colors.white70, size: 18),
              label: const Text("View JSON Preview", style: TextStyle(color: Colors.white70)),
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
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white,
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

  Widget _statRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _countBadge(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          "$count",
          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
