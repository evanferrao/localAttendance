import 'package:face_att/pages/face_recognition/camera_screen.dart';
import 'package:face_att/pages/signup_screen.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _loginWithFace(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FaceScanScreen(isLogin: true)),
    );
  }

  void _goToSignup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.greenAccent, width: 2),
                ),
                child: const Icon(Icons.face_retouching_natural, size: 52, color: Colors.greenAccent),
              ),
              const SizedBox(height: 28),
              const Text(
                "Face Attendance",
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Sign in with your face",
                style: TextStyle(color: Colors.white54, fontSize: 15),
              ),

              const SizedBox(height: 56),

              // Primary: face scan login button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _loginWithFace(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.face_retouching_natural, color: Colors.black, size: 24),
                      SizedBox(width: 10),
                      Text(
                        "Login with Face Scan",
                        style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Divider
              Row(
                children: [
                  const Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text("or", style: TextStyle(color: Colors.white.withOpacity(0.3))),
                  ),
                  const Expanded(child: Divider(color: Colors.white12)),
                ],
              ),

              const SizedBox(height: 16),

              // Secondary: go to signup
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _goToSignup(context),
                  icon: const Icon(Icons.person_add_alt_1, color: Colors.white70, size: 20),
                  label: const Text(
                    "Create an account",
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),

              const Spacer(),

              // Re-register option if already registered
              if (LocalDB.hasUser)
                TextButton(
                  onPressed: () async {
                    await HiveBoxes.clearAllBox();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      );
                    }
                  },
                  child: const Text(
                    "Re-register face",
                    style: TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
