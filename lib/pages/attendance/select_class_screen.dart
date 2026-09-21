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
  final TextEditingController _searchController = TextEditingController();

  List<ClassModel> _classes = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeacherClasses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    final filtered = _classes.where((c) {
      return _searchQuery.isEmpty || c.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

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

                // Search Bar if teacher has multiple classes
                if (_classes.length > 2)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: "Search your classes...",
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

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    "Your Assigned Classes (${_classes.length})",
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadTeacherClasses,
                    child: _classes.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    "You are not currently assigned to any classes.\nPlease ask an administrator or assign yourself from the Classes dashboard.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                                  ),
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
                                          "No matching classes found",
                                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final c = filtered[index];
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
                ),
              ],
            ),
    );
  }
}
