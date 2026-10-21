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
    List<String> studentRegisterNumbers = const [],
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Class name cannot be empty');
    }
    final uniqueTeacherIds = teacherIds.toSet().toList();
    if (uniqueTeacherIds.isEmpty) {
      throw ArgumentError('A class must have at least one teacher assigned');
    }
    final uniqueStudentRegNos = studentRegisterNumbers.map((r) => r.trim()).toSet().toList();

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
      for (final reg in uniqueStudentRegNos) {
        await txn.insert(
          DatabaseSchema.tableClassStudents,
          {
            'class_id': classId,
            'register_number': reg,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      return ClassModel(
        id: classId,
        name: trimmedName,
        createdAt: now,
        teacherIds: uniqueTeacherIds,
        studentRegisterNumbers: uniqueStudentRegNos,
        teachersCount: uniqueTeacherIds.length,
        studentsCount: uniqueStudentRegNos.length,
      );
    });
  }

  Future<List<ClassModel>> getAllClasses() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT 
        c.*,
        COUNT(DISTINCT ct.teacher_id) AS teacher_count,
        COUNT(DISTINCT cs.register_number) AS student_count
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
      columns: ['register_number'],
      where: 'class_id = ?',
      whereArgs: [id],
    );
    final studentRegisterNumbers = studentRows.map((r) => r['register_number'] as String).toList();

    return ClassModel.fromMap(
      classRows.first,
      teacherIds: teacherIds,
      studentRegisterNumbers: studentRegisterNumbers,
      teachersCount: teacherIds.length,
      studentsCount: studentRegisterNumbers.length,
    );
  }

  Future<List<ClassModel>> getClassesForTeacher(int teacherId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT 
        c.*,
        COUNT(DISTINCT ct2.teacher_id) AS teacher_count,
        COUNT(DISTINCT cs.register_number) AS student_count
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

  Future<bool> isStudentEnrolledInClass(String registerNumber, int classId) async {
    final db = await _db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('''
        SELECT COUNT(*) FROM ${DatabaseSchema.tableClassStudents}
        WHERE LOWER(register_number) = LOWER(?) AND class_id = ?
      ''', [registerNumber.trim(), classId]),
    );
    return (count ?? 0) > 0;
  }

  Future<List<String>> getStudentRegisterNumbersForClass(int classId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableClassStudents,
      columns: ['register_number'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    return rows.map((r) => r['register_number'] as String).toList();
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

  Future<void> assignStudentToClass(int classId, String registerNumber) async {
    final db = await _db;
    await db.insert(
      DatabaseSchema.tableClassStudents,
      {'class_id': classId, 'register_number': registerNumber.trim()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> assignStudentsToClass(int classId, List<String> registerNumbers) async {
    final uniqueRegs = registerNumbers.map((r) => r.trim()).where((r) => r.isNotEmpty).toSet();
    if (uniqueRegs.isEmpty) return;

    final db = await _db;
    final batch = db.batch();
    for (final reg in uniqueRegs) {
      batch.insert(
        DatabaseSchema.tableClassStudents,
        {'class_id': classId, 'register_number': reg},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeStudentFromClass(int classId, String registerNumber) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.tableClassStudents,
      where: 'class_id = ? AND LOWER(register_number) = LOWER(?)',
      whereArgs: [classId, registerNumber.trim()],
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

