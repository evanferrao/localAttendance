import 'dart:convert';
import 'dart:io';
import 'package:face_att/database/repositories/attendance_record_repository.dart';
import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AttendanceExportService {
  final AttendanceSessionRepository _sessionRepo;
  final AttendanceRecordRepository _recordRepo;
  final ClassRepository _classRepo;
  final TeacherRepository _teacherRepo;

  AttendanceExportService({
    AttendanceSessionRepository? sessionRepo,
    AttendanceRecordRepository? recordRepo,
    ClassRepository? classRepo,
    TeacherRepository? teacherRepo,
  })  : _sessionRepo = sessionRepo ?? AttendanceSessionRepository(),
        _recordRepo = recordRepo ?? AttendanceRecordRepository(),
        _classRepo = classRepo ?? ClassRepository(),
        _teacherRepo = teacherRepo ?? TeacherRepository();

  /// Converts class name to a safe filename slug
  static String slugify(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Generates the canonical deterministic filename
  static String generateFilename({
    required String className,
    required String attendanceDate,
    required int sessionId,
  }) {
    final slug = slugify(className);
    return 'attendance_${slug}_${attendanceDate}_session_$sessionId.json';
  }

  /// Generates the Map structure representing the complete session attendance
  Future<Map<String, dynamic>> generateExportMap(int sessionId) async {
    final session = await _sessionRepo.getSessionById(sessionId);
    if (session == null) {
      throw StateError('Attendance session $sessionId not found');
    }

    final teacher = await _teacherRepo.getTeacherById(session.teacherId);
    final classModel = await _classRepo.getClassById(session.classId);
    final records = await _recordRepo.getRecordsForSession(sessionId);

    final teacherMap = {
      'id': session.teacherId,
      'username': teacher?.username ?? session.teacherUsername ?? 'unknown',
      'name': teacher?.displayName ?? session.teacherName ?? 'Teacher',
    };

    final classMap = {
      'id': session.classId,
      'name': classModel?.name ?? session.className ?? 'Unknown Class',
    };

    final studentsList = records.map((record) {
      return {
        'register_number': record.studentRegisterNumber,
        'name': record.studentName,
        'email': record.studentEmail,
        'phone': record.studentPhone,
        'status': record.status,
        'attendance_time': record.attendanceTime,
      };
    }).toList();

    return {
      'attendance': {
        'session_id': session.id,
        'teacher': teacherMap,
        'class': classMap,
        'date': session.attendanceDate,
        'started_at': session.startedAt,
        'ended_at': session.endedAt,
      },
      'students': studentsList,
    };
  }

  /// Exports the session to a formatted JSON string (2-space indentation)
  Future<String> exportSessionAsJsonString(int sessionId) async {
    final map = await generateExportMap(sessionId);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(map);
  }

  /// Exports the session and saves to a JSON file in the application document directory
  Future<File> exportSessionToFile(int sessionId, {String? customDir}) async {
    final session = await _sessionRepo.getSessionById(sessionId);
    if (session == null) {
      throw StateError('Attendance session $sessionId not found');
    }

    final className = session.className ?? 'class_${session.classId}';
    final filename = generateFilename(
      className: className,
      attendanceDate: session.attendanceDate,
      sessionId: session.id!,
    );

    String dirPath = customDir ?? '';
    if (dirPath.isEmpty) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        dirPath = docDir.path;
      } catch (_) {
        dirPath = Directory.current.path;
      }
    }

    final file = File(p.join(dirPath, filename));
    final jsonString = await exportSessionAsJsonString(sessionId);
    await file.writeAsString(jsonString);
    return file;
  }

  /// Export and share the JSON file via system share sheet
  Future<void> shareSessionJson(int sessionId) async {
    final file = await exportSessionToFile(sessionId);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Attendance Export - ${p.basename(file.path)}',
      ),
    );
  }
}

