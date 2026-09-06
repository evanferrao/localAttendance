import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:sqflite/sqflite.dart';

class StudentRepository {
  final AppDatabase _dbManager;
  StudentRepository([AppDatabase? dbManager]) : _dbManager = dbManager ?? AppDatabase.instance;

  Future<Database> get _db => _dbManager.database;

  bool _isFaceEnrolled(String? studentId, String registerNumber) {
    // Check if Hive has a user enrolled under register_number or id
    final userByReg = LocalDB.getUser(registerNumber);
    if (userByReg != null && userByReg.array != null && userByReg.array!.length == 512) {
      return true;
    }
    if (studentId != null) {
      final userById = LocalDB.getUser(studentId);
      if (userById != null && userById.array != null && userById.array!.length == 512) {
        return true;
      }
    }
    return false;
  }

  Future<Student> createStudent({
    required String registerNumber,
    required String name,
    required String email,
    required String phone,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert(
      DatabaseSchema.tableStudents,
      {
        'register_number': registerNumber.trim(),
        'name': name.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final enrolled = _isFaceEnrolled(id.toString(), registerNumber.trim());
    return Student(
      id: id,
      registerNumber: registerNumber.trim(),
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
      final enrolled = _isFaceEnrolled(s.id?.toString(), s.registerNumber);
      return s.copyWith(hasFaceEnrolled: enrolled);
    }).toList();
  }

  Future<Student?> getStudentById(int id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableStudents,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final s = Student.fromMap(rows.first);
    final enrolled = _isFaceEnrolled(s.id?.toString(), s.registerNumber);
    return s.copyWith(hasFaceEnrolled: enrolled);
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
    final enrolled = _isFaceEnrolled(s.id?.toString(), s.registerNumber);
    return s.copyWith(hasFaceEnrolled: enrolled);
  }

  Future<List<Student>> getStudentsForClass(int classId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT s.* FROM ${DatabaseSchema.tableStudents} s
      INNER JOIN ${DatabaseSchema.tableClassStudents} cs ON s.id = cs.student_id
      WHERE cs.class_id = ?
      ORDER BY s.register_number ASC
    ''', [classId]);
    return rows.map((r) {
      final s = Student.fromMap(r);
      final enrolled = _isFaceEnrolled(s.id?.toString(), s.registerNumber);
      return s.copyWith(hasFaceEnrolled: enrolled);
    }).toList();
  }

  Future<int> updateStudent(Student student) async {
    final db = await _db;
    return await db.update(
      DatabaseSchema.tableStudents,
      student.toMap(),
      where: 'id = ?',
      whereArgs: [student.id],
    );
  }

  Future<int> deleteStudent(int id) async {
    final db = await _db;
    return await db.delete(
      DatabaseSchema.tableStudents,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
