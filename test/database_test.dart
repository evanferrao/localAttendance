import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/database/repositories/teacher_repository.dart';
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
          await AppDatabase.seedInitialDataIfNeeded(db);
        },
      ),
    );
    dbManager.setDatabaseForTesting(db);
    teacherRepo = TeacherRepository(dbManager);
    studentRepo = StudentRepository(dbManager);
    classRepo = ClassRepository(dbManager);
  });

  tearDown(() async {
    await db.close();
  });

  group('Teacher Database Tests', () {
    test('Default teacher account is seeded on fresh database', () async {
      final defaultTeacher = await teacherRepo.getTeacherByUsername('teacher');
      expect(defaultTeacher, isNotNull);
      expect(defaultTeacher!.displayName, equals('Teacher'));
      expect(
        TeacherAuthService.verifyPassword('password', defaultTeacher.passwordHash),
        isTrue,
      );
    });

    test('Create teacher succeeds and hashes password', () async {
      final hash = TeacherAuthService.hashPassword('secure123');
      final teacher = await teacherRepo.createTeacher(
        username: 'prof_smith',
        passwordHash: hash,
        displayName: 'Professor Smith',
      );

      expect(teacher.id, isNotNull);
      expect(teacher.username, equals('prof_smith'));
      expect(teacher.displayName, equals('Professor Smith'));

      final retrieved = await teacherRepo.getTeacherById(teacher.id!);
      expect(retrieved, isNotNull);
      expect(retrieved!.username, equals('prof_smith'));
      expect(TeacherAuthService.verifyPassword('secure123', retrieved.passwordHash), isTrue);
    });

    test('Duplicate teacher username is rejected with DatabaseException', () async {
      final hash = TeacherAuthService.hashPassword('pass');
      await teacherRepo.createTeacher(
        username: 'unique_user',
        passwordHash: hash,
        displayName: 'User 1',
      );

      expect(
        () async => await teacherRepo.createTeacher(
          username: 'unique_user',
          passwordHash: hash,
          displayName: 'User 2',
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('Teacher authentication succeeds with correct password and fails with invalid password', () async {
      final hash = TeacherAuthService.hashPassword('mySecretPass');
      await teacherRepo.createTeacher(
        username: 'janedoe',
        passwordHash: hash,
        displayName: 'Jane Doe',
      );

      final teacher = await teacherRepo.getTeacherByUsername('janedoe');
      expect(teacher, isNotNull);
      expect(TeacherAuthService.verifyPassword('mySecretPass', teacher!.passwordHash), isTrue);
      expect(TeacherAuthService.verifyPassword('wrongPass', teacher.passwordHash), isFalse);
    });
  });

  group('Student Database Tests', () {
    test('Create student succeeds with valid attributes', () async {
      final student = await studentRepo.createStudent(
        registerNumber: '23BRS1150',
        name: 'Piyush R Saini',
        email: 'piyush@example.com',
        phone: '9876543210',
      );

      expect(student.registerNumber, equals('23BRS1150'));
      expect(student.name, equals('Piyush R Saini'));

      final fetched = await studentRepo.getStudentByRegisterNumber(student.registerNumber);
      expect(fetched, isNotNull);
      expect(fetched!.registerNumber, equals('23BRS1150'));
    });

    test('Create student succeeds with only register number (all other fields optional)', () async {
      final student = await studentRepo.createStudent(
        registerNumber: '23BRS9999',
      );

      expect(student.registerNumber, equals('23BRS9999'));
      expect(student.name, isEmpty);
      expect(student.email, isEmpty);
      expect(student.phone, isEmpty);
      expect(student.displayName, equals('23BRS9999'));

      final fetched = await studentRepo.getStudentByRegisterNumber(student.registerNumber);
      expect(fetched, isNotNull);
      expect(fetched!.registerNumber, equals('23BRS9999'));
      expect(fetched.displayName, equals('23BRS9999'));
    });

    test('Duplicate register number is rejected with DatabaseException', () async {
      await studentRepo.createStudent(
        registerNumber: '23BRS1001',
        name: 'Arun Kumar',
        email: 'arun@example.com',
        phone: '9876543210',
      );

      expect(
        () async => await studentRepo.createStudent(
          registerNumber: '23BRS1001',
          name: 'Another Arun',
          email: 'another@example.com',
          phone: '9876543211',
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('Retrieve student by register number (case-insensitive)', () async {
      await studentRepo.createStudent(
        registerNumber: '23BRS1002',
        name: 'Priya Sharma',
        email: 'priya@example.com',
        phone: '9876543211',
      );

      final found = await studentRepo.getStudentByRegisterNumber('23brs1002');
      expect(found, isNotNull);
      expect(found!.name, equals('Priya Sharma'));
    });
  });

  group('Class Database Tests', () {
    test('Create class requires at least one teacher', () async {
      expect(
        () async => await classRepo.createClass(
          name: 'CSE 101',
          teacherIds: [],
        ),
        throwsArgumentError,
      );
    });

    test('Create class succeeds with teachers and students transactionally', () async {
      final teacher1 = (await teacherRepo.getTeacherByUsername('teacher'))!;
      final s1 = await studentRepo.createStudent(
        registerNumber: '23BRS1001',
        name: 'Arun Kumar',
        email: 'arun@example.com',
        phone: '9876543210',
      );
      final s2 = await studentRepo.createStudent(
        registerNumber: '23BRS1002',
        name: 'Priya Sharma',
        email: 'priya@example.com',
        phone: '9876543211',
      );

      final newClass = await classRepo.createClass(
        name: 'B.Tech CSE - Section A',
        teacherIds: [teacher1.id!],
        studentRegisterNumbers: [s1.registerNumber, s2.registerNumber],
      );

      expect(newClass.id, isNotNull);
      expect(newClass.name, equals('B.Tech CSE - Section A'));
      expect(newClass.teacherIds, contains(teacher1.id));
      expect(newClass.studentRegisterNumbers, containsAll([s1.registerNumber, s2.registerNumber]));

      final fetchedClass = await classRepo.getClassById(newClass.id!);
      expect(fetchedClass, isNotNull);
      expect(fetchedClass!.teachersCount, equals(1));
      expect(fetchedClass.studentsCount, equals(2));

      final isT1Assigned = await classRepo.isTeacherAssignedToClass(teacher1.id!, newClass.id!);
      expect(isT1Assigned, isTrue);

      final isS1Enrolled = await classRepo.isStudentEnrolledInClass(s1.registerNumber, newClass.id!);
      expect(isS1Enrolled, isTrue);
    });

    test('Prevent duplicate teacher or student assignments to class', () async {
      final teacher1 = (await teacherRepo.getTeacherByUsername('teacher'))!;
      final s1 = await studentRepo.createStudent(
        registerNumber: '23BRS1001',
        name: 'Arun Kumar',
        email: 'arun@example.com',
        phone: '9876543210',
      );

      final newClass = await classRepo.createClass(
        name: 'Physics Lab',
        teacherIds: [teacher1.id!, teacher1.id!], // duplicate in input
        studentRegisterNumbers: [s1.registerNumber, s1.registerNumber], // duplicate in input
      );

      expect(newClass.teachersCount, equals(1));
      expect(newClass.studentsCount, equals(1));

      // Attempt manual re-assignment
      await classRepo.assignTeacherToClass(newClass.id!, teacher1.id!);
      await classRepo.assignStudentToClass(newClass.id!, s1.registerNumber);

      final teachers = await classRepo.getTeacherIdsForClass(newClass.id!);
      final students = await classRepo.getStudentRegisterNumbersForClass(newClass.id!);
      expect(teachers.length, equals(1));
      expect(students.length, equals(1));
    });

    test('Batch assign multiple students to class at once', () async {
      final teacher1 = (await teacherRepo.getTeacherByUsername('teacher'))!;
      final s1 = await studentRepo.createStudent(registerNumber: '23BRS2001', name: 'Student 1');
      final s2 = await studentRepo.createStudent(registerNumber: '23BRS2002', name: 'Student 2');
      final s3 = await studentRepo.createStudent(registerNumber: '23BRS2003', name: 'Student 3');

      final newClass = await classRepo.createClass(
        name: 'Chemistry Lab',
        teacherIds: [teacher1.id!],
        studentRegisterNumbers: [],
      );

      expect(newClass.studentsCount, equals(0));

      await classRepo.assignStudentsToClass(newClass.id!, [
        s1.registerNumber,
        s2.registerNumber,
        s3.registerNumber,
      ]);

      final enrolled = await classRepo.getStudentRegisterNumbersForClass(newClass.id!);
      expect(enrolled.length, equals(3));
      expect(enrolled, containsAll([s1.registerNumber, s2.registerNumber, s3.registerNumber]));
    });
  });
}
