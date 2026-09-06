import 'dart:convert';
import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/database/repositories/attendance_record_repository.dart';
import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/services/attendance_export_service.dart';
import 'package:face_att/services/attendance_service.dart';
import 'package:face_att/services/teacher_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late AppDatabase dbManager;
  late TeacherRepository teacherRepo;
  late StudentRepository studentRepo;
  late ClassRepository classRepo;
  late AttendanceSessionRepository sessionRepo;
  late AttendanceRecordRepository recordRepo;
  late AttendanceService attendanceService;
  late AttendanceExportService exportService;

  setUp(() async {
    dbManager = AppDatabase.instance;
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseSchema.version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          for (final query in DatabaseSchema.createTablesQueries) {
            await db.execute(query);
          }
        },
      ),
    );
    dbManager.setDatabaseForTesting(db);

    teacherRepo = TeacherRepository(dbManager);
    studentRepo = StudentRepository(dbManager);
    classRepo = ClassRepository(dbManager);
    sessionRepo = AttendanceSessionRepository(dbManager);
    recordRepo = AttendanceRecordRepository(dbManager);

    attendanceService = AttendanceService(
      sessionRepo: sessionRepo,
      recordRepo: recordRepo,
      classRepo: classRepo,
      studentRepo: studentRepo,
      teacherRepo: teacherRepo,
    );

    exportService = AttendanceExportService(
      sessionRepo: sessionRepo,
      recordRepo: recordRepo,
      classRepo: classRepo,
      teacherRepo: teacherRepo,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('JSON Export contains entire class, exact schema, and valid formatting', () async {
    // 1. Setup entities
    final teacher = await teacherRepo.createTeacher(
      username: 'teacher',
      passwordHash: TeacherAuthService.hashPassword('password'),
      displayName: 'Teacher',
    );

    final arun = await studentRepo.createStudent(
      registerNumber: '23BRS1001',
      name: 'Arun Kumar',
      email: 'arun@example.com',
      phone: '9876543210',
    );
    final priya = await studentRepo.createStudent(
      registerNumber: '23BRS1002',
      name: 'Priya Sharma',
      email: 'priya@example.com',
      phone: '9876543211',
    );
    final rahul = await studentRepo.createStudent(
      registerNumber: '23BRS1003',
      name: 'Rahul Kumar',
      email: 'rahul@example.com',
      phone: '9876543212',
    );

    final classA = await classRepo.createClass(
      name: 'B.Tech CSE - Section A',
      teacherIds: [teacher.id!],
      studentIds: [arun.id!, priya.id!, rahul.id!],
    );

    // 2. Start session
    final session = await attendanceService.startOrResumeSession(
      classId: classA.id!,
      teacherId: teacher.id!,
      attendanceDate: '2026-09-06',
    );

    // 3. Mark Arun and Rahul present, leave Priya absent
    await attendanceService.markStudentPresent(
      sessionId: session.id!,
      studentId: arun.id!,
    );
    await attendanceService.markStudentPresent(
      sessionId: session.id!,
      studentId: rahul.id!,
    );

    // 4. Complete session
    await attendanceService.completeSession(session.id!);

    // 5. Generate export map and JSON string
    final jsonString = await exportService.exportSessionAsJsonString(session.id!);
    expect(jsonString, isNotEmpty);

    // 6. Verify independent parseability
    final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
    expect(parsed.containsKey('attendance'), isTrue);
    expect(parsed.containsKey('students'), isTrue);

    final attendanceObj = parsed['attendance'] as Map<String, dynamic>;
    expect(attendanceObj['session_id'], equals(session.id));
    expect(attendanceObj['date'], equals('2026-09-06'));
    expect(attendanceObj['started_at'], isNotNull);
    expect(attendanceObj['ended_at'], isNotNull);

    final teacherObj = attendanceObj['teacher'] as Map<String, dynamic>;
    expect(teacherObj['id'], equals(teacher.id));
    expect(teacherObj['username'], equals('teacher'));
    expect(teacherObj['name'], equals('Teacher'));

    final classObj = attendanceObj['class'] as Map<String, dynamic>;
    expect(classObj['id'], equals(classA.id));
    expect(classObj['name'], equals('B.Tech CSE - Section A'));

    // 7. Verify students array contains ALL 3 students
    final studentsList = parsed['students'] as List<dynamic>;
    expect(studentsList.length, equals(3));

    // Arun -> present with timestamp
    final arunJson = studentsList.firstWhere((s) => s['register_number'] == '23BRS1001');
    expect(arunJson['name'], equals('Arun Kumar'));
    expect(arunJson['email'], equals('arun@example.com'));
    expect(arunJson['phone'], equals('9876543210'));
    expect(arunJson['status'], equals('present'));
    expect(arunJson['attendance_time'], isNotNull);
    expect(DateTime.tryParse(arunJson['attendance_time']), isNotNull);

    // Priya -> absent with null timestamp
    final priyaJson = studentsList.firstWhere((s) => s['register_number'] == '23BRS1002');
    expect(priyaJson['name'], equals('Priya Sharma'));
    expect(priyaJson['email'], equals('priya@example.com'));
    expect(priyaJson['phone'], equals('9876543211'));
    expect(priyaJson['status'], equals('absent'));
    expect(priyaJson['attendance_time'], isNull);

    // Rahul -> present with timestamp
    final rahulJson = studentsList.firstWhere((s) => s['register_number'] == '23BRS1003');
    expect(rahulJson['name'], equals('Rahul Kumar'));
    expect(rahulJson['status'], equals('present'));
    expect(rahulJson['attendance_time'], isNotNull);

    // 8. Verify filename formatting
    final filename = AttendanceExportService.generateFilename(
      className: classA.name,
      attendanceDate: '2026-09-06',
      sessionId: session.id!,
    );
    expect(filename, equals('attendance_b_tech_cse_section_a_2026-09-06_session_${session.id}.json'));
  });
}
