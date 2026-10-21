import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/camera_screen.dart';
import 'package:face_att/services/face_recognition/face_enrollment_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:face_att/utils/utils.dart';
import 'package:face_att/widgets/ui_cards.dart';
import 'package:flutter/material.dart';

class CreateStudentScreen extends StatefulWidget {
  const CreateStudentScreen({super.key});

  @override
  State<CreateStudentScreen> createState() => _CreateStudentScreenState();
}

class _CreateStudentScreenState extends State<CreateStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _regNoController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  final StudentRepository _studentRepo = StudentRepository();
  final FaceEnrollmentService _enrollmentService = FaceEnrollmentService();

  bool _isLoading = false;

  @override
  void dispose() {
    _regNoController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitOnly() async {
    final student = await _saveStudentRecord();
    if (student != null && mounted) {
      Navigator.pop(context, student);
    }
  }

  Future<Student?> _saveStudentRecord() async {
    if (!_formKey.currentState!.validate()) return null;

    setState(() => _isLoading = true);
    try {
      final regNo = _regNoController.text.trim();
      final existing = await _studentRepo.getStudentByRegisterNumber(regNo);
      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.absent,
              content: Text("A student with this Register Number already exists"),
            ),
          );
        }
        return null;
      }

      final student = await _studentRepo.createStudent(
        registerNumber: regNo,
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      return student;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.absent,
            content: Text("Failed to save student: $e"),
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _enrollWithCamera() async {
    final student = await _saveStudentRecord();
    if (student == null || !mounted) return;

    final user = User(
      registerNumber: student.registerNumber,
      name: student.name,
      email: student.email,
      phone: student.phone,
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
      await _enrollmentService.syncAfterCameraEnrollment(student);
    }

    if (mounted) {
      Navigator.pop(context, student.copyWith(hasFaceEnrolled: enrolled == true));
    }
  }

  Future<void> _enrollWithPhoto() async {
    final student = await _saveStudentRecord();
    if (student == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final user = await _enrollmentService.enrollFromGallery(student);

      if (user != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.present,
            content: Text("Face enrolled from photo for ${student.name}!"),
          ),
        );
        Navigator.pop(context, student.copyWith(hasFaceEnrolled: true));
      } else if (mounted) {
        Navigator.pop(context, student);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.absent, content: Text("Photo enrollment failed: $e")),
        );
        Navigator.pop(context, student);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Add Student"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormCard(
                child: Column(
                  children: [
                    Icon(Icons.school, size: 50, color: colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      "Student Profile",
                      style: TextStyle(color: colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    // Register Number
                    TextFormField(
                      controller: _regNoController,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Register Number",
                        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                        hintText: "e.g. 23BRS1150",
                        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        prefixIcon: Icon(Icons.confirmation_number_outlined, color: colorScheme.primary),
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
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return "Register number is required";
                        if (!ValidationUtils.isValidRegisterNumber(v)) return "Invalid register number (no spaces allowed)";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Full Name (Optional)
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Full Name (Optional)",
                        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                        hintText: "e.g. Piyush R Saini",
                        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        prefixIcon: Icon(Icons.person_outline, color: colorScheme.primary),
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
                      validator: null,
                    ),
                    const SizedBox(height: 16),

                    // Email (Optional)
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Email (Optional)",
                        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                        hintText: "student@example.com",
                        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        prefixIcon: Icon(Icons.email_outlined, color: colorScheme.primary),
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
                      validator: (v) {
                        if (v != null && v.trim().isNotEmpty && !ValidationUtils.isValidEmail(v)) {
                          return "Enter a valid email (e.g. user@example.com)";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Phone (Optional)
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Phone Number (Optional)",
                        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                        hintText: "9876543210",
                        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        prefixIcon: Icon(Icons.phone_outlined, color: colorScheme.primary),
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
                      validator: (v) {
                        if (v != null && v.trim().isNotEmpty && !ValidationUtils.isValidPhone(v)) {
                          return "Enter a valid phone number (at least 7 digits)";
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Save & Face enrollment options
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _enrollWithCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text("Save & Enroll Face (Camera)", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: _isLoading ? null : _enrollWithPhoto,
                icon: const Icon(Icons.photo_library),
                label: const Text("Save & Enroll from Photo"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              TextButton(
                onPressed: _isLoading ? null : _submitOnly,
                child: Text("Save Student (Enroll Face Later)", style: TextStyle(color: colorScheme.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
