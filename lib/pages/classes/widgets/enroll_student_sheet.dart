import 'package:face_att/models/student.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

/// Modal bottom sheet for searching, selecting multiple students with checkboxes,
/// and enrolling them simultaneously into a class.
class EnrollStudentSheet extends StatefulWidget {
  final List<Student> unenrolledStudents;
  final ValueChanged<List<Student>> onStudentsSelected;
  final VoidCallback onCreateNewStudent;

  const EnrollStudentSheet({
    super.key,
    required this.unenrolledStudents,
    required this.onStudentsSelected,
    required this.onCreateNewStudent,
  });

  /// Displays the modal bottom sheet for multi-student enrollment.
  static Future<void> show(
    BuildContext context, {
    required List<Student> unenrolledStudents,
    required ValueChanged<List<Student>> onStudentsSelected,
    required VoidCallback onCreateNewStudent,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: EnrollStudentSheet(
          unenrolledStudents: unenrolledStudents,
          onStudentsSelected: onStudentsSelected,
          onCreateNewStudent: onCreateNewStudent,
        ),
      ),
    );
  }

  @override
  State<EnrollStudentSheet> createState() => _EnrollStudentSheetState();
}

class _EnrollStudentSheetState extends State<EnrollStudentSheet> {
  final Set<String> _selectedRegNos = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Student> get _filteredStudents {
    if (_searchQuery.isEmpty) return widget.unenrolledStudents;
    final query = _searchQuery.toLowerCase();
    return widget.unenrolledStudents.where((s) {
      return s.name.toLowerCase().contains(query) ||
          s.registerNumber.toLowerCase().contains(query);
    }).toList();
  }

  void _toggleSelectAll(List<Student> visibleStudents) {
    setState(() {
      final allVisibleSelected = visibleStudents.every(
        (s) => _selectedRegNos.contains(s.registerNumber),
      );
      if (allVisibleSelected) {
        for (final s in visibleStudents) {
          _selectedRegNos.remove(s.registerNumber);
        }
      } else {
        for (final s in visibleStudents) {
          _selectedRegNos.add(s.registerNumber);
        }
      }
    });
  }

  void _submitSelection() {
    final selectedStudents = widget.unenrolledStudents
        .where((s) => _selectedRegNos.contains(s.registerNumber))
        .toList();
    Navigator.pop(context);
    widget.onStudentsSelected(selectedStudents);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visible = _filteredStudents;
    final allVisibleSelected = visible.isNotEmpty &&
        visible.every((s) => _selectedRegNos.contains(s.registerNumber));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Enroll Students",
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "${_selectedRegNos.length} selected of ${widget.unenrolledStudents.length}",
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onCreateNewStudent();
                  },
                  icon: Icon(Icons.person_add_alt_1, size: 18, color: colorScheme.primary),
                  label: Text("Create New", style: TextStyle(color: colorScheme.primary)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (widget.unenrolledStudents.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    "All registered students are already in this class.",
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else ...[
              // Search & Select All Bar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      decoration: InputDecoration(
                        hintText: "Search students...",
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: visible.isEmpty ? null : () => _toggleSelectAll(visible),
                    child: Text(allVisibleSelected ? "Deselect All" : "Select All"),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Student Checkbox List
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          "No matching students found",
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final s = visible[i];
                          final isSelected = _selectedRegNos.contains(s.registerNumber);

                          return CheckboxListTile(
                            value: isSelected,
                            activeColor: colorScheme.primary,
                            checkColor: colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            secondary: CircleAvatar(
                              radius: 18,
                              backgroundColor: s.hasFaceEnrolled
                                  ? AppColors.present.withValues(alpha: 0.15)
                                  : AppColors.warning.withValues(alpha: 0.15),
                              foregroundColor: s.hasFaceEnrolled ? AppColors.present : AppColors.warning,
                              child: Icon(s.hasFaceEnrolled ? Icons.face : Icons.face_outlined, size: 20),
                            ),
                            title: Text(
                              s.name.isNotEmpty ? s.name : s.registerNumber,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              s.name.isNotEmpty
                                  ? "${s.registerNumber} • ${s.hasFaceEnrolled ? 'Face Enrolled' : 'No Face'}"
                                  : (s.hasFaceEnrolled ? 'Face Enrolled' : 'No Face'),
                              style: TextStyle(
                                color: s.hasFaceEnrolled
                                    ? AppColors.present
                                    : colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            onChanged: (bool? val) {
                              setState(() {
                                if (val == true) {
                                  _selectedRegNos.add(s.registerNumber);
                                } else {
                                  _selectedRegNos.remove(s.registerNumber);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),

              const SizedBox(height: 12),

              // Bottom Confirmation Button
              FilledButton.icon(
                onPressed: _selectedRegNos.isEmpty ? null : _submitSelection,
                icon: const Icon(Icons.person_add),
                label: Text(
                  _selectedRegNos.isEmpty
                      ? "Select Students to Enroll"
                      : "Enroll Selected (${_selectedRegNos.length})",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
