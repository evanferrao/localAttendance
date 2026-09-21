import 'package:face_att/models/teacher.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:face_att/widgets/ui_cards.dart';
import 'package:flutter/material.dart';

/// Reusable component for selecting teachers to assign to a class.
class ClassTeacherSelector extends StatelessWidget {
  final List<Teacher> teachers;
  final Set<int> selectedTeacherIds;
  final ValueChanged<int> onTeacherToggled;
  final VoidCallback onNewTeacher;

  const ClassTeacherSelector({
    super.key,
    required this.teachers,
    required this.selectedTeacherIds,
    required this.onTeacherToggled,
    required this.onNewTeacher,
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
                  "Teachers *",
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onNewTeacher,
                icon: Icon(Icons.add, size: 16, color: colorScheme.primary),
                label: Text("New Teacher", style: TextStyle(color: colorScheme.primary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (teachers.isEmpty)
            const Text(
              "No teachers exist yet. Click above to create one.",
              style: TextStyle(color: AppColors.warning),
            )
          else
            Column(
              children: teachers.map((t) {
                final isSelected = selectedTeacherIds.contains(t.id);
                return CheckboxListTile(
                  value: isSelected,
                  activeColor: colorScheme.primary,
                  checkColor: colorScheme.onPrimary,
                  title: Text(t.displayName, style: TextStyle(color: colorScheme.onSurface)),
                  subtitle: Text("@${t.username}", style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  onChanged: (bool? val) {
                    if (t.id != null) onTeacherToggled(t.id!);
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
