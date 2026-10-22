import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Service for exporting student records and their vector embeddings into a
/// privacy-preserving Vector ZIP archive compatible with [StudentImportService].
class StudentExportService {
  final StudentRepository _studentRepo;

  StudentExportService({
    StudentRepository? studentRepo,
  }) : _studentRepo = studentRepo ?? StudentRepository();

  /// Escapes a CSV field according to RFC 4180 rules.
  static String escapeCsv(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Converts student name and register number into canonical filename:
  /// e.g. "REGNO_FULLNAME.txt" or "REGNO.txt"
  static String buildVectorFileName(String registerNumber, String name) {
    final regClean = registerNumber.trim().toUpperCase();
    final nameClean = name.trim().replaceAll(RegExp(r'\s+'), '_').toUpperCase();
    if (nameClean.isNotEmpty && nameClean != regClean) {
      return '${regClean}_$nameClean.txt';
    }
    return '$regClean.txt';
  }

  /// Generates the raw ZIP archive bytes containing:
  /// - `students.csv`
  /// - `vectors/<REGNO_FULLNAME>.txt` (for all enrolled face vectors)
  Future<Uint8List> exportStudentsToZipBytes({
    List<Student>? students,
  }) async {
    final list = students ?? await _studentRepo.getAllStudents();
    final archive = Archive();

    final csvBuffer = StringBuffer();
    csvBuffer.writeln('register_number,name,email,phone,photo_file');

    for (final student in list) {
      final regNo = student.registerNumber.trim().toUpperCase();
      final user = LocalDB.getUser(regNo);
      final hasVector = user != null && user.array != null && user.array!.length == 512;

      String vectorPathInZip = '';

      if (hasVector) {
        final fileName = buildVectorFileName(regNo, student.name);
        vectorPathInZip = 'vectors/$fileName';

        final vectorContent = user.array!.map((v) => v.toStringAsFixed(8)).join(', ');
        final vectorBytes = utf8.encode(vectorContent);
        archive.addFile(ArchiveFile(vectorPathInZip, vectorBytes.length, vectorBytes));
      }

      csvBuffer.writeln(
        '${escapeCsv(regNo)},'
        '${escapeCsv(student.name)},'
        '${escapeCsv(student.email)},'
        '${escapeCsv(student.phone)},'
        '$vectorPathInZip',
      );
    }

    final csvBytes = utf8.encode(csvBuffer.toString());
    archive.addFile(ArchiveFile('students.csv', csvBytes.length, csvBytes));

    final zipData = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipData);
  }

  /// Exports students to a ZIP file saved in temporary or application directory.
  Future<File> exportStudentsToZipFile({
    List<Student>? students,
    String? customFileName,
    String? customDir,
  }) async {
    final bytes = await exportStudentsToZipBytes(students: students);

    final dirPath = customDir ??
        (await (Platform.isAndroid || Platform.isIOS
            ? getApplicationDocumentsDirectory()
            : getTemporaryDirectory()))
            .path;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = customFileName ?? 'students_vectors_export_$timestamp.zip';
    final file = File(p.join(dirPath, fileName));

    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Exports students to a ZIP archive and triggers the system share sheet.
  Future<ShareResult?> exportAndShareStudentsZip({
    List<Student>? students,
    String? customFileName,
  }) async {
    final file = await exportStudentsToZipFile(
      students: students,
      customFileName: customFileName,
    );

    return await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        subject: 'Students Vector Export (ZIP) - ${p.basename(file.path)}',
      ),
    );
  }
}
