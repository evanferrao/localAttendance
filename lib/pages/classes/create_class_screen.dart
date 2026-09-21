import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/models/teacher.dart';
import 'package:face_att/pages/classes/widgets/class_student_selector.dart';
import 'package:face_att/pages/classes/widgets/class_teacher_selector.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:face_att/pages/students/create_student_screen.dart';
import 'package:face_att/pages/teachers/create_teacher_screen.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:face_att/widgets/ui_cards.dart';
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
                      _buildFirstRunBanner(colorScheme),
                      const SizedBox(height: 24),
                    ],

                    // Class Name
                    FormCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Class Information",
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
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
                    ClassTeacherSelector(
                      teachers: _allTeachers,
                      selectedTeacherIds: _selectedTeacherIds,
                      onTeacherToggled: (id) {
                        setState(() {
                          if (_selectedTeacherIds.contains(id)) {
                            _selectedTeacherIds.remove(id);
                          } else {
                            _selectedTeacherIds.add(id);
                          }
                        });
                      },
                      onNewTeacher: _createNewTeacher,
                    ),
                    const SizedBox(height: 20),

                    // Students Section
                    ClassStudentSelector(
                      students: _allStudents,
                      selectedStudentIds: _selectedStudentIds,
                      onStudentToggled: (id) {
                        setState(() {
                          if (_selectedStudentIds.contains(id)) {
                            _selectedStudentIds.remove(id);
                          } else {
                            _selectedStudentIds.add(id);
                          }
                        });
                      },
                      onNewStudent: _createNewStudent,
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

  Widget _buildFirstRunBanner(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
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
    );
  }
}
