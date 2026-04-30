import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/camera_screen.dart';
import 'package:flutter/material.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  void _proceed() {
    if (!_formKey.currentState!.validate()) return;

    final user = User(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => FaceScanScreen(
          isLogin: false,
          registerName: user.name,
          registerUser: user,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const Icon(Icons.person_add_alt_1, size: 56, color: Colors.greenAccent),
                const SizedBox(height: 20),
                const Text(
                  "Create your profile",
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Fill in your details, then we'll scan your face.",
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 36),
                _FormField(
                  controller: _nameController,
                  label: "Full name",
                  icon: Icons.person_outline,
                  validator: (v) => v == null || v.trim().isEmpty ? "Name is required" : null,
                ),
                const SizedBox(height: 16),
                _FormField(
                  controller: _emailController,
                  label: "Email address",
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return "Email is required";
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                      return "Enter a valid email";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _FormField(
                  controller: _phoneController,
                  label: "Phone number",
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty ? "Phone is required" : null,
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _proceed,
                    icon: const Icon(Icons.face_retouching_natural, color: Colors.black),
                    label: const Text(
                      "Continue to face scan",
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
    );
  }
}
