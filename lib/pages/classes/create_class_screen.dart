import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/models/teacher.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:face_att/pages/students/create_student_screen.dart';
import 'package:face_att/pages/teachers/create_teacher_screen.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

class CreateClassScreen extends StatefulWidget {
  final bool isFirstRun;
  const CreateClassScreen({super.key, this.isFirstRun = false});

  @override
  State<CreateClassScreen> createState() => _CreateClassScreenState();
}

class _CreateClassScreenState extends State<CreateClassScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  final ClassRepository _classRepo = ClassRepository();
  final TeacherRepository _teacherRepo = TeacherRepository();
  final StudentRepository _studentRepo = StudentRepository();

  List<Teacher> _allTeachers = [];
  List<Student> _allStudents = [];

  final Set<int> _selectedTeacherIds = {};
  final Set<int> _selectedStudentIds = {};

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final teachers = await _teacherRepo.getAllTeachers();
    final students = await _studentRepo.getAllStudents();

    if (mounted) {
      setState(() {
        _allTeachers = teachers;
        _allStudents = students;
        if (teachers.isNotEmpty && _selectedTeacherIds.isEmpty && teachers.first.id != null) {
          _selectedTeacherIds.add(teachers.first.id!);
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _createNewTeacher() async {
    final created = await Navigator.push<Teacher>(
      context,
      MaterialPageRoute(builder: (_) => const CreateTeacherScreen()),
    );
    if (created != null && created.id != null) {
      await _loadData();
      setState(() => _selectedTeacherIds.add(created.id!));
    }
  }

  Future<void> _createNewStudent() async {
    final created = await Navigator.push<Student>(
      context,
      MaterialPageRoute(builder: (_) => const CreateStudentScreen()),
    );
    if (created != null && created.id != null) {
      await _loadData();
      setState(() => _selectedStudentIds.add(created.id!));
    }
  }

  Future<void> _saveClass() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedTeacherIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.warning,
          content: Text("A class must have at least one assigned teacher"),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final newClass = await _classRepo.createClass(
        name: _nameController.text.trim(),
        teacherIds: _selectedTeacherIds.toList(),
        studentIds: _selectedStudentIds.toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.present,
          content: Text("Class '${newClass.name}' created successfully!"),
        ),
      );

      if (widget.isFirstRun) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        Navigator.pop(context, newClass);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.absent, content: Text("Failed to create class: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.isFirstRun ? "Create Your First Class" : "Create Class"),
        automaticallyImplyLeading: !widget.isFirstRun,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.isFirstRun) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.waving_hand, color: colorScheme.primary, size: 36),
                            const SizedBox(height: 10),
                            Text(
                              "Welcome to Face Attendance",
                              style: TextStyle(color: colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "No classes have been created yet.\nCreate your first class to get started.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Class Name
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
                          Text(
                            "Class Information",
                            style: TextStyle(color: colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            style: TextStyle(color: colorScheme.onSurface),
                            decoration: InputDecoration(
                              labelText: "Class Name",
                              labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                              hintText: "e.g. B.Tech CSE - Section A",
                              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                              prefixIcon: Icon(Icons.class_outlined, color: colorScheme.primary),
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: colorScheme.primary, width: 2),
                              ),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? "Class name is required" : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Teachers Section
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  "Teachers *",
                                  style: TextStyle(color: colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _createNewTeacher,
                                icon: Icon(Icons.add, size: 16, color: colorScheme.primary),
                                label: Text("New Teacher", style: TextStyle(color: colorScheme.primary)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_allTeachers.isEmpty)
                            const Text(
                              "No teachers exist yet. Click above to create one.",
                              style: TextStyle(color: AppColors.warning),
                            )
                          else
                            Column(
                              children: _allTeachers.map((t) {
                                final isSelected = _selectedTeacherIds.contains(t.id);
                                return CheckboxListTile(
                                  value: isSelected,
                                  activeColor: colorScheme.primary,
                                  checkColor: colorScheme.onPrimary,
                                  title: Text(t.displayName, style: TextStyle(color: colorScheme.onSurface)),
                                  subtitle: Text("@${t.username}", style: TextStyle(color: colorScheme.onSurfaceVariant)),
                                  onChanged: (bool? val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedTeacherIds.add(t.id!);
                                      } else {
                                        _selectedTeacherIds.remove(t.id);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Students Section
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  "Students (${_selectedStudentIds.length} selected)",
                                  style: TextStyle(color: colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _createNewStudent,
                                icon: Icon(Icons.add, size: 16, color: colorScheme.primary),
                                label: Text("New Student", style: TextStyle(color: colorScheme.primary)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_allStudents.isEmpty)
                            Text(
                              "No students exist yet. Click above to add students now or add them later.",
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            )
                          else
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 250),
                              child: ListView(
                                shrinkWrap: true,
                                children: _allStudents.map((s) {
                                  final isSelected = _selectedStudentIds.contains(s.id);
                                  return CheckboxListTile(
                                    value: isSelected,
                                    activeColor: colorScheme.primary,
                                    checkColor: colorScheme.onPrimary,
                                    title: Text(s.name, style: TextStyle(color: colorScheme.onSurface)),
                                    subtitle: Text(
                                      "${s.registerNumber} • ${s.hasFaceEnrolled ? 'Face Enrolled' : 'No Face'}",
                                      style: TextStyle(
                                        color: s.hasFaceEnrolled ? AppColors.present : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                        fontSize: 12,
                                      ),
                                    ),
                                    onChanged: (bool? val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedStudentIds.add(s.id!);
                                        } else {
                                          _selectedStudentIds.remove(s.id);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Create Button
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveClass,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                            )
                          : const Text(
                              "Create Class",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
