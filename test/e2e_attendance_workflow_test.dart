import 'dart:convert';
import 'dart:io';
import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/database/repositories/attendance_record_repository.dart';
import 'package:face_att/database/repositories/attendance_session_repository.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/services/face_recognition/ml_service.dart';
import 'package:face_att/services/attendance_export_service.dart';
import 'package:face_att/services/attendance_service.dart';
import 'package:face_att/services/teacher_auth_service.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final tempDir = Directory.systemTemp.createTempSync('hive_test');
    Hive.init(tempDir.path);
    await HiveBoxes.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('Complete End-to-End Attendance Management & Recognition Workflow', () async {
    // 1. Fresh application database
    final dbManager = AppDatabase.instance;
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseSchema.version,
        onConfigure: (db) async => await db.execute('PRAGMA foreign_keys = ON;'),
        onCreate: (db, version) async {
          for (final query in DatabaseSchema.createTablesQueries) {
            await db.execute(query);
          }
          await AppDatabase.seedInitialDataIfNeeded(db);
        },
      ),
    );
    dbManager.setDatabaseForTesting(db);

    final teacherRepo = TeacherRepository(dbManager);
    final studentRepo = StudentRepository(dbManager);
    final classRepo = ClassRepository(dbManager);
    final sessionRepo = AttendanceSessionRepository(dbManager);
    final recordRepo = AttendanceRecordRepository(dbManager);
    final attendanceService = AttendanceService(
      sessionRepo: sessionRepo,
      recordRepo: recordRepo,
      classRepo: classRepo,
      studentRepo: studentRepo,
      teacherRepo: teacherRepo,
    );
    final exportService = AttendanceExportService(
      sessionRepo: sessionRepo,
      recordRepo: recordRepo,
      classRepo: classRepo,
      teacherRepo: teacherRepo,
    );

    // 2. Check fresh launch: classes is empty
    final initialClasses = await classRepo.getAllClasses();
    expect(initialClasses.isEmpty, isTrue);

    // 3. Verify seeded default teacher exists
    final defaultTeacher = await teacherRepo.getTeacherByUsername('teacher');
    expect(defaultTeacher, isNotNull);
    expect(TeacherAuthService.verifyPassword('password', defaultTeacher!.passwordHash), isTrue);

    // 4. Create Students and enroll face embeddings into Hive
    final studentPiyush = await studentRepo.createStudent(
      registerNumber: '23BRS1150',
      name: 'Piyush R Saini',
      email: 'piyush@example.com',
      phone: '9876543210',
    );
    final studentArun = await studentRepo.createStudent(
      registerNumber: '23BRS1001',
      name: 'Arun Kumar',
      email: 'arun@example.com',
      phone: '9876543211',
    );
    final studentPriya = await studentRepo.createStudent(
      registerNumber: '23BRS1002',
      name: 'Priya Sharma',
      email: 'priya@example.com',
      phone: '9876543212',
    );
    // Student without a name (name is optional in the app)
    final studentNameless = await studentRepo.createStudent(
      registerNumber: '23BRS1003',
      name: '',
      email: '',
      phone: '',
    );

    // Generate distinct synthetic 512D unit vectors for face recognition
    final mlService = MLService();
    final piyushEmbedding = mlService.l2Normalize(List.generate(512, (i) => i == 10 ? 1.0 : 0.0));
    final arunEmbedding = mlService.l2Normalize(List.generate(512, (i) => i == 20 ? 1.0 : 0.0));
    final priyaEmbedding = mlService.l2Normalize(List.generate(512, (i) => i == 30 ? 1.0 : 0.0));
    final namelessEmbedding = mlService.l2Normalize(List.generate(512, (i) => i == 50 ? 1.0 : 0.0));
    final unknownEmbedding = mlService.l2Normalize(List.generate(512, (i) => i == 99 ? 1.0 : 0.0));

    // Enroll into Hive (keying strictly by registerNumber)
    await LocalDB.saveUser(User(
      registerNumber: studentPiyush.registerNumber,
      name: studentPiyush.name,
      email: studentPiyush.email,
      phone: studentPiyush.phone,
      array: piyushEmbedding,
    ));
    await LocalDB.saveUser(User(
      registerNumber: studentArun.registerNumber,
      name: studentArun.name,
      email: studentArun.email,
      phone: studentArun.phone,
      array: arunEmbedding,
    ));
    await LocalDB.saveUser(User(
      registerNumber: studentPriya.registerNumber,
      name: studentPriya.name,
      email: studentPriya.email,
      phone: studentPriya.phone,
      array: priyaEmbedding,
    ));
    await LocalDB.saveUser(User(
      registerNumber: studentNameless.registerNumber,
      name: studentNameless.name,
      array: namelessEmbedding,
    ));

    // 5. Create Class containing Piyush, Arun, Priya, and Nameless
    final classA = await classRepo.createClass(
      name: 'B.Tech CSE - Section A',
      teacherIds: [defaultTeacher.id!],
      studentRegisterNumbers: [
        studentPiyush.registerNumber,
        studentArun.registerNumber,
        studentPriya.registerNumber,
        studentNameless.registerNumber,
      ],
    );
    expect(classA.id, isNotNull);
    expect(classA.studentsCount, equals(4));

    // Also create outside student not in Class A
    final outsideStudent = await studentRepo.createStudent(
      registerNumber: '23BRS9999',
      name: 'Outside Student',
      email: 'outside@example.com',
      phone: '9876543299',
    );
    final outsideEmbedding = mlService.l2Normalize(List.generate(512, (i) => i == 40 ? 1.0 : 0.0));
    await LocalDB.saveUser(User(
      registerNumber: outsideStudent.registerNumber,
      name: outsideStudent.name,
      array: outsideEmbedding,
    ));

    // 6. Teacher Login
    final loginSuccess = TeacherAuthService.verifyPassword('password', defaultTeacher.passwordHash);
    expect(loginSuccess, isTrue);

    // 7. Select Class assigned to teacher
    final teacherClasses = await classRepo.getClassesForTeacher(defaultTeacher.id!);
    expect(teacherClasses.length, equals(1));
    expect(teacherClasses.first.id, equals(classA.id));

    // 8. Select Date and Start Attendance Session
    const attendanceDate = '2026-09-06';
    final session = await attendanceService.startOrResumeSession(
      classId: classA.id!,
      teacherId: defaultTeacher.id!,
      attendanceDate: attendanceDate,
    );
    expect(session.id, isNotNull);
    expect(session.status, equals('active'));

    // 9. Initial state: All 4 class students are initialized as absent with historical snapshot
    var summary = await attendanceService.getSessionSummary(session.id!);
    expect(summary.totalCount, equals(4));
    expect(summary.presentCount, equals(0));
    expect(summary.absentCount, equals(4));

    // 10. ML Recognition for Piyush
    final recPiyush = mlService.recognizeFace(piyushEmbedding);
    expect(recPiyush.accepted, isTrue);
    expect(recPiyush.registerNumber, equals(studentPiyush.registerNumber));
    expect(recPiyush.score, greaterThanOrEqualTo(0.35));

    // Verify Piyush belongs to Class A and mark present
    final piyushStudent = await studentRepo.getStudentByRegisterNumber(recPiyush.registerNumber!);
    expect(piyushStudent, isNotNull);
    final isPiyushEnrolled = await classRepo.isStudentEnrolledInClass(piyushStudent!.registerNumber, classA.id!);
    expect(isPiyushEnrolled, isTrue);

    final markPiyush1 = await attendanceService.markStudentPresent(
      sessionId: session.id!,
      registerNumber: piyushStudent.registerNumber,
    );
    expect(markPiyush1, equals(MarkAttendanceResult.markedPresent));

    // 11. Repeated recognition of Piyush -> In-memory & DB duplicate protection
    final markPiyush2 = await attendanceService.markStudentPresent(
      sessionId: session.id!,
      registerNumber: piyushStudent.registerNumber,
    );
    expect(markPiyush2, equals(MarkAttendanceResult.alreadyPresent));

    // 12. ML Recognition of Outside Student (enrolled in DB, but NOT enrolled in Class A)
    final recOutside = mlService.recognizeFace(outsideEmbedding);
    expect(recOutside.accepted, isTrue);
    final outsideRecord = await studentRepo.getStudentByRegisterNumber(recOutside.registerNumber!);
    final isOutsideEnrolled = await classRepo.isStudentEnrolledInClass(outsideRecord!.registerNumber, classA.id!);
    expect(isOutsideEnrolled, isFalse);

    // Rejection of outside student
    final markOutside = await attendanceService.markStudentPresent(
      sessionId: session.id!,
      registerNumber: outsideRecord.registerNumber,
    );
    expect(markOutside, equals(MarkAttendanceResult.studentNotInClass));

    // 13. ML Recognition of Unknown Face
    final recUnknown = mlService.recognizeFace(unknownEmbedding);
    expect(recUnknown.accepted, isFalse);

    // 14. ML Recognition of second student Arun -> marked present
    final recArun = mlService.recognizeFace(arunEmbedding);
    expect(recArun.accepted, isTrue);
    final arunStudent = await studentRepo.getStudentByRegisterNumber(recArun.registerNumber!);
    final markArun = await attendanceService.markStudentPresent(
      sessionId: session.id!,
      registerNumber: arunStudent!.registerNumber,
    );
    expect(markArun, equals(MarkAttendanceResult.markedPresent));

    // 14b. ML Recognition of nameless student (strictly via register number) -> marked present
    final recNameless = mlService.recognizeFace(namelessEmbedding);
    expect(recNameless.accepted, isTrue);
    expect(recNameless.registerNumber, equals(studentNameless.registerNumber));
    final namelessRecord = await studentRepo.getStudentByRegisterNumber(recNameless.registerNumber!);
    expect(namelessRecord, isNotNull);
    final markNameless = await attendanceService.markStudentPresent(
      sessionId: session.id!,
      registerNumber: namelessRecord!.registerNumber,
    );
    expect(markNameless, equals(MarkAttendanceResult.markedPresent));

    // 15. Priya was never scanned/recognized -> remains absent!

    // 16. End Attendance Session
    final completedSession = await attendanceService.completeSession(session.id!);
    expect(completedSession.isCompleted, isTrue);
    expect(completedSession.endedAt, isNotNull);

    // 17. Final summary verification
    summary = await attendanceService.getSessionSummary(session.id!);
    expect(summary.totalCount, equals(4));
    expect(summary.presentCount, equals(3));
    expect(summary.absentCount, equals(1));

    // 18. Export JSON and verify complete class schema
    final jsonString = await exportService.exportSessionAsJsonString(session.id!);
    final exportMap = jsonDecode(jsonString) as Map<String, dynamic>;

    expect(exportMap['attendance']['session_id'], equals(session.id));
    expect(exportMap['attendance']['date'], equals('2026-09-06'));
    expect(exportMap['attendance']['teacher']['username'], equals('teacher'));
    expect(exportMap['attendance']['class']['name'], equals('B.Tech CSE - Section A'));

    final studentsExport = exportMap['students'] as List<dynamic>;
    expect(studentsExport.length, equals(4));

    // Piyush: present
    final piyushExport = studentsExport.firstWhere((s) => s['register_number'] == '23BRS1150');
    expect(piyushExport['status'], equals('present'));
    expect(piyushExport['attendance_time'], isNotNull);

    // Arun: present
    final arunExport = studentsExport.firstWhere((s) => s['register_number'] == '23BRS1001');
    expect(arunExport['status'], equals('present'));
    expect(arunExport['attendance_time'], isNotNull);

    // Nameless: present
    final namelessExport = studentsExport.firstWhere((s) => s['register_number'] == '23BRS1003');
    expect(namelessExport['status'], equals('present'));
    expect(namelessExport['attendance_time'], isNotNull);

    // Priya: absent with null attendance_time
    final priyaExport = studentsExport.firstWhere((s) => s['register_number'] == '23BRS1002');
    expect(priyaExport['status'], equals('absent'));
    expect(priyaExport['attendance_time'], isNull);

    // 19. Application restart persistence test: query history
    final history = await sessionRepo.getAllSessions();
    expect(history.length, equals(1));
    expect(history.first.id, equals(session.id));
    expect(history.first.presentCount, equals(3));
    expect(history.first.totalCount, equals(4));

    await db.close();
  });
}
