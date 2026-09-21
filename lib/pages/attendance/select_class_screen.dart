import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/models/class_model.dart';
import 'package:face_att/models/teacher.dart';
import 'package:face_att/pages/attendance/select_date_screen.dart';
import 'package:flutter/material.dart';

class SelectClassScreen extends StatefulWidget {
  final Teacher teacher;
  const SelectClassScreen({super.key, required this.teacher});

  @override
  State<SelectClassScreen> createState() => _SelectClassScreenState();
}

class _SelectClassScreenState extends State<SelectClassScreen> {
  final ClassRepository _classRepo = ClassRepository();
  List<ClassModel> _classes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeacherClasses();
  }

  Future<void> _loadTeacherClasses() async {
    setState(() => _isLoading = true);
    final classes = await _classRepo.getClassesForTeacher(widget.teacher.id!);
    if (mounted) {
      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Select Class"),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.onPrimaryContainer,
                        child: const Icon(Icons.person),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Authenticated Teacher", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                          Text(
                            widget.teacher.displayName,
                            style: TextStyle(color: colorScheme.onSurface, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    "Your Assigned Classes (${_classes.length})",
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: _classes.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              "You are not currently assigned to any classes.\nPlease ask an administrator or assign yourself from the Classes dashboard.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                leading: CircleAvatar(
                                  backgroundColor: colorScheme.primaryContainer,
                                  foregroundColor: colorScheme.onPrimaryContainer,
                                  child: const Icon(Icons.class_),
                                ),
                                title: Text(
                                  c.name,
                                  style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 17),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    "${c.studentsCount} students enrolled",
                                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                                  ),
                                ),
                                trailing: Icon(Icons.arrow_forward_ios, size: 16, color: colorScheme.primary),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SelectDateScreen(
                                        teacher: widget.teacher,
                                        classModel: c,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
