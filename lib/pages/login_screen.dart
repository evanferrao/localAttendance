import 'package:face_att/pages/face_recognition/camera_screen.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();

  bool get _hasRegisteredUser => LocalDB.hasUser;

  void _goToRegister() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name first")),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FaceScanScreen(isLogin: false, registerName: name),
      ),
    );
  }

  void _goToLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FaceScanScreen(isLogin: true),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasUser = _hasRegisteredUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.face_retouching_natural, size: 80, color: Colors.greenAccent),
              const SizedBox(height: 24),
              const Text(
                "Face Attendance",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Register or log in with your face",
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 48),

              // Name field (only needed for register)
              if (!hasUser) ...[
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Enter your name",
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.person, color: Colors.white38),
                  ),
                ),
                const SizedBox(height: 16),
                _ActionButton(
                  label: "Register Face",
                  icon: Icons.how_to_reg,
                  color: Colors.greenAccent,
                  onTap: _goToRegister,
                ),
              ],

              if (hasUser) ...[
                _ActionButton(
                  label: "Login with Face",
                  icon: Icons.login,
                  color: Colors.blueAccent,
                  onTap: _goToLogin,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    await HiveBoxes.clearAllBox();
                    setState(() {});
                  },
                  child: const Text(
                    "Re-register (clear data)",
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.black),
        label: Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
