import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/attendance/attendance_history_screen.dart';
import 'package:face_att/pages/attendance/teacher_login_screen.dart';
import 'package:face_att/pages/classes/class_list_screen.dart';
import 'package:face_att/pages/students/student_list_screen.dart';
import 'package:face_att/pages/teachers/teacher_list_screen.dart';
import 'package:face_att/utils/app_colors.dart';
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
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
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
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Classes Card
                  _dashboardCard(
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
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
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
                    icon: const Icon(Icons.history, color: AppColors.primaryLight),
                    label: const Text(
                      "Attendance History",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: AppColors.border, width: 1.5),
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
    required String title,
    required String countText,
    required String buttonLabel,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                foregroundColor: AppColors.primaryLight,
                child: Icon(icon, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    countText,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
              icon: const Icon(Icons.arrow_forward, size: 16, color: AppColors.primaryLight),
              label: Text(
                buttonLabel,
                style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
