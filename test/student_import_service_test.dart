import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/database_schema.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/services/student_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
  });
}
