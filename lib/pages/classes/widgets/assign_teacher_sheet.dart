import 'package:face_att/models/teacher.dart';
import 'package:flutter/material.dart';

/// Modal bottom sheet for searching and assigning unassigned teachers to a class.
class AssignTeacherSheet extends StatelessWidget {
  final List<Teacher> unassignedTeachers;
  final ValueChanged<Teacher> onTeacherSelected;
  final VoidCallback onCreateNewTeacher;

  const AssignTeacherSheet({
    super.key,
    required this.unassignedTeachers,
    required this.onTeacherSelected,
    required this.onCreateNewTeacher,
  });

  /// Displays the bottom sheet for assigning teachers.
  static Future<void> show(
    BuildContext context, {
    required List<Teacher> unassignedTeachers,
    required ValueChanged<Teacher> onTeacherSelected,
    required VoidCallback onCreateNewTeacher,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AssignTeacherSheet(
        unassignedTeachers: unassignedTeachers,
        onTeacherSelected: onTeacherSelected,
        onCreateNewTeacher: onCreateNewTeacher,
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
                "Assign Teacher",
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onCreateNewTeacher();
                },
                icon: Icon(Icons.add, size: 18, color: colorScheme.primary),
                label: Text("Create New", style: TextStyle(color: colorScheme.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (unassignedTeachers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                "All existing teachers are already assigned to this class.",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: unassignedTeachers.length,
                itemBuilder: (_, i) {
                  final t = unassignedTeachers[i];
                  return ListTile(
                    title: Text(t.displayName, style: TextStyle(color: colorScheme.onSurface)),
                    subtitle: Text("@${t.username}", style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    trailing: Icon(Icons.add_circle_outline, color: colorScheme.primary),
                    onTap: () {
                      Navigator.pop(context);
                      onTeacherSelected(t);
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
