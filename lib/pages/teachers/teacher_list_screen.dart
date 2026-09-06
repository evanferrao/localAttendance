import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/teacher.dart';
import 'package:face_att/pages/teachers/create_teacher_screen.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

class TeacherListScreen extends StatefulWidget {
  const TeacherListScreen({super.key});

  @override
  State<TeacherListScreen> createState() => _TeacherListScreenState();
}

class _TeacherListScreenState extends State<TeacherListScreen> {
  final TeacherRepository _teacherRepo = TeacherRepository();
  List<Teacher> _teachers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    setState(() => _isLoading = true);
    final teachers = await _teacherRepo.getAllTeachers();
    if (mounted) {
      setState(() {
        _teachers = teachers;
        _isLoading = false;
      });
    }
  }

  void _addTeacher() async {
    final created = await Navigator.push<Teacher>(
      context,
      MaterialPageRoute(builder: (_) => const CreateTeacherScreen()),
    );
    if (created != null) {
      _loadTeachers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text("Manage Teachers"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : _teachers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_outline, size: 64, color: Colors.white30),
                      const SizedBox(height: 16),
                      const Text("No teachers found", style: TextStyle(color: Colors.white70, fontSize: 18)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _addTeacher,
                        icon: const Icon(Icons.add),
                        label: const Text("Add Teacher"),
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
                  itemCount: _teachers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final teacher = _teachers[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.navySurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                          foregroundColor: AppColors.primaryLight,
                          child: Text(
                            teacher.displayName.isNotEmpty
                                ? teacher.displayName[0].toUpperCase()
                                : 'T',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          teacher.displayName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Text(
                          "@${teacher.username}",
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTeacher,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("Add Teacher", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
