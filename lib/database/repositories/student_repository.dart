import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:sqflite/sqflite.dart';

class StudentRepository {
  final AppDatabase _dbManager;
  StudentRepository([AppDatabase? dbManager]) : _dbManager = dbManager ?? AppDatabase.instance;

  Future<Database> get _db => _dbManager.database;

  bool _isFaceEnrolled(String registerNumber) {
    // Check if Hive has a user enrolled strictly under register_number as primary key
    final trimmedReg = registerNumber.trim();
    final userByReg = LocalDB.getUser(trimmedReg) ??
        LocalDB.getUser(trimmedReg.toUpperCase()) ??
        LocalDB.getUser(trimmedReg.toLowerCase());
    return userByReg != null && userByReg.array != null && userByReg.array!.length == 512;
  }

  Future<Student> createStudent({
    required String registerNumber,
    String name = '',
    String email = '',
    String phone = '',
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final regTrimmed = registerNumber.trim();
    await db.insert(
      DatabaseSchema.tableStudents,
      {
        'register_number': regTrimmed,
        'name': name.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final enrolled = _isFaceEnrolled(regTrimmed);
    return Student(
      registerNumber: regTrimmed,
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      createdAt: now,
      hasFaceEnrolled: enrolled,
    );
  }

  Future<List<Student>> getAllStudents() async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableStudents,
      orderBy: 'register_number ASC',
    );
    return rows.map((r) {
      final s = Student.fromMap(r);
      final enrolled = _isFaceEnrolled(s.registerNumber);
      return s.copyWith(hasFaceEnrolled: enrolled);
    }).toList();
  }

  Future<Student?> getStudentByRegisterNumber(String registerNumber) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableStudents,
      where: 'LOWER(register_number) = LOWER(?)',
      whereArgs: [registerNumber.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final s = Student.fromMap(rows.first);
    final enrolled = _isFaceEnrolled(s.registerNumber);
    return s.copyWith(hasFaceEnrolled: enrolled);
  }

  Future<List<Student>> getStudentsForClass(int classId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT s.* FROM ${DatabaseSchema.tableStudents} s
      INNER JOIN ${DatabaseSchema.tableClassStudents} cs ON s.register_number = cs.register_number
      WHERE cs.class_id = ?
      ORDER BY s.register_number ASC
    ''', [classId]);
    return rows.map((r) {
      final s = Student.fromMap(r);
      final enrolled = _isFaceEnrolled(s.registerNumber);
      return s.copyWith(hasFaceEnrolled: enrolled);
    }).toList();
  }

  Future<int> updateStudent(Student student) async {
    final db = await _db;
    return await db.update(
      DatabaseSchema.tableStudents,
      student.toMap(),
      where: 'register_number = ?',
      whereArgs: [student.registerNumber],
    );
  }

  Future<int> deleteStudent(String registerNumber) async {
    final db = await _db;
    return await db.delete(
      DatabaseSchema.tableStudents,
      where: 'register_number = ?',
      whereArgs: [registerNumber.trim()],
    );
  }
}

