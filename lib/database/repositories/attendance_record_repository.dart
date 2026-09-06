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
        if (student.id == null) continue;
        await txn.insert(
          DatabaseSchema.tableAttendanceRecords,
          {
            'session_id': sessionId,
            'student_id': student.id,
            'status': 'absent',
            'attendance_time': null,
            'student_register_number': student.registerNumber,
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
    required int studentId,
    required String attendanceTime,
  }) async {
    final db = await _db;
    final updatedCount = await db.update(
      DatabaseSchema.tableAttendanceRecords,
      {
        'status': 'present',
        'attendance_time': attendanceTime,
      },
      where: 'session_id = ? AND student_id = ? AND status != ?',
      whereArgs: [sessionId, studentId, 'present'],
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

  Future<AttendanceRecord?> getRecord(int sessionId, int studentId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableAttendanceRecords,
      where: 'session_id = ? AND student_id = ?',
      whereArgs: [sessionId, studentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceRecord.fromMap(rows.first);
  }

  Future<Set<int>> getPresentStudentIds(int sessionId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableAttendanceRecords,
      columns: ['student_id'],
      where: 'session_id = ? AND status = ?',
      whereArgs: [sessionId, 'present'],
    );
    return rows.map((r) => r['student_id'] as int).toSet();
  }
}
