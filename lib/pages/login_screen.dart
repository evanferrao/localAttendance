import 'package:face_att/models/user.dart';
import 'package:face_att/pages/face_recognition/camera_screen.dart';
import 'package:face_att/pages/signup_screen.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<User> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _loadUsers() {
    setState(() => _users = LocalDB.getUsers());
  }

  void _loginWithFace(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FaceScanScreen(isLogin: true)),
    ).then((_) => _loadUsers());
  }

  void _goToSignup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    ).then((_) => _loadUsers());
  }

  Future<void> _deleteUser(User user) async {
    await LocalDB.deleteUser(user.id);
    _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // Header
              Row(
                children: [
                  const Icon(Icons.face_retouching_natural, size: 36, color: Colors.greenAccent),
                  const SizedBox(width: 12),
                  const Text(
                    "Face Attendance",
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  // Add user button
                  IconButton(
                    onPressed: () => _goToSignup(context),
                    icon: const Icon(Icons.person_add_alt_1, color: Colors.greenAccent),
                    tooltip: "Register new user",
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Face login button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => _loginWithFace(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.face_retouching_natural, color: Colors.black, size: 22),
                      SizedBox(width: 10),
                      Text(
                        "Login with Face Scan",
                        style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // User list header
              Row(
                children: [
                  const Text("Registered users", style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 0.5)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_users.length}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // User list
              Expanded(
                child: _users.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_off_outlined, color: Colors.white24, size: 48),
                            const SizedBox(height: 12),
                            const Text("No users registered yet", style: TextStyle(color: Colors.white38)),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () => _goToSignup(context),
                              icon: const Icon(Icons.add, color: Colors.greenAccent),
                              label: const Text("Register first user", style: TextStyle(color: Colors.greenAccent)),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _users.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _UserTile(
                          user: _users[i],
                          onDelete: () => _deleteUser(_users[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final User user;
  final VoidCallback onDelete;

  const _UserTile({required this.user, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            backgroundColor: Colors.greenAccent.withOpacity(0.15),
            child: Text(
              (user.name ?? '?')[0].toUpperCase(),
              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name ?? 'Unknown',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                ),
                if (user.email != null && user.email!.isNotEmpty)
                  Text(user.email!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),

          // Face registered indicator
          Icon(
            user.array != null ? Icons.verified : Icons.warning_amber_rounded,
            color: user.array != null ? Colors.greenAccent : Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 8),

          // Delete
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                title: const Text("Remove user", style: TextStyle(color: Colors.white)),
                content: Text("Remove ${user.name} from registered users?", style: const TextStyle(color: Colors.white54)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onDelete();
                    },
                    child: const Text("Remove", style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
