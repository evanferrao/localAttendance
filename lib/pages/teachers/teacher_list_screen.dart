import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/teacher.dart';
import 'package:face_att/pages/teachers/create_teacher_screen.dart';
import 'package:flutter/material.dart';

class TeacherListScreen extends StatefulWidget {
  const TeacherListScreen({super.key});

  @override
  State<TeacherListScreen> createState() => _TeacherListScreenState();
}

class _TeacherListScreenState extends State<TeacherListScreen> {
  final TeacherRepository _teacherRepo = TeacherRepository();
  final TextEditingController _searchController = TextEditingController();

  List<Teacher> _teachers = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    setState(() => _isLoading = true);
    final teachers = await _teacherRepo.getAllTeachers();
    if (mounted) {
      setState(() {
        _teachers = teachers;
        _isLoading = false;
      });
    }
  }

  void _addTeacher() async {
    final created = await Navigator.push<Teacher>(
      context,
      MaterialPageRoute(builder: (_) => const CreateTeacherScreen()),
    );
    if (created != null) {
      _loadTeachers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final filtered = _teachers.where((t) {
      return _searchQuery.isEmpty ||
          t.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          t.username.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Manage Teachers"),
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
                      hintText: "Search teachers by name or username...",
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

                // Teachers List
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadTeachers,
                    child: _teachers.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.people_outline, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                                    const SizedBox(height: 16),
                                    Text("No teachers found", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 18)),
                                    const SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      onPressed: _addTeacher,
                                      icon: const Icon(Icons.add),
                                      label: const Text("Add Teacher"),
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
                                          "No matching teachers found",
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
                                  final teacher = filtered[index];
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainer,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      leading: CircleAvatar(
                                        backgroundColor: colorScheme.primaryContainer,
                                        foregroundColor: colorScheme.onPrimaryContainer,
                                        child: Text(
                                          teacher.displayName.isNotEmpty
                                              ? teacher.displayName[0].toUpperCase()
                                              : 'T',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      title: Text(
                                        teacher.displayName,
                                        style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      subtitle: Text(
                                        "@${teacher.username}",
                                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTeacher,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text("Add Teacher", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
