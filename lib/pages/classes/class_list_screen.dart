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
  final TextEditingController _searchController = TextEditingController();

  List<ClassModel> _classes = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    final filtered = _classes.where((c) {
      return _searchQuery.isEmpty || c.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Manage Classes"),
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
                      hintText: "Search classes...",
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

                // Classes List
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadClasses,
                    child: _classes.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                              Center(
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
                                padding: const EdgeInsets.all(20),
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
                  ),
                ),
              ],
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
