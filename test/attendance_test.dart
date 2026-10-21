import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/database/repositories/attendance_record_repository.dart';
import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/class_model.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/models/teacher.dart';
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

  late Teacher authorizedTeacher;
  late Teacher unauthorizedTeacher;
  late Student studentArun;
  late Student studentPriya;
  late Student studentRahul;
  late Student outsideStudent;
  late ClassModel testClass;

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

    // Create seed entities
    final hash = TeacherAuthService.hashPassword('pass');
    authorizedTeacher = await teacherRepo.createTeacher(
      username: 'teacher_assigned',
      passwordHash: hash,
      displayName: 'Assigned Teacher',
    );
    unauthorizedTeacher = await teacherRepo.createTeacher(
      username: 'teacher_unassigned',
      passwordHash: hash,
      displayName: 'Unassigned Teacher',
    );

    studentArun = await studentRepo.createStudent(
      registerNumber: '23BRS1001',
      name: 'Arun Kumar',
      email: 'arun@example.com',
      phone: '9876543210',
    );
    studentPriya = await studentRepo.createStudent(
      registerNumber: '23BRS1002',
      name: 'Priya Sharma',
      email: 'priya@example.com',
      phone: '9876543211',
    );
    studentRahul = await studentRepo.createStudent(
      registerNumber: '23BRS1003',
      name: 'Rahul Kumar',
      email: 'rahul@example.com',
      phone: '9876543212',
    );
    outsideStudent = await studentRepo.createStudent(
      registerNumber: '23BRS9999',
      name: 'Outside Student',
      email: 'outside@example.com',
      phone: '9876543299',
    );

    testClass = await classRepo.createClass(
      name: 'B.Tech CSE - Section A',
      teacherIds: [authorizedTeacher.id!],
      studentRegisterNumbers: [studentArun.registerNumber, studentPriya.registerNumber, studentRahul.registerNumber],
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Attendance Session & Authorization Tests', () {
    test('Reject unauthorized teacher attempting to take attendance for class', () async {
      expect(
        () async => await attendanceService.startOrResumeSession(
          classId: testClass.id!,
          teacherId: unauthorizedTeacher.id!,
          attendanceDate: '2026-09-06',
        ),
        throwsStateError,
      );
    });

    test('Authorized teacher starts session and all class students are initialized as absent', () async {
      final session = await attendanceService.startOrResumeSession(
        classId: testClass.id!,
        teacherId: authorizedTeacher.id!,
        attendanceDate: '2026-09-06',
      );

      expect(session.id, isNotNull);
      expect(session.status, equals('active'));
      expect(session.attendanceDate, equals('2026-09-06'));

      final summary = await attendanceService.getSessionSummary(session.id!);
      expect(summary.totalCount, equals(3));
      expect(summary.presentCount, equals(0));
      expect(summary.absentCount, equals(3));

      for (final absent in summary.absentRecords) {
        expect(absent.attendanceTime, isNull);
        expect(absent.status, equals('absent'));
        expect(absent.studentRegisterNumber, isNotEmpty);
      }
    });

    test('Starting session when active session exists resumes the existing session', () async {
      final session1 = await attendanceService.startOrResumeSession(
        classId: testClass.id!,
        teacherId: authorizedTeacher.id!,
        attendanceDate: '2026-09-06',
      );

      // Mark Arun present in session 1
      await attendanceService.markStudentPresent(
        sessionId: session1.id!,
        registerNumber: studentArun.registerNumber,
      );

      // Call startOrResumeSession again for same class and date
      final session2 = await attendanceService.startOrResumeSession(
        classId: testClass.id!,
        teacherId: authorizedTeacher.id!,
        attendanceDate: '2026-09-06',
      );

      expect(session2.id, equals(session1.id));
      final summary = await attendanceService.getSessionSummary(session2.id!);
      expect(summary.presentCount, equals(1));
      expect(summary.absentCount, equals(2));
    });
  });

  group('Attendance Marking, Absent Handling & Duplication Protection', () {
    test('Marking attendance marks student present and stores ISO-8601 timestamp', () async {
      final session = await attendanceService.startOrResumeSession(
        classId: testClass.id!,
        teacherId: authorizedTeacher.id!,
        attendanceDate: '2026-09-06',
      );

      final markResult = await attendanceService.markStudentPresent(
        sessionId: session.id!,
        registerNumber: studentArun.registerNumber,
      );
      expect(markResult, equals(MarkAttendanceResult.markedPresent));

      final record = await recordRepo.getRecord(session.id!, studentArun.registerNumber);
      expect(record, isNotNull);
      expect(record!.status, equals('present'));
      expect(record.attendanceTime, isNotNull);
      expect(DateTime.tryParse(record.attendanceTime!), isNotNull);
    });

    test('Recognizing the same student repeatedly does not create duplicate attendance', () async {
      final session = await attendanceService.startOrResumeSession(
        classId: testClass.id!,
        teacherId: authorizedTeacher.id!,
        attendanceDate: '2026-09-06',
      );

      final firstMark = await attendanceService.markStudentPresent(
        sessionId: session.id!,
        registerNumber: studentArun.registerNumber,
      );
      expect(firstMark, equals(MarkAttendanceResult.markedPresent));

      // Attempt second mark
      final secondMark = await attendanceService.markStudentPresent(
        sessionId: session.id!,
        registerNumber: studentArun.registerNumber,
      );
      expect(secondMark, equals(MarkAttendanceResult.alreadyPresent));

      final records = await recordRepo.getRecordsForSession(session.id!);
      expect(records.length, equals(3));
      final arunRecords = records.where((r) => r.registerNumber == studentArun.registerNumber).toList();
      expect(arunRecords.length, equals(1));
    });

    test('Reject marking attendance for student not enrolled in selected class', () async {
      final session = await attendanceService.startOrResumeSession(
        classId: testClass.id!,
        teacherId: authorizedTeacher.id!,
        attendanceDate: '2026-09-06',
      );

      final markResult = await attendanceService.markStudentPresent(
        sessionId: session.id!,
        registerNumber: outsideStudent.registerNumber,
      );
      expect(markResult, equals(MarkAttendanceResult.studentNotInClass));

      final summary = await attendanceService.getSessionSummary(session.id!);
      expect(summary.presentCount, equals(0));
    });

    test('Absent students verification: Only Arun marked present -> Priya and Rahul remain absent with null timestamp', () async {
      final session = await attendanceService.startOrResumeSession(
        classId: testClass.id!,
        teacherId: authorizedTeacher.id!,
        attendanceDate: '2026-09-06',
      );

      // Only Arun is recognized
      await attendanceService.markStudentPresent(
        sessionId: session.id!,
        registerNumber: studentArun.registerNumber,
      );

      final completedSession = await attendanceService.completeSession(session.id!);
      expect(completedSession.isCompleted, isTrue);
      expect(completedSession.endedAt, isNotNull);

      final summary = await attendanceService.getSessionSummary(session.id!);
      expect(summary.totalCount, equals(3));
      expect(summary.presentCount, equals(1));
      expect(summary.absentCount, equals(2));

      // Verify Arun
      final arunRecord = summary.presentRecords.firstWhere((r) => r.registerNumber == studentArun.registerNumber);
      expect(arunRecord.status, equals('present'));
      expect(arunRecord.attendanceTime, isNotNull);

      // Verify Priya
      final priyaRecord = summary.absentRecords.firstWhere((r) => r.registerNumber == studentPriya.registerNumber);
      expect(priyaRecord.status, equals('absent'));
      expect(priyaRecord.attendanceTime, isNull);

      // Verify Rahul
      final rahulRecord = summary.absentRecords.firstWhere((r) => r.registerNumber == studentRahul.registerNumber);
      expect(rahulRecord.status, equals('absent'));
      expect(rahulRecord.attendanceTime, isNull);
    });
  });
}
