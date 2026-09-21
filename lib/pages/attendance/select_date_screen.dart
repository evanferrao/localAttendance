import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/models/attendance_session.dart';
import 'package:face_att/models/class_model.dart';
import 'package:face_att/models/teacher.dart';
import 'package:face_att/pages/attendance/attendance_scanner_screen.dart';
import 'package:face_att/services/attendance_service.dart';
import 'package:flutter/material.dart';

class SelectDateScreen extends StatefulWidget {
  final Teacher teacher;
  final ClassModel classModel;

  const SelectDateScreen({
    super.key,
    required this.teacher,
    required this.classModel,
  });

  @override
  State<SelectDateScreen> createState() => _SelectDateScreenState();
}

class _SelectDateScreenState extends State<SelectDateScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final AttendanceSessionRepository _sessionRepo = AttendanceSessionRepository();

  DateTime _selectedDate = DateTime.now();
  AttendanceSession? _existingActiveSession;
  bool _isLoading = true;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  String get _formattedDateString {
    final y = _selectedDate.year.toString().padLeft(4, '0');
    final m = _selectedDate.month.toString().padLeft(2, '0');
    final d = _selectedDate.day.toString().padLeft(2, '0');
    return "$y-$m-$d";
  }

  String get _displayDateString {
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return "${months[_selectedDate.month - 1]} ${_selectedDate.day}, ${_selectedDate.year}";
  }

  Future<void> _checkExistingSession() async {
    setState(() => _isLoading = true);
    final active = await _sessionRepo.getActiveSessionForClassAndDate(
      widget.classModel.id!,
      _formattedDateString,
    );
    if (mounted) {
      setState(() {
        _existingActiveSession = active;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
      _checkExistingSession();
    }
  }

  Future<void> _startAttendance() async {
    setState(() => _isStarting = true);
    try {
      final session = await _attendanceService.startOrResumeSession(
        classId: widget.classModel.id!,
        teacherId: widget.teacher.id!,
        attendanceDate: _formattedDateString,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceScannerScreen(
            session: session,
            teacher: widget.teacher,
            classModel: widget.classModel,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text("Failed to start session: $e")),
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Attendance Date"),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Class", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          widget.classModel.name,
                          style: TextStyle(color: colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),

                        Text("Teacher", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          widget.teacher.displayName,
                          style: TextStyle(color: colorScheme.primary, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 20),

                        Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Selected Date", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(
                                  _displayDateString,
                                  style: TextStyle(color: colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              onPressed: _pickDate,
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: const Text("Change"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.surfaceContainerHigh,
                                foregroundColor: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_existingActiveSession != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "An active session (#${_existingActiveSession!.id}) already exists for this date. Starting attendance will resume the session.",
                              style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),

                  ElevatedButton(
                    onPressed: _isStarting ? null : _startAttendance,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isStarting
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                          )
                        : Text(
                            _existingActiveSession != null ? "Resume Attendance" : "Start Attendance",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
