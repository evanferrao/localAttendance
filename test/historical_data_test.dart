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

  test('Historical Data Test: Removing student from class after session completion preserves historical report and JSON', () async {
    // 1. Setup Class A with Student 1 & Student 2
    final teacher = await teacherRepo.createTeacher(
      username: 'teacher',
      passwordHash: TeacherAuthService.hashPassword('password'),
      displayName: 'Teacher',
    );

    final student1 = await studentRepo.createStudent(
      registerNumber: '23BRS1001',
      name: 'Student One',
      email: 's1@example.com',
      phone: '1111111111',
    );
    final student2 = await studentRepo.createStudent(
      registerNumber: '23BRS1002',
      name: 'Student Two',
      email: 's2@example.com',
      phone: '2222222222',
    );

    final classA = await classRepo.createClass(
      name: 'Class A',
      teacherIds: [teacher.id!],
      studentRegisterNumbers: [student1.registerNumber, student2.registerNumber],
    );

    // 2. Start attendance session
    final session = await attendanceService.startOrResumeSession(
      classId: classA.id!,
      teacherId: teacher.id!,
      attendanceDate: '2026-09-06',
    );

    // 3. Mark Student 1 present; Student 2 remains absent
    await attendanceService.markStudentPresent(
      sessionId: session.id!,
      registerNumber: student1.registerNumber,
    );

    // 4. Complete session
    await attendanceService.completeSession(session.id!);

    // 5. Remove Student 2 from Class A
    await classRepo.removeStudentFromClass(classA.id!, student2.registerNumber);

    // Verify current class membership now only has Student 1
    final currentStudentsInClass = await classRepo.getStudentRegisterNumbersForClass(classA.id!);
    expect(currentStudentsInClass.length, equals(1));
    expect(currentStudentsInClass.contains(student2.registerNumber), isFalse);

    // 6. Open old attendance session
    final summary = await attendanceService.getSessionSummary(session.id!);
    expect(summary.totalCount, equals(2));
    expect(summary.presentCount, equals(1));
    expect(summary.absentCount, equals(1));

    final absentRecord = summary.absentRecords.firstWhere((r) => r.registerNumber == student2.registerNumber);
    expect(absentRecord.studentRegisterNumber, equals('23BRS1002'));
    expect(absentRecord.studentName, equals('Student Two'));
    expect(absentRecord.status, equals('absent'));

    // 7. Verify exported JSON still contains Student 2
    final jsonString = await exportService.exportSessionAsJsonString(session.id!);
    final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
    final studentsList = parsed['students'] as List<dynamic>;
    expect(studentsList.length, equals(2));

    final s2Json = studentsList.firstWhere((s) => s['register_number'] == '23BRS1002');
    expect(s2Json['name'], equals('Student Two'));
    expect(s2Json['status'], equals('absent'));
    expect(s2Json['attendance_time'], isNull);
  });
}
