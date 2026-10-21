import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/services/face_recognition/ml_service.dart';
import 'package:flutter/foundation.dart';

/// Candidate student record parsed from ZIP contents prior to ML enrollment.
class StudentImportCandidate {
  final String registerNumber;
  final String name;
  final String email;
  final String phone;
  final String? photoPath;
  final Uint8List? photoBytes;

  const StudentImportCandidate({
    required this.registerNumber,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.photoPath,
    this.photoBytes,
  });

  Student toStudent({bool hasFaceEnrolled = false}) {
    return Student(
      registerNumber: registerNumber,
      name: name,
      email: email,
      phone: phone,
      hasFaceEnrolled: hasFaceEnrolled,
    );
  }
}

/// Result for an individual student processed during batch import.
class StudentImportItemResult {
  final String registerNumber;
  final String name;
  final bool success;
  final bool faceEnrolled;
  final String? errorMessage;

  const StudentImportItemResult({
    required this.registerNumber,
    required this.name,
    required this.success,
    required this.faceEnrolled,
    this.errorMessage,
  });
}

/// Overall summary report returned after importing a ZIP archive.
class StudentImportSummary {
  final int totalCount;
  final int successCount;
  final int failedCount;
  final List<StudentImportItemResult> results;

  const StudentImportSummary({
    required this.totalCount,
    required this.successCount,
    required this.failedCount,
    required this.results,
  });

  bool get hasFailures => failedCount > 0;
}

/// Callback for tracking import progress: (current, total, currentStudentLabel)
typedef ImportProgressCallback = void Function(int current, int total, String currentLabel);

/// Service for importing, parsing, and enrolling students from ZIP files.
class StudentImportService {
  final StudentRepository _studentRepo;
  final ClassRepository _classRepo;
  final MLService _mlService;

  StudentImportService({
    StudentRepository? studentRepo,
    ClassRepository? classRepo,
    MLService? mlService,
  })  : _studentRepo = studentRepo ?? StudentRepository(),
        _classRepo = classRepo ?? ClassRepository(),
        _mlService = mlService ?? MLService();

  /// Supported image extensions for face photos
  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  /// Main entry point: Import from a local file path.
  Future<StudentImportSummary> importFromZipFile({
    required String filePath,
    int? classId,
    ImportProgressCallback? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ArgumentError('ZIP file does not exist at path: $filePath');
    }
    final bytes = await file.readAsBytes();
    return importFromZipBytes(
      zipBytes: bytes,
      classId: classId,
      onProgress: onProgress,
    );
  }

