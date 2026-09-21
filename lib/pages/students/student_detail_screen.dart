import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/class_model.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/camera_screen.dart';
import 'package:face_att/services/face_recognition/face_enrollment_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:face_att/widgets/ui_cards.dart';
import 'package:flutter/material.dart';

class StudentDetailScreen extends StatefulWidget {
  final Student student;
  const StudentDetailScreen({super.key, required this.student});

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  final StudentRepository _studentRepo = StudentRepository();
  final ClassRepository _classRepo = ClassRepository();
  final FaceEnrollmentService _enrollmentService = FaceEnrollmentService();

  late Student _student;
  List<ClassModel> _classes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    if (_student.id != null) {
      final updated = await _studentRepo.getStudentById(_student.id!);
      if (updated != null) _student = updated;

      final allClasses = await _classRepo.getAllClasses();
      final enrolledClasses = <ClassModel>[];
      for (final c in allClasses) {
        if (c.id != null) {
          final isEnrolled = await _classRepo.isStudentEnrolledInClass(_student.id!, c.id!);
          if (isEnrolled) enrolledClasses.add(c);
        }
      }
      _classes = enrolledClasses;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _enrollWithCamera() async {
    final user = User(
      id: _student.id?.toString() ?? _student.registerNumber,
      name: _student.name,
      email: _student.email,
      phone: _student.phone,
    );

    final enrolled = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceScanScreen(
          isLogin: false,
          registerUser: user,
        ),
      ),
    );

    if (enrolled == true) {
      await _enrollmentService.syncAfterCameraEnrollment(_student);
      _loadData();
    }
  }

  Future<void> _enrollWithPhoto() async {
    try {
      final user = await _enrollmentService.enrollFromGallery(_student);
      if (user != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.present,
            content: Text("Face registered for ${_student.name}!"),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.absent, content: Text("Enrollment failed: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_student.name),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Card
                  FormCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: colorScheme.primaryContainer,
                              foregroundColor: colorScheme.onPrimaryContainer,
                              child: const Icon(Icons.school, size: 32),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _student.name,
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _student.registerNumber,
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Divider(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                          height: 32,
                        ),

                        _infoRow(Icons.email_outlined, _student.email, colorScheme),
                        const SizedBox(height: 12),
                        _infoRow(Icons.phone_outlined, _student.phone, colorScheme),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Icon(
                              _student.hasFaceEnrolled ? Icons.verified : Icons.warning_amber_rounded,
                              size: 18,
                              color: _student.hasFaceEnrolled ? AppColors.present : AppColors.warning,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _student.hasFaceEnrolled ? "Face Enrolled (512D ArcFace)" : "Face Not Enrolled",
                              style: TextStyle(
                                color: _student.hasFaceEnrolled ? AppColors.present : AppColors.warning,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Enrolled Classes Card
                  FormCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Enrolled Classes",
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_classes.isEmpty)
                          Text("Not enrolled in any classes yet.", style: TextStyle(color: colorScheme.onSurfaceVariant))
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _classes.map((c) {
                              return Chip(
                                backgroundColor: colorScheme.surfaceContainerHigh,
                                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                                label: Text(c.name, style: TextStyle(color: colorScheme.onSurface)),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Face Enrollment Actions
                  ElevatedButton.icon(
                    onPressed: _enrollWithCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(
                      _student.hasFaceEnrolled ? "Re-scan Face (Camera)" : "Register Face (Camera)",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: _enrollWithPhoto,
                    icon: const Icon(Icons.photo_library),
                    label: const Text("Enroll Face from Photo"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(IconData icon, String text, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, color: colorScheme.onSurfaceVariant, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: colorScheme.onSurfaceVariant))),
      ],
    );
  }
}
