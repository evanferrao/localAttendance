import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/services/student_export_service.dart';
import 'package:face_att/services/student_import_service.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempHiveDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempHiveDir = Directory.systemTemp.createTempSync('student_import_hive_test');
    Hive.init(tempHiveDir.path);
    await HiveBoxes.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempHiveDir.existsSync()) {
      tempHiveDir.deleteSync(recursive: true);
    }
  });

  late Database db;
  late AppDatabase dbManager;
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
    studentRepo = StudentRepository(dbManager);
    classRepo = ClassRepository(dbManager);
  });

  tearDown(() async {
    await db.close();
  });

  group('StudentImportService Archive Parsing Tests', () {
    test(
      'Correctly parses students_sample.zip with students.csv and photos/',
      () async {
        final zipFile = File('students_sample.zip');
        if (!await zipFile.exists()) return;

        final bytes = await zipFile.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        final service = StudentImportService(
          studentRepo: studentRepo,
          classRepo: classRepo,
        );
        final candidates = service.parseZipCandidates(archive);

        expect(candidates.isNotEmpty, isTrue);
        expect(candidates.length, equals(40));

        final first = candidates.firstWhere((c) => c.registerNumber == '22BPS1089');
        expect(first.name, equals('RISHI SIDHARTH G'));
        expect(first.photoBytes, isNotNull);
        expect(first.photoBytes!.length, greaterThan(1000));

        final rajat = candidates.firstWhere((c) => c.registerNumber == '23BAI1161');
        expect(rajat.name, equals('RAJAT'));
        expect(rajat.photoBytes, isNotNull);
        expect(rajat.photoBytes!.length, greaterThan(1000));
      },
      skip: File('students_sample.zip').existsSync()
          ? null
          : 'students_sample.zip not present in repo (skipped for consent/privacy)',
    );

    test('Fallback to filename parsing when no CSV exists in archive', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('photos/23BAI1509_ISHAAN_MILIND_SAWANT.jpeg', 10, [1, 2, 3, 4]));
      archive.addFile(ArchiveFile('photos/23BPS1006.png', 10, [5, 6, 7, 8]));

      final service = StudentImportService(
        studentRepo: studentRepo,
        classRepo: classRepo,
      );
      final candidates = service.parseZipCandidates(archive);

      expect(candidates.length, equals(2));
      final c1 = candidates.firstWhere((c) => c.registerNumber == '23BAI1509');
      expect(c1.name, equals('ISHAAN MILIND SAWANT'));
      expect(c1.photoBytes, isNotNull);

      final c2 = candidates.firstWhere((c) => c.registerNumber == '23BPS1006');
      expect(c2.name, isEmpty);
      expect(c2.photoBytes, isNotNull);
    });

    test('Pairwise JSON parsing extracts student metadata and photos', () async {
      final archive = Archive();
      final jsonData = json.encode({
        'register_number': '23BPS1081',
        'name': 'AAYUSH SHUKLA',
        'email': 'aayush@univ.edu',
        'phone': '9876543210',
      });
      archive.addFile(ArchiveFile('23BPS1081.json', jsonData.length, utf8.encode(jsonData)));
      archive.addFile(ArchiveFile('23BPS1081.jpeg', 4, [1, 2, 3, 4]));

      final service = StudentImportService(
        studentRepo: studentRepo,
        classRepo: classRepo,
      );
      final candidates = service.parseZipCandidates(archive);

      expect(candidates.length, equals(1));
      final c = candidates.first;
      expect(c.registerNumber, equals('23BPS1081'));
      expect(c.name, equals('AAYUSH SHUKLA'));
      expect(c.email, equals('aayush@univ.edu'));
      expect(c.phone, equals('9876543210'));
      expect(c.photoBytes, isNotNull);
    });

    test('Parses CSV with quoted names and optional columns omitted', () async {
      final archive = Archive();
      final csv = 'register_number,name,email,phone,photo_file\n'
          '23BPS1131,"KHANDELWAL, VAIBHAV",,,photos/23BPS1131.jpeg\n';
      archive.addFile(ArchiveFile('students.csv', csv.length, utf8.encode(csv)));
      archive.addFile(ArchiveFile('photos/23BPS1131.jpeg', 4, [1, 2, 3, 4]));

      final service = StudentImportService(
        studentRepo: studentRepo,
        classRepo: classRepo,
      );
      final candidates = service.parseZipCandidates(archive);

      expect(candidates.length, equals(1));
      final c = candidates.first;
      expect(c.registerNumber, equals('23BPS1131'));
      expect(c.name, equals('KHANDELWAL, VAIBHAV'));
      expect(c.email, isEmpty);
      expect(c.phone, isEmpty);
      expect(c.photoBytes, isNotNull);
    });

    test('parseVectorContent parses comma, space, newline, and json vectors correctly', () {
      final mockVector512 = List.generate(512, (i) => i * 0.001);

      // Comma separated
      final commaStr = mockVector512.map((d) => d.toStringAsFixed(6)).join(', ');
      final parsedComma = StudentImportService.parseVectorContent(commaStr);
      expect(parsedComma, isNotNull);
      expect(parsedComma!.length, equals(512));
      expect(parsedComma.first, closeTo(0.0, 1e-4));

      // Space separated
      final spaceStr = mockVector512.map((d) => d.toStringAsFixed(6)).join(' ');
      final parsedSpace = StudentImportService.parseVectorContent(spaceStr);
      expect(parsedSpace, isNotNull);
      expect(parsedSpace!.length, equals(512));

      // Newline separated
      final newlineStr = mockVector512.map((d) => d.toStringAsFixed(6)).join('\n');
      final parsedNewline = StudentImportService.parseVectorContent(newlineStr);
      expect(parsedNewline, isNotNull);
      expect(parsedNewline!.length, equals(512));

      // JSON array
      final jsonStr = json.encode(mockVector512);
      final parsedJson = StudentImportService.parseVectorContent(jsonStr);
      expect(parsedJson, isNotNull);
      expect(parsedJson!.length, equals(512));

      // Invalid length should be rejected
      final shortStr = '0.1, 0.2, 0.3';
      expect(StudentImportService.parseVectorContent(shortStr), isNull);
    });

    test('Correctly parses vector ZIP archive with students.csv and vectors/ folder', () async {
      final archive = Archive();
      final csv = 'register_number,name,email,phone,photo_file\n'
          '23BAI1262,FERRAO EVAN TEO,,,photos/23BAI1262_FERRAO_EVAN_TEO.jpeg\n'
          '23BRS1150,PIYUSH R SAINI,,,photos/23BRS1150_PIYUSH_R_SAINI.jpeg\n';
      archive.addFile(ArchiveFile('students.csv', csv.length, utf8.encode(csv)));

      final vec1 = List.generate(512, (i) => 0.01).join(', ');
      final vec2 = List.generate(512, (i) => 0.02).join(', ');
      archive.addFile(ArchiveFile('vectors/23BAI1262_FERRAO_EVAN_TEO.txt', vec1.length, utf8.encode(vec1)));
      archive.addFile(ArchiveFile('vectors/23BRS1150_PIYUSH_R_SAINI.txt', vec2.length, utf8.encode(vec2)));

      final service = StudentImportService(
        studentRepo: studentRepo,
        classRepo: classRepo,
      );
      final candidates = service.parseZipCandidates(archive);

      expect(candidates.length, equals(2));

      final c1 = candidates.firstWhere((c) => c.registerNumber == '23BAI1262');
      expect(c1.name, equals('FERRAO EVAN TEO'));
      expect(c1.hasVector, isTrue);
      expect(c1.vector!.length, equals(512));
      expect(c1.vector!.first, closeTo(0.01, 1e-4));

      final c2 = candidates.firstWhere((c) => c.registerNumber == '23BRS1150');
      expect(c2.name, equals('PIYUSH R SAINI'));
      expect(c2.hasVector, isTrue);
      expect(c2.vector!.length, equals(512));
      expect(c2.vector!.first, closeTo(0.02, 1e-4));
    });

    test('Fallback to filename parsing for vector ZIP when no CSV exists', () async {
      final archive = Archive();
      final vec1 = List.generate(512, (i) => 0.05).join(', ');
      final vec2 = List.generate(512, (i) => -0.05).join(', ');
      archive.addFile(ArchiveFile('vectors/23BAI1509_ISHAAN_MILIND_SAWANT.txt', vec1.length, utf8.encode(vec1)));
      archive.addFile(ArchiveFile('vectors/23BPS1006.txt', vec2.length, utf8.encode(vec2)));

      final service = StudentImportService(
        studentRepo: studentRepo,
        classRepo: classRepo,
      );
      final candidates = service.parseZipCandidates(archive);

      expect(candidates.length, equals(2));
      final c1 = candidates.firstWhere((c) => c.registerNumber == '23BAI1509');
      expect(c1.name, equals('ISHAAN MILIND SAWANT'));
      expect(c1.hasVector, isTrue);
      expect(c1.vector!.length, equals(512));

      final c2 = candidates.firstWhere((c) => c.registerNumber == '23BPS1006');
      expect(c2.name, isEmpty);
      expect(c2.hasVector, isTrue);
      expect(c2.vector!.length, equals(512));
    });

    test('Correctly parses generated 3test_vectors.zip if available', () async {
      final zipFile = File('3test_vectors.zip');
      if (!await zipFile.exists()) return;

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final service = StudentImportService(
        studentRepo: studentRepo,
        classRepo: classRepo,
      );
      final candidates = service.parseZipCandidates(archive);

      expect(candidates.length, equals(3));
      for (final c in candidates) {
        expect(c.hasVector, isTrue);
        expect(c.vector!.length, equals(512));
      }
    });
  });

  group('StudentExportService & Round-Trip Vector Import Tests', () {
    test('Exports students to Vector ZIP format matching vector import specification', () async {
      final mockVector = List.generate(512, (i) => (i + 1) * 0.001);

      // Seed student in SQLite and embedding in Hive
      await studentRepo.createStudent(
        registerNumber: '23BAI1262',
        name: 'FERRAO EVAN TEO',
        email: 'evan@univ.edu',
        phone: '1234567890',
      );
      await LocalDB.saveUser(User(
        registerNumber: '23BAI1262',
        name: 'FERRAO EVAN TEO',
        email: 'evan@univ.edu',
        phone: '1234567890',
        array: mockVector,
      ));

      final exportService = StudentExportService(studentRepo: studentRepo);
      final zipBytes = await exportService.exportStudentsToZipBytes();
      expect(zipBytes.isNotEmpty, isTrue);

      final archive = ZipDecoder().decodeBytes(zipBytes);
      final fileNames = archive.map((f) => f.name).toList();

      expect(fileNames.contains('students.csv'), isTrue);
      expect(fileNames.contains('vectors/23BAI1262_FERRAO_EVAN_TEO.txt'), isTrue);

      // Verify CSV content
      final csvFile = archive.firstWhere((f) => f.name == 'students.csv');
      final csvText = utf8.decode(csvFile.content);
      expect(csvText.contains('register_number,name,email,phone,photo_file'), isTrue);
      expect(csvText.contains('23BAI1262,FERRAO EVAN TEO,evan@univ.edu,1234567890,vectors/23BAI1262_FERRAO_EVAN_TEO.txt'), isTrue);

      // Verify vector text content
      final vecFile = archive.firstWhere((f) => f.name == 'vectors/23BAI1262_FERRAO_EVAN_TEO.txt');
      final vecText = utf8.decode(vecFile.content);
      final parsedVector = StudentImportService.parseVectorContent(vecText);
      expect(parsedVector, isNotNull);
      expect(parsedVector!.length, equals(512));
      expect(parsedVector[0], closeTo(0.001, 1e-5));
    });

    test('Exported students Vector ZIP can be directly imported via StudentImportService', () async {
      final mockVector = List.generate(512, (i) => 0.05);

      // 1. Prepare student in DB & Hive
      await studentRepo.createStudent(
        registerNumber: '23BRS1150',
        name: 'PIYUSH R SAINI',
        email: 'piyush@univ.edu',
        phone: '9876543210',
      );
      await LocalDB.saveUser(User(
        registerNumber: '23BRS1150',
        name: 'PIYUSH R SAINI',
        email: 'piyush@univ.edu',
        phone: '9876543210',
        array: mockVector,
      ));

      // 2. Export to ZIP bytes
      final exportService = StudentExportService(studentRepo: studentRepo);
      final zipBytes = await exportService.exportStudentsToZipBytes();

      // 3. Clear data to test round-trip import
      await db.delete('students');
      await LocalDB.deleteUser('23BRS1150');
      expect(await studentRepo.getStudentByRegisterNumber('23BRS1150'), isNull);
      expect(LocalDB.getUser('23BRS1150'), isNull);

      // 4. Perform vector import on exported ZIP bytes
      final importService = StudentImportService(studentRepo: studentRepo);
      final summary = await importService.importVectorsFromZipBytes(zipBytes: zipBytes);

      expect(summary.totalCount, greaterThanOrEqualTo(1));
      expect(summary.successCount, greaterThanOrEqualTo(1));
      expect(summary.failedCount, equals(0));

      // 5. Verify restored in SQLite and Hive
      final restoredStudent = await studentRepo.getStudentByRegisterNumber('23BRS1150');
      expect(restoredStudent, isNotNull);
      expect(restoredStudent!.name, equals('PIYUSH R SAINI'));
      expect(restoredStudent.hasFaceEnrolled, isTrue);

      final restoredUser = LocalDB.getUser('23BRS1150');
      expect(restoredUser, isNotNull);
      expect(restoredUser!.array, isNotNull);
      expect(restoredUser.array!.length, equals(512));
      expect(restoredUser.array![0], closeTo(0.05, 1e-4));
    });
  });
}


