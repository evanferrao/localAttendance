import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/models/class_model.dart';
import 'package:sqflite/sqflite.dart';

class ClassRepository {
  final AppDatabase _dbManager;
  ClassRepository([AppDatabase? dbManager]) : _dbManager = dbManager ?? AppDatabase.instance;

  Future<Database> get _db => _dbManager.database;

  /// Creates a class with teachers and students in an atomic transaction.
  /// Enforces: at least 1 teacher must be assigned.
  Future<ClassModel> createClass({
    required String name,
    required List<int> teacherIds,
    List<int> studentIds = const [],
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Class name cannot be empty');
    }
    final uniqueTeacherIds = teacherIds.toSet().toList();
    if (uniqueTeacherIds.isEmpty) {
      throw ArgumentError('A class must have at least one teacher assigned');
    }
    final uniqueStudentIds = studentIds.toSet().toList();

    final db = await _db;
    final now = DateTime.now().toIso8601String();

    return await db.transaction((txn) async {
      // 1. Insert class
      final classId = await txn.insert(
        DatabaseSchema.tableClasses,
        {
          'name': trimmedName,
          'created_at': now,
        },
      );

      // 2. Insert teacher assignments
      for (final tId in uniqueTeacherIds) {
        await txn.insert(
          DatabaseSchema.tableClassTeachers,
          {
            'class_id': classId,
            'teacher_id': tId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // 3. Insert student memberships
      for (final sId in uniqueStudentIds) {
        await txn.insert(
          DatabaseSchema.tableClassStudents,
          {
            'class_id': classId,
            'student_id': sId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      return ClassModel(
        id: classId,
        name: trimmedName,
        createdAt: now,
        teacherIds: uniqueTeacherIds,
        studentIds: uniqueStudentIds,
        teachersCount: uniqueTeacherIds.length,
        studentsCount: uniqueStudentIds.length,
      );
    });
  }

  Future<List<ClassModel>> getAllClasses() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT 
        c.*,
        COUNT(DISTINCT ct.teacher_id) AS teacher_count,
        COUNT(DISTINCT cs.student_id) AS student_count
      FROM ${DatabaseSchema.tableClasses} c
      LEFT JOIN ${DatabaseSchema.tableClassTeachers} ct ON c.id = ct.class_id
      LEFT JOIN ${DatabaseSchema.tableClassStudents} cs ON c.id = cs.class_id
      GROUP BY c.id
      ORDER BY c.name ASC
    ''');

    return rows.map((r) {
      return ClassModel.fromMap(
        r,
        teachersCount: (r['teacher_count'] as num?)?.toInt() ?? 0,
        studentsCount: (r['student_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  Future<ClassModel?> getClassById(int id) async {
    final db = await _db;
    final classRows = await db.query(
      DatabaseSchema.tableClasses,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (classRows.isEmpty) return null;

    final teacherRows = await db.query(
      DatabaseSchema.tableClassTeachers,
      columns: ['teacher_id'],
      where: 'class_id = ?',
      whereArgs: [id],
    );
    final teacherIds = teacherRows.map((r) => r['teacher_id'] as int).toList();

    final studentRows = await db.query(
      DatabaseSchema.tableClassStudents,
      columns: ['student_id'],
      where: 'class_id = ?',
      whereArgs: [id],
    );
    final studentIds = studentRows.map((r) => r['student_id'] as int).toList();

    return ClassModel.fromMap(
      classRows.first,
      teacherIds: teacherIds,
      studentIds: studentIds,
      teachersCount: teacherIds.length,
      studentsCount: studentIds.length,
    );
  }

  Future<List<ClassModel>> getClassesForTeacher(int teacherId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT 
        c.*,
        COUNT(DISTINCT ct2.teacher_id) AS teacher_count,
        COUNT(DISTINCT cs.student_id) AS student_count
      FROM ${DatabaseSchema.tableClasses} c
      INNER JOIN ${DatabaseSchema.tableClassTeachers} ct ON c.id = ct.class_id
      LEFT JOIN ${DatabaseSchema.tableClassTeachers} ct2 ON c.id = ct2.class_id
      LEFT JOIN ${DatabaseSchema.tableClassStudents} cs ON c.id = cs.class_id
      WHERE ct.teacher_id = ?
      GROUP BY c.id
      ORDER BY c.name ASC
    ''', [teacherId]);

    return rows.map((r) {
      return ClassModel.fromMap(
        r,
        teachersCount: (r['teacher_count'] as num?)?.toInt() ?? 0,
        studentsCount: (r['student_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  Future<bool> isTeacherAssignedToClass(int teacherId, int classId) async {
    final db = await _db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('''
        SELECT COUNT(*) FROM ${DatabaseSchema.tableClassTeachers}
        WHERE teacher_id = ? AND class_id = ?
      ''', [teacherId, classId]),
    );
    return (count ?? 0) > 0;
  }

  Future<bool> isStudentEnrolledInClass(int studentId, int classId) async {
    final db = await _db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('''
        SELECT COUNT(*) FROM ${DatabaseSchema.tableClassStudents}
        WHERE student_id = ? AND class_id = ?
      ''', [studentId, classId]),
    );
    return (count ?? 0) > 0;
  }

  Future<List<int>> getStudentIdsForClass(int classId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableClassStudents,
      columns: ['student_id'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    return rows.map((r) => r['student_id'] as int).toList();
  }

  Future<List<int>> getTeacherIdsForClass(int classId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableClassTeachers,
      columns: ['teacher_id'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    return rows.map((r) => r['teacher_id'] as int).toList();
  }

  Future<void> assignTeacherToClass(int classId, int teacherId) async {
    final db = await _db;
    await db.insert(
      DatabaseSchema.tableClassTeachers,
      {'class_id': classId, 'teacher_id': teacherId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeTeacherFromClass(int classId, int teacherId) async {
    final db = await _db;
    final currentTeachers = await getTeacherIdsForClass(classId);
    if (currentTeachers.length <= 1 && currentTeachers.contains(teacherId)) {
      throw StateError('A class must have at least one teacher assigned');
    }
    await db.delete(
      DatabaseSchema.tableClassTeachers,
      where: 'class_id = ? AND teacher_id = ?',
      whereArgs: [classId, teacherId],
    );
  }

  Future<void> assignStudentToClass(int classId, int studentId) async {
    final db = await _db;
    await db.insert(
      DatabaseSchema.tableClassStudents,
      {'class_id': classId, 'student_id': studentId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeStudentFromClass(int classId, int studentId) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.tableClassStudents,
      where: 'class_id = ? AND student_id = ?',
      whereArgs: [classId, studentId],
    );
  }

  Future<void> deleteClass(int classId) async {
    final db = await _db;
    final sessionsCount = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM ${DatabaseSchema.tableAttendanceSessions} WHERE class_id = ?',
        [classId],
      ),
    );
    if ((sessionsCount ?? 0) > 0) {
      throw StateError('Cannot delete class with existing attendance sessions');
    }
    await db.delete(
      DatabaseSchema.tableClasses,
      where: 'id = ?',
      whereArgs: [classId],
    );
  }
}
