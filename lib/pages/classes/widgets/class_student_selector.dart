import 'package:face_att/models/student.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:face_att/widgets/ui_cards.dart';
import 'package:flutter/material.dart';

/// Reusable component for selecting students to enroll in a class.
class ClassStudentSelector extends StatelessWidget {
  final List<Student> students;
  final Set<int> selectedStudentIds;
  final ValueChanged<int> onStudentToggled;
  final VoidCallback onNewStudent;

  const ClassStudentSelector({
    super.key,
    required this.students,
    required this.selectedStudentIds,
    required this.onStudentToggled,
    required this.onNewStudent,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Students (${selectedStudentIds.length} selected)",
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onNewStudent,
                icon: Icon(Icons.add, size: 16, color: colorScheme.primary),
                label: Text("New Student", style: TextStyle(color: colorScheme.primary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (students.isEmpty)
            Text(
              "No students exist yet. Click above to add students now or add them later.",
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView(
                shrinkWrap: true,
                children: students.map((s) {
                  final isSelected = selectedStudentIds.contains(s.id);
                  return CheckboxListTile(
                    value: isSelected,
                    activeColor: colorScheme.primary,
                    checkColor: colorScheme.onPrimary,
                    title: Text(s.name, style: TextStyle(color: colorScheme.onSurface)),
                    subtitle: Text(
                      "${s.registerNumber} • ${s.hasFaceEnrolled ? 'Face Enrolled' : 'No Face'}",
                      style: TextStyle(
                        color: s.hasFaceEnrolled
                            ? AppColors.present
                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (bool? val) {
                      if (s.id != null) onStudentToggled(s.id!);
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
