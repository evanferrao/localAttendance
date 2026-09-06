import 'package:face_att/database/repositories/attendance_record_repository.dart';
import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/attendance_record.dart';
import 'package:face_att/models/attendance_session.dart';

enum MarkAttendanceResult {
  markedPresent,
  alreadyPresent,
  studentNotInClass,
  sessionNotActive,
}

class AttendanceSummary {
  final AttendanceSession session;
  final List<AttendanceRecord> presentRecords;
  final List<AttendanceRecord> absentRecords;

  int get totalCount => presentRecords.length + absentRecords.length;
  int get presentCount => presentRecords.length;
  int get absentCount => absentRecords.length;

  const AttendanceSummary({
    required this.session,
    required this.presentRecords,
    required this.absentRecords,
  });
}

class AttendanceService {
  final AttendanceSessionRepository _sessionRepo;
  final AttendanceRecordRepository _recordRepo;
  final ClassRepository _classRepo;
  final StudentRepository _studentRepo;
  final TeacherRepository _teacherRepo;

  AttendanceService({
    AttendanceSessionRepository? sessionRepo,
    AttendanceRecordRepository? recordRepo,
    ClassRepository? classRepo,
    StudentRepository? studentRepo,
    TeacherRepository? teacherRepo,
  })  : _sessionRepo = sessionRepo ?? AttendanceSessionRepository(),
        _recordRepo = recordRepo ?? AttendanceRecordRepository(),
        _classRepo = classRepo ?? ClassRepository(),
        _studentRepo = studentRepo ?? StudentRepository(),
        _teacherRepo = teacherRepo ?? TeacherRepository();

  /// Start a new attendance session or resume existing active session.
  /// Validates that the teacher is authorized for the class and initializes Approach A absent records.
  Future<AttendanceSession> startOrResumeSession({
    required int classId,
    required int teacherId,
    required String attendanceDate,
  }) async {
    // 1. Verify teacher exists and is assigned to class
    final teacher = await _teacherRepo.getTeacherById(teacherId);
    if (teacher == null) {
      throw StateError('Teacher (ID: $teacherId) does not exist');
    }
    final isAssigned = await _classRepo.isTeacherAssignedToClass(teacherId, classId);
    if (!isAssigned) {
      throw StateError('Teacher (ID: $teacherId) is not assigned to Class (ID: $classId)');
    }

    // 2. Check for active session to resume
    final activeSession = await _sessionRepo.getActiveSessionForClassAndDate(classId, attendanceDate);
    if (activeSession != null) {
      // Ensure any newly added class students get initialized
      final classStudents = await _studentRepo.getStudentsForClass(classId);
      await _recordRepo.initializeRecordsForSession(
        sessionId: activeSession.id!,
        students: classStudents,
      );
      return activeSession;
    }

    // 3. Create new session
    final now = DateTime.now().toIso8601String();
    final newSession = await _sessionRepo.createSession(
      classId: classId,
      teacherId: teacherId,
      attendanceDate: attendanceDate,
      startedAt: now,
    );

    // 4. Approach A: Initialize attendance records for every student in class as absent with historical snapshot
    final classStudents = await _studentRepo.getStudentsForClass(classId);
    await _recordRepo.initializeRecordsForSession(
      sessionId: newSession.id!,
      students: classStudents,
    );

    return (await _sessionRepo.getSessionById(newSession.id!))!;
  }

  /// Mark student present.
  /// Enforces class membership and prevents duplicate attendance writes.
  Future<MarkAttendanceResult> markStudentPresent({
    required int sessionId,
    required int studentId,
  }) async {
    final session = await _sessionRepo.getSessionById(sessionId);
    if (session == null || !session.isActive) {
      return MarkAttendanceResult.sessionNotActive;
    }

    // Check if student belongs to the class
    final isEnrolled = await _classRepo.isStudentEnrolledInClass(studentId, session.classId);
    if (!isEnrolled) {
      return MarkAttendanceResult.studentNotInClass;
    }

    final now = DateTime.now().toIso8601String();
    final updated = await _recordRepo.markStudentPresent(
      sessionId: sessionId,
      studentId: studentId,
      attendanceTime: now,
    );

    if (updated) {
      return MarkAttendanceResult.markedPresent;
    } else {
      return MarkAttendanceResult.alreadyPresent;
    }
  }

  /// Complete active session
  Future<AttendanceSession> completeSession(int sessionId) async {
    final now = DateTime.now().toIso8601String();
    await _sessionRepo.completeSession(sessionId, now);
    final completed = await _sessionRepo.getSessionById(sessionId);
    if (completed == null) {
      throw StateError('Session not found: $sessionId');
    }
    return completed;
  }

  /// Fetch full summary of attendance session with all present and absent records
  Future<AttendanceSummary> getSessionSummary(int sessionId) async {
    final session = await _sessionRepo.getSessionById(sessionId);
    if (session == null) {
      throw StateError('Attendance session $sessionId not found');
    }

    final records = await _recordRepo.getRecordsForSession(sessionId);
    final present = records.where((r) => r.isPresent).toList();
    final absent = records.where((r) => r.isAbsent).toList();

    return AttendanceSummary(
      session: session,
      presentRecords: present,
      absentRecords: absent,
    );
  }
}
