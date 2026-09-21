import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/attendance/attendance_history_screen.dart';
import 'package:face_att/pages/attendance/teacher_login_screen.dart';
import 'package:face_att/pages/classes/class_list_screen.dart';
import 'package:face_att/pages/settings/settings_screen.dart';
import 'package:face_att/pages/students/student_list_screen.dart';
import 'package:face_att/pages/teachers/teacher_list_screen.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  final User? user;
  const HomeScreen({super.key, this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ClassRepository _classRepo = ClassRepository();
  final TeacherRepository _teacherRepo = TeacherRepository();
  final StudentRepository _studentRepo = StudentRepository();

  int _classesCount = 0;
  int _teachersCount = 0;
  int _studentsCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardCounts();
  }

  Future<void> _loadDashboardCounts() async {
    setState(() => _isLoading = true);
    final classes = await _classRepo.getAllClasses();
    final teachers = await _teacherRepo.getAllTeachers();
    final students = await _studentRepo.getAllStudents();

    if (mounted) {
      setState(() {
        _classesCount = classes.length;
        _teachersCount = teachers.length;
        _studentsCount = students.length;
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
        title: const Text(
          "Face Attendance",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Dashboard",
            onPressed: _loadDashboardCounts,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Settings",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Classes Card
                  _dashboardCard(
                    context: context,
                    title: "Classes",
                    countText: "$_classesCount ${_classesCount == 1 ? 'class' : 'classes'}",
                    buttonLabel: "Manage Classes",
                    icon: Icons.class_,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ClassListScreen()),
                      );
                      _loadDashboardCounts();
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2. Teachers Card
                  _dashboardCard(
                    context: context,
                    title: "Teachers",
                    countText: "$_teachersCount ${_teachersCount == 1 ? 'teacher' : 'teachers'}",
                    buttonLabel: "Manage Teachers",
                    icon: Icons.people,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TeacherListScreen()),
                      );
                      _loadDashboardCounts();
                    },
                  ),
                  const SizedBox(height: 16),

                  // 3. Students Card
                  _dashboardCard(
                    context: context,
                    title: "Students",
                    countText: "$_studentsCount ${_studentsCount == 1 ? 'student' : 'students'}",
                    buttonLabel: "Manage Students",
                    icon: Icons.school,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StudentListScreen()),
                      );
                      _loadDashboardCounts();
                    },
                  ),
                  const SizedBox(height: 28),

                  // Primary CTA: [ Take Attendance ]
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TeacherLoginScreen()),
                      );
                    },
                    icon: const Icon(Icons.camera_alt, size: 22),
                    label: const Text(
                      "Take Attendance",
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Secondary CTA: [ Attendance History ]
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen()),
                      );
                    },
                    icon: Icon(Icons.history, color: colorScheme.primary),
                    label: const Text(
                      "Attendance History",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _dashboardCard({
    required BuildContext context,
    required String title,
    required String countText,
    required String buttonLabel,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                child: Icon(icon, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    countText,
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onTap,
              icon: Icon(Icons.arrow_forward, size: 16, color: colorScheme.primary),
              label: Text(
                buttonLabel,
                style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