  /// Import from raw ZIP bytes in memory.
  Future<StudentImportSummary> importFromZipBytes({
    required Uint8List zipBytes,
    int? classId,
    ImportProgressCallback? onProgress,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final candidates = parseZipCandidates(archive);

    final total = candidates.length;
    if (total == 0) {
      return const StudentImportSummary(
        totalCount: 0,
        successCount: 0,
        failedCount: 0,
        results: [],
      );
    }

    final results = <StudentImportItemResult>[];
    int successCount = 0;
    int failedCount = 0;

    for (int i = 0; i < total; i++) {
      final candidate = candidates[i];
      final regNo = candidate.registerNumber.trim();
      final label = candidate.name.isNotEmpty ? '$regNo (${candidate.name})' : regNo;

      onProgress?.call(i + 1, total, label);

      try {
        if (regNo.isEmpty) {
          failedCount++;
          results.add(StudentImportItemResult(
            registerNumber: 'UNKNOWN',
            name: candidate.name,
            success: false,
            faceEnrolled: false,
            errorMessage: 'Registration number is missing or empty',
          ));
          continue;
        }

        bool faceEnrolled = false;
        String? faceError;

        if (candidate.photoBytes != null && candidate.photoBytes!.isNotEmpty) {
          try {
            final user = await _mlService.enrollFromImageBytes(
              bytes: candidate.photoBytes!,
              registerNumber: regNo,
              name: candidate.name,
              email: candidate.email,
              phone: candidate.phone,
            );

            // Double check valid embedding was produced
            if (user.array != null && user.array!.length == 512) {
              faceEnrolled = true;
            } else {
              faceError = 'Could not generate valid 512-d face embedding';
            }
          } catch (e) {
            faceError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
          }
        } else {
          faceError = 'No photo found matching registration number in archive';
        }

        // Save or update student in SQLite
        final existing = await _studentRepo.getStudentByRegisterNumber(regNo);
        if (existing != null) {
          await _studentRepo.updateStudent(existing.copyWith(
            name: candidate.name.isNotEmpty ? candidate.name : existing.name,
            email: candidate.email.isNotEmpty ? candidate.email : existing.email,
            phone: candidate.phone.isNotEmpty ? candidate.phone : existing.phone,
            hasFaceEnrolled: faceEnrolled || existing.hasFaceEnrolled,
          ));
        } else {
          await _studentRepo.createStudent(
            registerNumber: regNo,
            name: candidate.name,
            email: candidate.email,
            phone: candidate.phone,
          );
        }

        // If target class specified, assign student to the class
        if (classId != null) {
          await _classRepo.assignStudentToClass(classId, regNo);
        }

        if (faceEnrolled) {
          successCount++;
          results.add(StudentImportItemResult(
            registerNumber: regNo,
            name: candidate.name,
            success: true,
            faceEnrolled: true,
          ));
        } else {
          // If face was not enrolled, we record it as a failure for face-attendance purposes
          failedCount++;
          results.add(StudentImportItemResult(
            registerNumber: regNo,
            name: candidate.name,
            success: false,
            faceEnrolled: false,
            errorMessage: faceError ?? 'Face could not be enrolled',
          ));
        }
      } catch (e) {
        failedCount++;
        results.add(StudentImportItemResult(
          registerNumber: regNo,
          name: candidate.name,
          success: false,
          faceEnrolled: false,
          errorMessage: 'Unexpected error: $e',
        ));
      }
    }

    return StudentImportSummary(
      totalCount: total,
      successCount: successCount,
      failedCount: failedCount,
      results: results,
    );
  }

  /// Parses an extracted [Archive] into a list of [StudentImportCandidate]s.
  /// Handles:
  /// 1. CSV Manifest + photos (Tier 1)
  /// 2. Pairwise JSON + photo (Tier 2)
  /// 3. Direct filename photos (Tier 3 fallback)
  List<StudentImportCandidate> parseZipCandidates(Archive archive) {
    // 1. Index all image files by normalized path and by filename prefix
    final imagesByNormalizedPath = <String, Uint8List>{};
    final imagesByFilename = <String, Uint8List>{};
    final imagesByOriginalFilename = <String, Uint8List>{};
    ArchiveFile? csvFile;
    final jsonFiles = <String, ArchiveFile>{};

    for (final file in archive) {
      if (!file.isFile) continue;
      final normalizedPath = file.name.replaceAll('\\', '/');
      final fileName = normalizedPath.split('/').last;
      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

      final bytes = file.content;

      if (_imageExtensions.contains(ext)) {
        imagesByNormalizedPath[normalizedPath.toLowerCase()] = bytes;
        imagesByFilename[fileName.toLowerCase()] = bytes;
        imagesByOriginalFilename[fileName] = bytes;
      } else if (ext == 'csv' && csvFile == null) {
        csvFile = file;
      } else if (ext == 'json') {
        jsonFiles[fileName.toLowerCase()] = file;
      }
    }

    // TIER 1: If CSV file exists, parse CSV
    if (csvFile != null) {
      final csvContent = utf8.decode(csvFile.content, allowMalformed: true);
      final fromCsv = _parseCandidatesFromCsv(csvContent, imagesByNormalizedPath, imagesByFilename);
      if (fromCsv.isNotEmpty) {
        return fromCsv;
      }
    }

    // TIER 2: Check for pairwise JSON files (<reg_no>.json)
    if (jsonFiles.isNotEmpty) {
      final fromJson = _parseCandidatesFromJson(jsonFiles, imagesByFilename);
      if (fromJson.isNotEmpty) {
        return fromJson;
      }
    }

    // TIER 3: Filename-based fallback (e.g. REGNO_FULLNAME.jpeg or REGNO.jpeg)
    final fromFilenames = <StudentImportCandidate>[];
    for (final entry in imagesByOriginalFilename.entries) {
      final rawFilename = entry.key;
      final identity = MLService.parseIdentityFromFilename(rawFilename);
      final regNo = identity['register_number']?.trim().toUpperCase() ?? '';
      final name = identity['name']?.trim() ?? '';

      if (regNo.isNotEmpty) {
        fromFilenames.add(StudentImportCandidate(
          registerNumber: regNo,
          name: name == regNo ? '' : name,
          photoPath: rawFilename,
          photoBytes: entry.value,
        ));
      }
    }

    return fromFilenames;
  }

  /// Parses CSV table lines into student candidates
  List<StudentImportCandidate> _parseCandidatesFromCsv(
    String csvContent,
    Map<String, Uint8List> imagesByNormalizedPath,
    Map<String, Uint8List> imagesByFilename,
  ) {
    final lines = const LineSplitter().convert(csvContent);
    if (lines.isEmpty) return [];

    final rows = lines.map(_parseCsvRow).where((r) => r.isNotEmpty).toList();
    if (rows.length < 2) return [];

    final headers = rows.first.map((h) => h.trim().toLowerCase()).toList();

    // Identify header positions
    int regIndex = -1;
    int nameIndex = -1;
    int emailIndex = -1;
    int phoneIndex = -1;
    int photoIndex = -1;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (regIndex == -1 &&
          (h.contains('register') ||
              h.contains('reg_no') ||
              h.contains('roll') ||
              h.contains('reg no') ||
              h.contains('registration'))) {
        regIndex = i;
      } else if (nameIndex == -1 && (h.contains('name') || h.contains('student'))) {
        nameIndex = i;
      } else if (emailIndex == -1 && h.contains('email')) {
        emailIndex = i;
      } else if (phoneIndex == -1 && (h.contains('phone') || h.contains('mobile') || h.contains('contact'))) {
        phoneIndex = i;
      } else if (photoIndex == -1 && (h.contains('photo') || h.contains('image') || h.contains('file') || h.contains('picture'))) {
        photoIndex = i;
      }
    }

    // If no explicit registration column was recognized, assume first column
    if (regIndex == -1) regIndex = 0;

    final candidates = <StudentImportCandidate>[];

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (regIndex >= row.length) continue;

      final regNo = row[regIndex].trim().toUpperCase();
      if (regNo.isEmpty) continue;

      final name = (nameIndex != -1 && nameIndex < row.length) ? row[nameIndex].trim() : '';
      final email = (emailIndex != -1 && emailIndex < row.length) ? row[emailIndex].trim() : '';
      final phone = (phoneIndex != -1 && phoneIndex < row.length) ? row[phoneIndex].trim() : '';
      final photoVal = (photoIndex != -1 && photoIndex < row.length) ? row[photoIndex].trim() : '';

      Uint8List? matchedBytes;
      String? matchedPath;

      // 1. Check explicit photo path in CSV
      if (photoVal.isNotEmpty) {
        final normPath = photoVal.replaceAll('\\', '/').toLowerCase();
        final baseName = normPath.split('/').last;

        if (imagesByNormalizedPath.containsKey(normPath)) {
          matchedBytes = imagesByNormalizedPath[normPath];
          matchedPath = photoVal;
        } else if (imagesByFilename.containsKey(baseName)) {
          matchedBytes = imagesByFilename[baseName];
          matchedPath = baseName;
        }
      }

      // 2. If not found by path, match by register number prefix
      if (matchedBytes == null) {
        final regLower = regNo.toLowerCase();
        for (final entry in imagesByFilename.entries) {
          final fname = entry.key;
          // Matches e.g. 23bai1161.jpg, 23bai1161_rajat.jpg, 23bai1161 - rajat.png
          if (fname.startsWith(regLower)) {
            matchedBytes = entry.value;
            matchedPath = entry.key;
            break;
          }
        }
      }

      candidates.add(StudentImportCandidate(
        registerNumber: regNo,
        name: name,
        email: email,
        phone: phone,
        photoPath: matchedPath,
        photoBytes: matchedBytes,
      ));
    }

