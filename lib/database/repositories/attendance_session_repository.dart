import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/models/attendance_session.dart';
import 'package:sqflite/sqflite.dart';

class AttendanceSessionRepository {
  final AppDatabase _dbManager;
  AttendanceSessionRepository([AppDatabase? dbManager])
      : _dbManager = dbManager ?? AppDatabase.instance;

  Future<Database> get _db => _dbManager.database;

  Future<AttendanceSession> createSession({
    required int classId,
    required int teacherId,
    required String attendanceDate,
    required String startedAt,
  }) async {
    final db = await _db;
    final id = await db.insert(
      DatabaseSchema.tableAttendanceSessions,
      {
        'class_id': classId,
        'teacher_id': teacherId,
        'attendance_date': attendanceDate,
        'started_at': startedAt,
        'ended_at': null,
        'status': 'active',
      },
    );

    return (await getSessionById(id))!;
  }

  Future<AttendanceSession?> getActiveSessionForClassAndDate(int classId, String date) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT 
        s.*,
        c.name AS class_name,
        t.display_name AS teacher_name,
        t.username AS teacher_username,
        (SELECT COUNT(*) FROM ${DatabaseSchema.tableAttendanceRecords} ar WHERE ar.session_id = s.id AND ar.status = 'present') AS present_count,
        (SELECT COUNT(*) FROM ${DatabaseSchema.tableAttendanceRecords} ar WHERE ar.session_id = s.id) AS total_count
      FROM ${DatabaseSchema.tableAttendanceSessions} s
      INNER JOIN ${DatabaseSchema.tableClasses} c ON s.class_id = c.id
      INNER JOIN ${DatabaseSchema.tableTeachers} t ON s.teacher_id = t.id
      WHERE s.class_id = ? AND s.attendance_date = ? AND s.status = 'active'
      ORDER BY s.id DESC
      LIMIT 1
    ''', [classId, date]);

    if (rows.isEmpty) return null;
    return AttendanceSession.fromMap(rows.first);
  }

  Future<AttendanceSession?> getSessionById(int sessionId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT 
        s.*,
        c.name AS class_name,
        t.display_name AS teacher_name,
        t.username AS teacher_username,
        (SELECT COUNT(*) FROM ${DatabaseSchema.tableAttendanceRecords} ar WHERE ar.session_id = s.id AND ar.status = 'present') AS present_count,
        (SELECT COUNT(*) FROM ${DatabaseSchema.tableAttendanceRecords} ar WHERE ar.session_id = s.id) AS total_count
      FROM ${DatabaseSchema.tableAttendanceSessions} s
      INNER JOIN ${DatabaseSchema.tableClasses} c ON s.class_id = c.id
      INNER JOIN ${DatabaseSchema.tableTeachers} t ON s.teacher_id = t.id
      WHERE s.id = ?
      LIMIT 1
    ''', [sessionId]);

    if (rows.isEmpty) return null;
    return AttendanceSession.fromMap(rows.first);
  }

  Future<List<AttendanceSession>> getAllSessions() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT 
        s.*,
        c.name AS class_name,
        t.display_name AS teacher_name,
        t.username AS teacher_username,
        (SELECT COUNT(*) FROM ${DatabaseSchema.tableAttendanceRecords} ar WHERE ar.session_id = s.id AND ar.status = 'present') AS present_count,
        (SELECT COUNT(*) FROM ${DatabaseSchema.tableAttendanceRecords} ar WHERE ar.session_id = s.id) AS total_count
      FROM ${DatabaseSchema.tableAttendanceSessions} s
      INNER JOIN ${DatabaseSchema.tableClasses} c ON s.class_id = c.id
      INNER JOIN ${DatabaseSchema.tableTeachers} t ON s.teacher_id = t.id
      ORDER BY s.attendance_date DESC, s.started_at DESC
    ''');

    return rows.map((r) => AttendanceSession.fromMap(r)).toList();
  }

  Future<List<AttendanceSession>> getSessionsForClass(int classId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT 
        s.*,
        c.name AS class_name,
        t.display_name AS teacher_name,
        t.username AS teacher_username,
        (SELECT COUNT(*) FROM ${DatabaseSchema.tableAttendanceRecords} ar WHERE ar.session_id = s.id AND ar.status = 'present') AS present_count,
        (SELECT COUNT(*) FROM ${DatabaseSchema.tableAttendanceRecords} ar WHERE ar.session_id = s.id) AS total_count
      FROM ${DatabaseSchema.tableAttendanceSessions} s
      INNER JOIN ${DatabaseSchema.tableClasses} c ON s.class_id = c.id
      INNER JOIN ${DatabaseSchema.tableTeachers} t ON s.teacher_id = t.id
      WHERE s.class_id = ?
      ORDER BY s.attendance_date DESC, s.started_at DESC
    ''', [classId]);

    return rows.map((r) => AttendanceSession.fromMap(r)).toList();
  }

  Future<void> completeSession(int sessionId, String endedAt) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableAttendanceSessions,
      {
        'ended_at': endedAt,
        'status': 'completed',
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> deleteSession(int sessionId) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.tableAttendanceSessions,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
}
