import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/models/teacher.dart';
import 'package:sqflite/sqflite.dart';

class TeacherRepository {
  final AppDatabase _dbManager;
  TeacherRepository([AppDatabase? dbManager]) : _dbManager = dbManager ?? AppDatabase.instance;

  Future<Database> get _db => _dbManager.database;

  Future<Teacher> createTeacher({
    required String username,
    required String passwordHash,
    required String displayName,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert(
      DatabaseSchema.tableTeachers,
      {
        'username': username.trim(),
        'password_hash': passwordHash,
        'display_name': displayName.trim(),
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return Teacher(
      id: id,
      username: username.trim(),
      passwordHash: passwordHash,
      displayName: displayName.trim(),
      createdAt: now,
    );
  }

  Future<List<Teacher>> getAllTeachers() async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableTeachers,
      orderBy: 'display_name ASC',
    );
    return rows.map((r) => Teacher.fromMap(r)).toList();
  }

  Future<Teacher?> getTeacherById(int id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableTeachers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Teacher.fromMap(rows.first);
  }

  Future<Teacher?> getTeacherByUsername(String username) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableTeachers,
      where: 'LOWER(username) = LOWER(?)',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Teacher.fromMap(rows.first);
  }

  Future<List<Teacher>> getTeachersForClass(int classId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT t.* FROM ${DatabaseSchema.tableTeachers} t
      INNER JOIN ${DatabaseSchema.tableClassTeachers} ct ON t.id = ct.teacher_id
      WHERE ct.class_id = ?
      ORDER BY t.display_name ASC
    ''', [classId]);
    return rows.map((r) => Teacher.fromMap(r)).toList();
  }

  Future<int> updateTeacher(Teacher teacher) async {
    final db = await _db;
    return await db.update(
      DatabaseSchema.tableTeachers,
      teacher.toMap(),
      where: 'id = ?',
      whereArgs: [teacher.id],
    );
  }

  Future<int> deleteTeacher(int id) async {
    final db = await _db;
    return await db.delete(
      DatabaseSchema.tableTeachers,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