    return candidates;
  }

  /// Parses pairwise JSON files (`<reg_no>.json`)
  List<StudentImportCandidate> _parseCandidatesFromJson(
    Map<String, ArchiveFile> jsonFiles,
    Map<String, Uint8List> imagesByFilename,
  ) {
    final candidates = <StudentImportCandidate>[];

    for (final entry in jsonFiles.entries) {
      final jsonFileName = entry.key; // e.g. 23bai1161.json
      final regNoKey = jsonFileName.contains('.')
          ? jsonFileName.substring(0, jsonFileName.lastIndexOf('.'))
          : jsonFileName;

      try {
        final rawContent = utf8.decode(entry.value.content, allowMalformed: true);
        final map = json.decode(rawContent) as Map<String, dynamic>;

        final regNo = (map['register_number'] ?? map['reg_no'] ?? regNoKey).toString().trim().toUpperCase();
        final name = (map['name'] ?? '').toString().trim();
        final email = (map['email'] ?? '').toString().trim();
        final phone = (map['phone'] ?? '').toString().trim();

        // Match photo by register number
        Uint8List? matchedBytes;
        String? matchedPath;

        final regLower = regNo.toLowerCase();
        for (final imgEntry in imagesByFilename.entries) {
          if (imgEntry.key.startsWith(regLower)) {
            matchedBytes = imgEntry.value;
            matchedPath = imgEntry.key;
            break;
          }
        }

        candidates.add(StudentImportCandidate(
          registerNumber: regNo,
          name: name,
          email: email,
          phone: phone,
          photoPath: matchedPath,
          photoBytes: matchedBytes,
        ));
      } catch (e) {
        debugPrint('Failed to parse json candidate $jsonFileName: $e');
      }
    }

    return candidates;
  }

  /// Robust CSV row tokenizer respecting quotes and escaped characters
  List<String> _parseCsvRow(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++; // skip escaped quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString());
    return result;
  }
}
