import 'package:face_att/models/user.dart';
import 'package:face_att/pages/login_screen.dart';
import 'package:face_att/pages/signup_screen.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  final User user;
  const HomeScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text("Dashboard"),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_user, size: 80, color: Colors.greenAccent),
              const SizedBox(height: 24),
              Text(
                "Welcome, ${user.name}!",
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text("Face authentication successful", style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 24),

              // Profile card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    if (user.email != null && user.email!.isNotEmpty) _InfoRow(Icons.email_outlined, user.email!),
                    if (user.phone != null && user.phone!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _InfoRow(Icons.phone_outlined, user.phone!),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () async {
                  await LocalDB.deleteUser(user.id);
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                      (_) => false,
                    );
                  }
                },
                icon: const Icon(Icons.delete_forever),
                label: const Text("Clear & Re-register"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
