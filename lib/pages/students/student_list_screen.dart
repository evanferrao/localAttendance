import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/pages/students/create_student_screen.dart';
import 'package:face_att/pages/students/student_detail_screen.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final StudentRepository _studentRepo = StudentRepository();
  List<Student> _students = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    final students = await _studentRepo.getAllStudents();
    if (mounted) {
      setState(() {
        _students = students;
        _isLoading = false;
      });
    }
  }

  void _addStudent() async {
    final created = await Navigator.push<Student>(
      context,
      MaterialPageRoute(builder: (_) => const CreateStudentScreen()),
    );
    if (created != null) {
      _loadStudents();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text("Manage Students"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : _students.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.school_outlined, size: 64, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      const Text("No students found", style: TextStyle(color: Colors.white70, fontSize: 18)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _addStudent,
                        icon: const Icon(Icons.add),
                        label: const Text("Add Student"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _students.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final student = _students[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.navySurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: student.hasFaceEnrolled
                              ? AppColors.present.withValues(alpha: 0.2)
                              : AppColors.warning.withValues(alpha: 0.2),
                          foregroundColor: student.hasFaceEnrolled ? AppColors.present : AppColors.warning,
                          child: Icon(
                            student.hasFaceEnrolled ? Icons.face : Icons.face_outlined,
                          ),
                        ),
                        title: Text(
                          student.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Text(
                          student.registerNumber,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        trailing: Icon(
                          student.hasFaceEnrolled ? Icons.verified : Icons.warning_amber_rounded,
                          color: student.hasFaceEnrolled ? AppColors.present : AppColors.warning,
                          size: 20,
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => StudentDetailScreen(student: student)),
                          );
                          _loadStudents();
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStudent,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("Add Student", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
