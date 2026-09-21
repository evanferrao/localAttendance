import 'package:face_att/models/student.dart';
import 'package:flutter/material.dart';

/// Modal bottom sheet for searching and enrolling students into a class.
class EnrollStudentSheet extends StatelessWidget {
  final List<Student> unenrolledStudents;
  final ValueChanged<Student> onStudentSelected;
  final VoidCallback onCreateNewStudent;

  const EnrollStudentSheet({
    super.key,
    required this.unenrolledStudents,
    required this.onStudentSelected,
    required this.onCreateNewStudent,
  });

  /// Displays the bottom sheet for enrolling students.
  static Future<void> show(
    BuildContext context, {
    required List<Student> unenrolledStudents,
    required ValueChanged<Student> onStudentSelected,
    required VoidCallback onCreateNewStudent,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EnrollStudentSheet(
        unenrolledStudents: unenrolledStudents,
        onStudentSelected: onStudentSelected,
        onCreateNewStudent: onCreateNewStudent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Enroll Student",
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onCreateNewStudent();
                },
                icon: Icon(Icons.add, size: 18, color: colorScheme.primary),
                label: Text("Create New", style: TextStyle(color: colorScheme.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (unenrolledStudents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                "All registered students are already in this class.",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: unenrolledStudents.length,
                itemBuilder: (_, i) {
                  final s = unenrolledStudents[i];
                  return ListTile(
                    title: Text(s.name, style: TextStyle(color: colorScheme.onSurface)),
                    subtitle: Text(s.registerNumber, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    trailing: Icon(Icons.add_circle_outline, color: colorScheme.primary),
                    onTap: () {
                      Navigator.pop(context);
                      onStudentSelected(s);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
