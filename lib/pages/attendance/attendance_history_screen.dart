import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/models/attendance_session.dart';
import 'package:face_att/pages/attendance/attendance_summary_screen.dart';
import 'package:flutter/material.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  final AttendanceSessionRepository _sessionRepo = AttendanceSessionRepository();
  List<AttendanceSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    final sessions = await _sessionRepo.getAllSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Attendance History"),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text("No attendance sessions recorded yet", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final s = _sessions[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        leading: CircleAvatar(
                          backgroundColor: s.isActive
                              ? Colors.orangeAccent.withValues(alpha: 0.2)
                              : colorScheme.primaryContainer,
                          foregroundColor: s.isActive ? Colors.orangeAccent : colorScheme.onPrimaryContainer,
                          child: Icon(s.isActive ? Icons.pending_actions : Icons.fact_check),
                        ),
                        title: Text(
                          s.className ?? "Class #${s.classId}",
                          style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "${s.attendanceDate} • Teacher: ${s.teacherName ?? 'Teacher'}\n${s.presentCount} / ${s.totalCount} Present",
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                          ),
                        ),
                        trailing: Icon(Icons.arrow_forward_ios, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AttendanceSummaryScreen(sessionId: s.id!)),
                          );
                          _loadSessions();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
