import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/models/class_model.dart';
import 'package:face_att/pages/classes/class_detail_screen.dart';
import 'package:face_att/pages/classes/create_class_screen.dart';
import 'package:flutter/material.dart';

class ClassListScreen extends StatefulWidget {
  const ClassListScreen({super.key});

  @override
  State<ClassListScreen> createState() => _ClassListScreenState();
}

class _ClassListScreenState extends State<ClassListScreen> {
  final ClassRepository _classRepo = ClassRepository();
  List<ClassModel> _classes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    final classes = await _classRepo.getAllClasses();
    if (mounted) {
      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    }
  }

  void _addClass() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateClassScreen()),
    );
    _loadClasses();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Manage Classes"),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _classes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.class_outlined, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text("No classes found", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 18)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _addClass,
                        icon: const Icon(Icons.add),
                        label: const Text("Create Class"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _classes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final c = _classes[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                          child: const Icon(Icons.class_),
                        ),
                        title: Text(
                          c.name,
                          style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "Teachers: ${c.teachersCount}   •   Students: ${c.studentsCount}",
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                          ),
                        ),
                        trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ClassDetailScreen(classModel: c)),
                          );
                          _loadClasses();
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addClass,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text("Create Class", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
