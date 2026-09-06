import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/attendance_session.dart';
import 'package:face_att/models/class_model.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/models/teacher.dart';
import 'package:face_att/pages/attendance/attendance_summary_screen.dart';
import 'package:face_att/pages/students/create_student_screen.dart';
import 'package:face_att/pages/students/student_detail_screen.dart';
import 'package:face_att/pages/teachers/create_teacher_screen.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

class ClassDetailScreen extends StatefulWidget {
  final ClassModel classModel;
  const ClassDetailScreen({super.key, required this.classModel});

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  final ClassRepository _classRepo = ClassRepository();
  final TeacherRepository _teacherRepo = TeacherRepository();
  final StudentRepository _studentRepo = StudentRepository();
  final AttendanceSessionRepository _sessionRepo = AttendanceSessionRepository();

  late ClassModel _class;
  List<Teacher> _teachers = [];
  List<Student> _students = [];
  List<AttendanceSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _class = widget.classModel;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final refreshedClass = await _classRepo.getClassById(_class.id!) ?? _class;
    final teachers = await _teacherRepo.getTeachersForClass(_class.id!);
    final students = await _studentRepo.getStudentsForClass(_class.id!);
    final sessions = await _sessionRepo.getSessionsForClass(_class.id!);

    if (mounted) {
      setState(() {
        _class = refreshedClass;
        _teachers = teachers;
        _students = students;
        _sessions = sessions;
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddTeacherDialog() async {
    final allTeachers = await _teacherRepo.getAllTeachers();
    final currentTeacherIds = _teachers.map((t) => t.id).toSet();
    final unassigned = allTeachers.where((t) => !currentTeacherIds.contains(t.id)).toList();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Assign Teacher", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final created = await Navigator.push<Teacher>(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateTeacherScreen()),
                      );
                      if (created != null && created.id != null) {
                        await _classRepo.assignTeacherToClass(_class.id!, created.id!);
                        _loadData();
                      }
                    },
                    icon: const Icon(Icons.add, size: 18, color: AppColors.primaryLight),
                    label: const Text("Create New", style: TextStyle(color: AppColors.primaryLight)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (unassigned.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text("All existing teachers are already assigned to this class.", style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: unassigned.length,
                    itemBuilder: (_, i) {
                      final t = unassigned[i];
                      return ListTile(
                        title: Text(t.displayName, style: const TextStyle(color: Colors.white)),
                        subtitle: Text("@${t.username}", style: const TextStyle(color: AppColors.textSecondary)),
                        trailing: const Icon(Icons.add_circle_outline, color: AppColors.primaryLight),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _classRepo.assignTeacherToClass(_class.id!, t.id!);
                          _loadData();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddStudentDialog() async {
    final allStudents = await _studentRepo.getAllStudents();
    final currentStudentIds = _students.map((s) => s.id).toSet();
    final unenrolled = allStudents.where((s) => !currentStudentIds.contains(s.id)).toList();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Enroll Student", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final created = await Navigator.push<Student>(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateStudentScreen()),
                      );
                      if (created != null && created.id != null) {
                        await _classRepo.assignStudentToClass(_class.id!, created.id!);
                        _loadData();
                      }
                    },
                    icon: const Icon(Icons.add, size: 18, color: AppColors.primaryLight),
                    label: const Text("Create New", style: TextStyle(color: AppColors.primaryLight)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (unenrolled.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text("All registered students are already in this class.", style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: unenrolled.length,
                    itemBuilder: (_, i) {
                      final s = unenrolled[i];
                      return ListTile(
                        title: Text(s.name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(s.registerNumber, style: const TextStyle(color: AppColors.textSecondary)),
                        trailing: const Icon(Icons.add_circle_outline, color: AppColors.primaryLight),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _classRepo.assignStudentToClass(_class.id!, s.id!);
                          _loadData();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _removeTeacher(Teacher teacher) async {
    try {
      await _classRepo.removeTeacherFromClass(_class.id!, teacher.id!);
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.absent, content: Text(e.toString())),
      );
    }
  }

  Future<void> _removeStudent(Student student) async {
    await _classRepo.removeStudentFromClass(_class.id!, student.id!);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(_class.name),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header summary
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.navySurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _class.name,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.people, size: 16, color: AppColors.primaryLight),
                            const SizedBox(width: 6),
                            Text("${_teachers.length} Teachers", style: const TextStyle(color: Colors.white70)),
                            const SizedBox(width: 16),
                            const Icon(Icons.school, size: 16, color: AppColors.primaryLight),
                            const SizedBox(width: 6),
                            Text("${_students.length} Students", style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Teachers Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Assigned Teachers (${_teachers.length})",
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: _showAddTeacherDialog,
                        icon: const Icon(Icons.add, color: AppColors.primaryLight),
                        tooltip: "Assign Teacher",
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._teachers.map((t) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.navySurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: ListTile(
                          title: Text(t.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text("@${t.username}", style: const TextStyle(color: AppColors.textSecondary)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: AppColors.absent, size: 20),
                            onPressed: () => _removeTeacher(t),
                            tooltip: "Remove from class",
                          ),
                        ),
                      )),
                  const SizedBox(height: 24),

                  // Students Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Enrolled Students (${_students.length})",
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: _showAddStudentDialog,
                        icon: const Icon(Icons.add, color: AppColors.primaryLight),
                        tooltip: "Enroll Student",
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_students.isEmpty)
                    const Text("No students enrolled in this class yet.", style: TextStyle(color: AppColors.textSecondary))
                  else
                    ..._students.map((s) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppColors.navySurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: ListTile(
                            title: Text(s.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              "${s.registerNumber} • ${s.hasFaceEnrolled ? 'Face Enrolled' : 'No Face'}",
                              style: TextStyle(
                                color: s.hasFaceEnrolled ? AppColors.present : AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: AppColors.absent, size: 20),
                              onPressed: () => _removeStudent(s),
                              tooltip: "Remove from class",
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => StudentDetailScreen(student: s)),
                            ),
                          ),
                        )),
                  const SizedBox(height: 24),

                  // Historical Sessions for this Class
                  if (_sessions.isNotEmpty) ...[
                    const Text(
                      "Attendance History",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ..._sessions.map((sess) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppColors.navySurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: ListTile(
                            title: Text(sess.attendanceDate, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              "${sess.teacherName ?? 'Teacher'} • ${sess.presentCount}/${sess.totalCount} Present",
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            trailing: Chip(
                              label: Text(
                                sess.status.toUpperCase(),
                                style: TextStyle(
                                  color: sess.isActive ? AppColors.present : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: sess.isActive ? AppColors.present.withValues(alpha: 0.15) : AppColors.navySurfaceElevated,
                              side: BorderSide(color: AppColors.borderSubtle),
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => AttendanceSummaryScreen(sessionId: sess.id!)),
                            ),
                          ),
                        )),
                  ],
                ],
              ),
            ),
    );
  }
}
