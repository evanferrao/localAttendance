import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/pages/students/create_student_screen.dart';
import 'package:face_att/pages/students/student_detail_screen.dart';
import 'package:face_att/pages/students/widgets/student_import_dialogs.dart';
import 'package:face_att/services/student_import_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final StudentRepository _studentRepo = StudentRepository();
  final TextEditingController _searchController = TextEditingController();

  List<Student> _students = [];
  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'enrolled', 'needs_face'
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    final students = await _studentRepo.getAllStudents();
    if (mounted) {
      setState(() {
        _students = students;
        _isLoading = false;
      });
    }
  }

  void _addStudent() async {
    final created = await Navigator.push<Student>(
      context,
      MaterialPageRoute(builder: (_) => const CreateStudentScreen()),
    );
    if (created != null) {
      _loadStudents();
    }
  }

  Future<void> _importFromZip() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    if (!mounted) return;

    int current = 0;
    int total = 0;
    String currentLabel = 'Reading archive...';
    StateSetter? dialogSetState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setProgressState) {
            dialogSetState = setProgressState;
            final progress = total > 0 ? (current / total).clamp(0.0, 1.0) : null;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              content: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 16),
                    Text(
                      total > 0 ? "Enrolling student $current of $total" : "Extracting student ZIP...",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currentLabel,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    try {
      final importService = StudentImportService();
      StudentImportSummary summary;

      if (file.bytes != null) {
        summary = await importService.importFromZipBytes(
          zipBytes: file.bytes!,
          onProgress: (cur, tot, label) {
            if (dialogSetState != null) {
              dialogSetState!(() {
                current = cur;
                total = tot;
                currentLabel = label;
              });
            }
          },
        );
      } else if (file.path != null) {
        summary = await importService.importFromZipFile(
          filePath: file.path!,
          onProgress: (cur, tot, label) {
            if (dialogSetState != null) {
              dialogSetState!(() {
                current = cur;
                total = tot;
                currentLabel = label;
              });
            }
          },
        );
      } else {
        throw Exception("Unable to read selected ZIP file data.");
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss progress dialog
        await StudentImportDialogs.showSummaryDialog(context, summary: summary);
        _loadStudents();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.absent,
            content: Text("ZIP Import Failed: $e"),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final filtered = _students.where((s) {
      final matchesSearch = _searchQuery.isEmpty ||
          s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.registerNumber.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;
      if (_filterMode == 'enrolled') return s.hasFaceEnrolled;
      if (_filterMode == 'needs_face') return !s.hasFaceEnrolled;
      return true;
    }).toList();

    final enrolledCount = _students.where((s) => s.hasFaceEnrolled).length;
    final needsFaceCount = _students.length - enrolledCount;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Manage Students"),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: "Import Students (ZIP)",
            onPressed: _importFromZip,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: "Search by name or roll number...",
                      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                      prefixIcon: Icon(Icons.search, color: colorScheme.primary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: colorScheme.surfaceContainer,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),

                // Filter Chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      FilterChip(
                        label: Text("All (${_students.length})"),
                        selected: _filterMode == 'all',
                        onSelected: (_) => setState(() => _filterMode = 'all'),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text("Enrolled ($enrolledCount)"),
                        selected: _filterMode == 'enrolled',
                        onSelected: (_) => setState(() => _filterMode = 'enrolled'),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text("Needs Face ($needsFaceCount)"),
                        selected: _filterMode == 'needs_face',
                        onSelected: (_) => setState(() => _filterMode = 'needs_face'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Student List / Empty States
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadStudents,
                    child: _students.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.school_outlined, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                                    const SizedBox(height: 16),
                                    Text("No students found", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 18)),
                                    const SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      onPressed: _addStudent,
                                      icon: const Icon(Icons.add),
                                      label: const Text("Add Student"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: colorScheme.primary,
                                        foregroundColor: colorScheme.onPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : filtered.isEmpty
                            ? ListView(
                                children: [
                                  SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                                  Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.search_off_rounded, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                                        const SizedBox(height: 12),
                                        Text(
                                          "No matching students found",
                                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(20),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final student = filtered[index];
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainer,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      leading: CircleAvatar(
                                        backgroundColor: student.hasFaceEnrolled
                                            ? AppColors.present.withValues(alpha: 0.2)
                                            : AppColors.warning.withValues(alpha: 0.2),
                                        foregroundColor: student.hasFaceEnrolled ? AppColors.present : AppColors.warning,
                                        child: Icon(
                                          student.hasFaceEnrolled ? Icons.face : Icons.face_outlined,
                                        ),
                                      ),
                                      title: Text(
                                        student.displayName,
                                        style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      subtitle: Text(
                                        student.name.isNotEmpty
                                            ? student.registerNumber
                                            : (student.email.isNotEmpty
                                                ? student.email
                                                : (student.phone.isNotEmpty ? student.phone : "Student")),
                                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                                      ),
                                      trailing: Icon(
                                        student.hasFaceEnrolled ? Icons.verified : Icons.warning_amber_rounded,
                                        color: student.hasFaceEnrolled ? AppColors.present : AppColors.warning,
                                        size: 20,
                                      ),
                                      onTap: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => StudentDetailScreen(student: student)),
                                        );
                                        _loadStudents();
                                      },
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStudent,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text("Add Student", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
