import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/models/attendance_record.dart';
import 'package:face_att/models/student.dart';
import 'package:sqflite/sqflite.dart';

class AttendanceRecordRepository {
  final AppDatabase _dbManager;
  AttendanceRecordRepository([AppDatabase? dbManager])
      : _dbManager = dbManager ?? AppDatabase.instance;

  Future<Database> get _db => _dbManager.database;

  /// Approach A: Initialize absent records for all class students in a transaction,
  /// preserving historical snapshot details of the students at session time.
  Future<void> initializeRecordsForSession({
    required int sessionId,
    required List<Student> students,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final student in students) {
        if (student.registerNumber.trim().isEmpty) continue;
        await txn.insert(
          DatabaseSchema.tableAttendanceRecords,
          {
            'session_id': sessionId,
            'register_number': student.registerNumber.trim(),
            'status': 'absent',
            'attendance_time': null,
            'student_name': student.name,
            'student_email': student.email,
            'student_phone': student.phone,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Mark student present. Returns true if updated from absent to present.
  Future<bool> markStudentPresent({
    required int sessionId,
    required String registerNumber,
    required String attendanceTime,
  }) async {
    final db = await _db;
    final updatedCount = await db.update(
      DatabaseSchema.tableAttendanceRecords,
      {
        'status': 'present',
        'attendance_time': attendanceTime,
      },
      where: 'session_id = ? AND LOWER(register_number) = LOWER(?) AND status != ?',
      whereArgs: [sessionId, registerNumber.trim(), 'present'],
    );
    return updatedCount > 0;
  }

  Future<List<AttendanceRecord>> getRecordsForSession(int sessionId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableAttendanceRecords,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'status DESC, student_name ASC',
    );
    return rows.map((r) => AttendanceRecord.fromMap(r)).toList();
  }

  Future<AttendanceRecord?> getRecord(int sessionId, String registerNumber) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableAttendanceRecords,
      where: 'session_id = ? AND LOWER(register_number) = LOWER(?)',
      whereArgs: [sessionId, registerNumber.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceRecord.fromMap(rows.first);
  }

  Future<Set<String>> getPresentRegisterNumbers(int sessionId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableAttendanceRecords,
      columns: ['register_number'],
      where: 'session_id = ? AND status = ?',
      whereArgs: [sessionId, 'present'],
    );
    return rows.map((r) => r['register_number'] as String).toSet();
  }
}

