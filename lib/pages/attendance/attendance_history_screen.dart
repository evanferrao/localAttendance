import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/models/attendance_session.dart';
import 'package:face_att/pages/attendance/attendance_summary_screen.dart';
import 'package:face_att/utils/app_colors.dart';
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
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text("Attendance History"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : _sessions.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, size: 64, color: Colors.white30),
                      SizedBox(height: 16),
                      Text("No attendance sessions recorded yet", style: TextStyle(color: Colors.white70, fontSize: 16)),
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
                        color: AppColors.navySurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        leading: CircleAvatar(
                          backgroundColor: s.isActive
                              ? Colors.orangeAccent.withValues(alpha: 0.2)
                              : AppColors.primary.withValues(alpha: 0.2),
                          foregroundColor: s.isActive ? Colors.orangeAccent : AppColors.primaryLight,
                          child: Icon(s.isActive ? Icons.pending_actions : Icons.fact_check),
                        ),
                        title: Text(
                          s.className ?? "Class #${s.classId}",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "${s.attendanceDate} • Teacher: ${s.teacherName ?? 'Teacher'}\n${s.presentCount} / ${s.totalCount} Present",
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
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
