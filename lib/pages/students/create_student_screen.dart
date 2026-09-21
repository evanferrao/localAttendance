import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/camera_screen.dart';
import 'package:face_att/pages/face_recognition/ml_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  final MLService _mlService = MLService();
  final ImagePicker _picker = ImagePicker();

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
      id: student.id?.toString() ?? student.registerNumber,
      name: student.name,
      email: student.email,
      phone: student.phone,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FaceScanScreen(
          isLogin: false,
          registerUser: user,
        ),
      ),
    );

    // Also mirror to registerNumber key in Hive for dual lookup support
    final enrolledUser = LocalDB.getUser(user.id);
    if (enrolledUser != null && enrolledUser.array != null) {
      await LocalDB.saveUser(User(
        id: student.registerNumber,
        name: student.name,
        email: student.email,
        phone: student.phone,
        array: enrolledUser.array,
      ));
    }

    if (mounted) {
      Navigator.pop(context, student.copyWith(hasFaceEnrolled: true));
    }
  }

  Future<void> _enrollWithPhoto() async {
    final student = await _saveStudentRecord();
    if (student == null || !mounted) return;

    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) {
      if (mounted) Navigator.pop(context, student);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final bytes = await xFile.readAsBytes();
      final user = await _mlService.enrollFromImageBytes(
        bytes: bytes,
        studentId: student.id?.toString() ?? student.registerNumber,
        name: student.name,
        email: student.email,
        phone: student.phone,
      );

      // Also mirror to registerNumber key
      await LocalDB.saveUser(User(
        id: student.registerNumber,
        name: student.name,
        email: student.email,
        phone: student.phone,
        array: user.array,
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.present,
            content: Text("Face enrolled from photo for ${student.name}!"),
          ),
        );
        Navigator.pop(context, student.copyWith(hasFaceEnrolled: true));
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
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
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
                      validator: (v) => (v == null || v.trim().isEmpty) ? "Register number is required" : null,
                    ),
                    const SizedBox(height: 16),

                    // Full Name
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Full Name",
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
                      validator: (v) => (v == null || v.trim().isEmpty) ? "Name is required" : null,
                    ),
                    const SizedBox(height: 16),

                    // Email
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Email",
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
                      validator: (v) => (v == null || v.trim().isEmpty) ? "Email is required" : null,
                    ),
                    const SizedBox(height: 16),

                    // Phone
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Phone Number",
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
                      validator: (v) => (v == null || v.trim().isEmpty) ? "Phone is required" : null,
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
