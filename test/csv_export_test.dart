import 'dart:io';
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

  group('CSV Export Tests', () {
    test('RFC 4180 field escaping helper works correctly', () {
      expect(AttendanceExportService.escapeCsvField(null), equals(''));
      expect(AttendanceExportService.escapeCsvField(''), equals(''));
      expect(AttendanceExportService.escapeCsvField('Simple'), equals('Simple'));
      expect(
        AttendanceExportService.escapeCsvField('Smith, John'),
        equals('"Smith, John"'),
      );
      expect(
        AttendanceExportService.escapeCsvField('He said "Hello"'),
        equals('"He said ""Hello"""'),
      );
      expect(
        AttendanceExportService.escapeCsvField('Line 1\nLine 2'),
        equals('"Line 1\nLine 2"'),
      );
    });

    test('CSV Export contains correct header, student records, and formatting', () async {
      // 1. Setup entities
      final teacher = await teacherRepo.createTeacher(
        username: 'prof_smith',
        passwordHash: TeacherAuthService.hashPassword('securePass123'),
        displayName: 'Professor Smith',
      );

      final arun = await studentRepo.createStudent(
        registerNumber: '23BRS1001',
        name: 'Arun Kumar',
        email: 'arun@example.com',
        phone: '9876543210',
      );
      final priya = await studentRepo.createStudent(
        registerNumber: '23BRS1002',
        name: 'Priya "Special" Sharma, Jr.',
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
        attendanceDate: '2026-09-21',
      );

      // 3. Mark Arun and Priya present, leave Rahul absent
      await attendanceService.markStudentPresent(
        sessionId: session.id!,
        studentId: arun.id!,
      );
      await attendanceService.markStudentPresent(
        sessionId: session.id!,
        studentId: priya.id!,
      );

      // 4. Complete session
      await attendanceService.completeSession(session.id!);

      // 5. Generate CSV string
      final csvString = await exportService.exportSessionAsCsvString(session.id!);
      expect(csvString, isNotEmpty);

      // 6. Verify lines
      final lines = csvString.trim().split(RegExp(r'\r?\n'));
      expect(lines.length, equals(4)); // 1 header + 3 students

      // Header verification
      expect(
        lines[0],
        equals('Register Number,Name,Status,Attendance Time,Email,Phone,Class,Date,Session ID'),
      );

      // Verify Arun (Present)
      final arunLine = lines.firstWhere((l) => l.startsWith('23BRS1001'));
      expect(arunLine, contains('Arun Kumar'));
      expect(arunLine, contains(',present,'));
      expect(arunLine, contains('arun@example.com'));
      expect(arunLine, contains('B.Tech CSE - Section A'));
      expect(arunLine, contains('2026-09-21'));
      expect(arunLine, contains('${session.id}'));

      // Verify Priya (Present with quotes and comma in name)
      final priyaLine = lines.firstWhere((l) => l.startsWith('23BRS1002'));
      expect(priyaLine, contains('"Priya ""Special"" Sharma, Jr."'));
      expect(priyaLine, contains(',present,'));
      expect(priyaLine, contains('priya@example.com'));

      // Verify Rahul (Absent - attendance time should be empty)
      final rahulLine = lines.firstWhere((l) => l.startsWith('23BRS1003'));
      expect(rahulLine, contains('Rahul Kumar'));
      expect(rahulLine, contains(',absent,,'));
      expect(rahulLine, contains('rahul@example.com'));

      // 7. Verify filename generation
      final filename = AttendanceExportService.generateFilename(
        className: classA.name,
        attendanceDate: '2026-09-21',
        sessionId: session.id!,
        extension: 'csv',
      );
      expect(
        filename,
        equals('attendance_b_tech_cse_section_a_2026-09-21_session_${session.id}.csv'),
      );

      // 8. Verify export to CSV file
      final tempDir = await Directory.systemTemp.createTemp('csv_test');
      try {
        final exportedFile = await exportService.exportSessionToCsvFile(
          session.id!,
          customDir: tempDir.path,
        );
        expect(await exportedFile.exists(), isTrue);
        expect(exportedFile.path.endsWith('.csv'), isTrue);
        final fileContent = await exportedFile.readAsString();
        expect(fileContent, equals(csvString));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
