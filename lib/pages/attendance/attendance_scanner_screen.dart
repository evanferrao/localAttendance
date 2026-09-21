import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:face_att/database/repositories/attendance_record_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/attendance_record.dart';
import 'package:face_att/models/attendance_session.dart';
import 'package:face_att/models/class_model.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/models/teacher.dart';
import 'package:face_att/pages/attendance/attendance_summary_screen.dart';
import 'package:face_att/pages/face_recognition/camera_screen.dart';
import 'package:face_att/pages/face_recognition/liveness_service.dart';
import 'package:face_att/pages/face_recognition/ml_service.dart';
import 'package:face_att/pages/face_recognition/spoof_guard.dart';
import 'package:face_att/services/attendance_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class AttendanceScannerScreen extends StatefulWidget {
  final AttendanceSession session;
  final Teacher teacher;
  final ClassModel classModel;

  const AttendanceScannerScreen({
    super.key,
    required this.session,
    required this.teacher,
    required this.classModel,
  });

  @override
  State<AttendanceScannerScreen> createState() => _AttendanceScannerScreenState();
}

class _AttendanceScannerScreenState extends State<AttendanceScannerScreen> with SingleTickerProviderStateMixin {
  static const int kCaptureIntervalSeconds = 4;

  final AttendanceService _attendanceService = AttendanceService();
  final AttendanceRecordRepository _recordRepo = AttendanceRecordRepository();
  final StudentRepository _studentRepo = StudentRepository();
  final MLService _mlService = MLService();
  final LivenessService _livenessService = LivenessService();
  final ImagePicker _picker = ImagePicker();

  CameraController? _cameraController;
  bool _isControllerInitialized = false;
  bool _isCapturing = false;
  bool _isProcessing = false;
  bool _isDisposed = false;

  /// Mode: false = Single Mode (Portrait, 1 student)
  ///       true = Classroom Mode (Landscape, identifies multiple students)
  bool _isEasyMode = false;

  int _countdown = kCaptureIntervalSeconds;
  Timer? _intervalTimer;

  // In-memory tracking
  final Set<int> _presentStudentIds = {};
  Set<int> _enrolledStudentIds = {};
  List<Student> _enrolledStudents = [];
  Set<String> _allowedStudentIds = {};
  List<AttendanceRecord> _records = [];

  String _statusMessage = "Position face inside frame";
  Color _feedbackColor = Colors.white70;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadClassAndRecords();
    _initializeCamera();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _intervalTimer?.cancel();
    _cameraController?.dispose();
    _cameraController = null;
    _tabController.dispose();
    // Restore portrait orientation when leaving the scanner
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  /// Toggle between Single Mode (Portrait) and Classroom Mode (Landscape Multi-Student)
  Future<void> _toggleMode() async {
    final newMode = !_isEasyMode;
    setState(() {
      _isEasyMode = newMode;
      _countdown = kCaptureIntervalSeconds;
      _statusMessage = newMode
          ? "Classroom Mode • Scanning multiple students..."
          : "Single Mode • Position student face in frame";
      _feedbackColor = newMode ? AppColors.present : Colors.white70;
    });

    if (newMode) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  Future<void> _loadClassAndRecords() async {
    final records = await _recordRepo.getRecordsForSession(widget.session.id!);
    final presentIds = await _recordRepo.getPresentStudentIds(widget.session.id!);
    final enrolledStudents = await _studentRepo.getStudentsForClass(widget.classModel.id!);

    final allowedIds = <String>{};
    for (final s in enrolledStudents) {
      if (s.id != null) allowedIds.add(s.id.toString());
      if (s.registerNumber.isNotEmpty) {
        allowedIds.add(s.registerNumber.trim());
        allowedIds.add(s.registerNumber.trim().toUpperCase());
        allowedIds.add(s.registerNumber.trim().toLowerCase());
      }
      if (s.name.isNotEmpty) {
        allowedIds.add(s.name.trim().toLowerCase());
      }
    }

    if (mounted) {
      setState(() {
        _records = records;
        _presentStudentIds.clear();
        _presentStudentIds.addAll(presentIds);
        _enrolledStudents = enrolledStudents;
        _enrolledStudentIds = enrolledStudents.map((s) => s.id!).toSet();
        _allowedStudentIds = allowedIds;
      });
    }
  }

  Future<void> _initializeCamera() async {
    if (cameras == null || cameras!.isEmpty) {
      try {
        cameras = await availableCameras();
      } catch (_) {}
    }

    if (cameras == null || cameras!.isEmpty) {
      if (mounted) {
        setState(() {
          _statusMessage = "No camera hardware detected";
        });
      }
      return;
    }

    final camera = cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras!.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(FlashMode.off);

      if (_isDisposed || !mounted) return;
      setState(() => _isControllerInitialized = true);

      _startCountdownLoop();
    } catch (e) {
      debugPrint("Camera init error: $e");
      if (mounted) {
        setState(() {
          _statusMessage = "Camera error: $e";
        });
      }
    }
  }

  void _startCountdownLoop() {
    _intervalTimer?.cancel();
    _countdown = kCaptureIntervalSeconds;
    _intervalTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed || !mounted) {
        timer.cancel();
        return;
      }
      if (_isCapturing || _isProcessing) return;

      setState(() {
        if (_countdown > 1) {
          _countdown--;
        } else {
          _countdown = kCaptureIntervalSeconds;
          _triggerScan();
        }
      });
    });
  }

  Future<void> _triggerScan() async {
    if (_isCapturing || _isProcessing || !_isControllerInitialized || _cameraController == null) return;
    if (_cameraController!.value.isTakingPicture) return;

    setState(() {
      _isCapturing = true;
      _statusMessage = _isEasyMode
          ? "Scanning classroom..."
          : "Verifying face...";
      _feedbackColor = Theme.of(context).colorScheme.primary;
    });

    XFile? pictureFile;
    try {
      pictureFile = await _cameraController!.takePicture();
      final bytes = await pictureFile.readAsBytes();

      try {
        await File(pictureFile.path).delete();
      } catch (_) {}

      await _processImageBytes(bytes);
    } catch (e) {
      debugPrint("Scan capture error: $e");
      if (mounted) {
        setState(() {
          _statusMessage = "Scan error. Retrying...";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
    } finally {
      if (mounted && !_isProcessing) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _processImageBytes(Uint8List bytes) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = _isEasyMode
          ? "Detecting classroom faces with ArcFace..."
          : "Analyzing face with ArcFace...";
      _feedbackColor = Theme.of(context).colorScheme.primary;
    });

    try {
      if (_enrolledStudents.isEmpty) {
        if (mounted) {
          setState(() {
            _statusMessage = "No students enrolled in this class";
            _feedbackColor = AppColors.warning;
            _countdown = kCaptureIntervalSeconds;
          });
        }
        return;
      }

      if (_isEasyMode) {
        await _processEasyModeBatch(bytes);
      } else {
        await _processNormalModeSingle(bytes);
      }
    } catch (e) {
      debugPrint("Inference error: $e");
      if (mounted) {
        setState(() {
          _statusMessage = "Recognition error: $e";
          _feedbackColor = AppColors.absent;
          _countdown = kCaptureIntervalSeconds;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isCapturing = false;
        });
      }
    }
  }

  /// Single Mode: Limit to 1 student at a time (focusing on primary face)
  Future<void> _processNormalModeSingle(Uint8List bytes) async {
    final faceData = await _mlService.detectFaceOnImageBytes(
      bytes,
      sensorOrientation: _cameraController?.description.sensorOrientation,
    );
    if (faceData == null) {
      if (mounted) {
        setState(() {
          _statusMessage = "No face detected • Align face in frame";
          _feedbackColor = Colors.white70;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    // Check Anti-Spoofing and Liveness if mlKitFace is available
    if (faceData.mlKitFace != null) {
      final spoofWarning = SpoofGuard.check(faceData.mlKitFace!);
      if (spoofWarning != null) {
        if (mounted) {
          setState(() {
            _statusMessage = "Alert: $spoofWarning";
            _feedbackColor = AppColors.warning;
            _countdown = kCaptureIntervalSeconds;
          });
        }
        return;
      }
      _livenessService.process(faceData.mlKitFace!);
    }

    final effectiveBytes = faceData.correctedImageBytes ?? bytes;
    final embedding = await _mlService.getEmbeddingFromImageBytes(
      effectiveBytes,
      boundingBox: faceData.boundingBox,
      landmarks: faceData.landmarks,
    );

    final result = _mlService.recognizeFace(
      embedding,
      allowedStudentIds: _allowedStudentIds,
    );
    await _handleRecognitionResult(result);
  }

  /// Classroom Mode: Identifies multiple students simultaneously
  Future<void> _processEasyModeBatch(Uint8List bytes) async {
    final faces = await _mlService.detectAllFacesOnImageBytes(
      bytes,
      sensorOrientation: _cameraController?.description.sensorOrientation,
    );

    if (faces.isEmpty) {
      if (mounted) {
        setState(() {
          _statusMessage = "No students detected • Aim camera at class";
          _feedbackColor = Colors.white70;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    final effectiveBytes = faces.first.correctedImageBytes ?? bytes;
    final embeddings = await _mlService.getMultipleFaceEmbeddings(effectiveBytes, faces);

    final newlyMarked = <String>[];
    final alreadyPresent = <String>[];
    int unrecognizedCount = 0;

    for (int i = 0; i < embeddings.length; i++) {
      final emb = embeddings[i];
      final result = _mlService.recognizeFace(emb, allowedStudentIds: _allowedStudentIds);

      if (!result.accepted || result.studentId == null) {
        unrecognizedCount++;
        continue;
      }

      Student? student;
      final parsedId = int.tryParse(result.studentId!);
      if (parsedId != null) {
        student = _enrolledStudents.where((s) => s.id == parsedId).firstOrNull;
      }
      student ??= _enrolledStudents.where(
        (s) => s.registerNumber.trim().toLowerCase() == result.studentId!.trim().toLowerCase(),
      ).firstOrNull;
      student ??= _enrolledStudents.where(
        (s) => s.name.trim().toLowerCase() == result.name.trim().toLowerCase(),
      ).firstOrNull;

      if (student == null) {
        if (parsedId != null) {
          student = await _studentRepo.getStudentById(parsedId);
        }
        student ??= await _studentRepo.getStudentByRegisterNumber(result.studentId!);
      }

      if (student == null || student.id == null) {
        unrecognizedCount++;
        continue;
      }

      if (!_enrolledStudentIds.contains(student.id!)) {
        continue;
      }

      if (_presentStudentIds.contains(student.id!)) {
        if (!alreadyPresent.contains(student.name)) {
          alreadyPresent.add(student.name);
        }
        continue;
      }

      final markResult = await _attendanceService.markStudentPresent(
        sessionId: widget.session.id!,
        studentId: student.id!,
      );

      if (markResult == MarkAttendanceResult.markedPresent || markResult == MarkAttendanceResult.alreadyPresent) {
        _presentStudentIds.add(student.id!);
        newlyMarked.add(student.name);
      }
    }

    if (newlyMarked.isNotEmpty) {
      await _loadClassAndRecords();
    }

    if (mounted) {
      setState(() {
        _countdown = kCaptureIntervalSeconds;
        if (newlyMarked.isNotEmpty) {
          final count = newlyMarked.length;
          final names = count <= 2
              ? newlyMarked.join(", ")
              : "${newlyMarked.take(2).join(', ')} +${count - 2} more";
          _statusMessage = "✓ Marked $count present: $names";
          _feedbackColor = AppColors.present;
        } else if (alreadyPresent.isNotEmpty) {
          final count = alreadyPresent.length;
          _statusMessage = "✓ $count student(s) already marked present";
          _feedbackColor = AppColors.warning;
        } else if (unrecognizedCount > 0) {
          _statusMessage = "$unrecognizedCount student(s) not recognized in this class";
          _feedbackColor = AppColors.absent;
        }
      });
    }
  }

  Future<void> _handleRecognitionResult(RecognitionResult result) async {
    if (!result.accepted || result.studentId == null) {
      if (mounted) {
        setState(() {
          _statusMessage = "Face not recognized in this class";
          _feedbackColor = AppColors.absent;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    Student? student;
    final parsedId = int.tryParse(result.studentId!);
    if (parsedId != null) {
      student = _enrolledStudents.where((s) => s.id == parsedId).firstOrNull;
    }
    student ??= _enrolledStudents.where(
      (s) => s.registerNumber.trim().toLowerCase() == result.studentId!.trim().toLowerCase(),
    ).firstOrNull;
    student ??= _enrolledStudents.where(
      (s) => s.name.trim().toLowerCase() == result.name.trim().toLowerCase(),
    ).firstOrNull;

    if (student == null) {
      if (parsedId != null) {
        student = await _studentRepo.getStudentById(parsedId);
      }
      student ??= await _studentRepo.getStudentByRegisterNumber(result.studentId!);
    }

    if (student == null || student.id == null) {
      if (mounted) {
        setState(() {
          _statusMessage = "Recognized ${result.name}, record not found";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    final isEnrolled = _enrolledStudentIds.contains(student.id!);
    if (!isEnrolled) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student!.name} is not enrolled in this class";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    if (_presentStudentIds.contains(student.id!)) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student!.name} is already marked present";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    final markResult = await _attendanceService.markStudentPresent(
      sessionId: widget.session.id!,
      studentId: student.id!,
    );

    if (markResult == MarkAttendanceResult.markedPresent || markResult == MarkAttendanceResult.alreadyPresent) {
      _presentStudentIds.add(student.id!);
      await _loadClassAndRecords();

      if (mounted) {
        setState(() {
          _statusMessage = "✓ Marked Present: ${student!.name}";
          _feedbackColor = AppColors.present;
          _countdown = kCaptureIntervalSeconds;
        });
      }
    } else if (markResult == MarkAttendanceResult.studentNotInClass) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student!.name} is not enrolled in this class";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
    }
  }

  Future<void> _testFromPhoto() async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;

    final bytes = await xFile.readAsBytes();
    await _processImageBytes(bytes);
  }

  Future<void> _testDebugPiyushPhoto() async {
    try {
      final bytes = await _mlService.loadDebugPhotoBytes();
      await _processImageBytes(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.absent, content: Text("Debug photo error: $e")),
        );
      }
    }
  }

  Future<void> _confirmEndAttendance() async {
    final presentCount = _presentStudentIds.length;
    final totalCount = _records.length;
    final absentCount = totalCount - presentCount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainer,
          title: Text("End Attendance Session?", style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Class: ${widget.classModel.name}", style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text("$presentCount", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.present)),
                        const SizedBox(height: 2),
                        Text("Present", style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    Container(height: 30, width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    Column(
                      children: [
                        Text("$absentCount", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.absent)),
                        const SizedBox(height: 2),
                        Text("Absent", style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    Container(height: 30, width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    Column(
                      children: [
                        Text("$totalCount", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                        const SizedBox(height: 2),
                        Text("Total", style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Are you sure you want to complete this session? This will finalize the attendance records.",
                style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("Cancel", style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.absent,
                foregroundColor: Colors.white,
              ),
              child: const Text("End Session"),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _intervalTimer?.cancel();
      _cameraController?.dispose();
      _cameraController = null;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      await _attendanceService.completeSession(widget.session.id!);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceSummaryScreen(sessionId: widget.session.id!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape = _isEasyMode || MediaQuery.of(context).orientation == Orientation.landscape;
    final presentList = _records.where((r) => r.isPresent).toList();
    final absentList = _records.where((r) => r.isAbsent).toList();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.classModel.name,
              style: TextStyle(
                fontSize: isLandscape ? 15 : 17,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "${widget.session.attendanceDate} • ${widget.teacher.displayName}",
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          // Mode Toggle Chip (Single vs Classroom Mode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleMode,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isEasyMode
                        ? AppColors.present.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isEasyMode
                          ? AppColors.present.withValues(alpha: 0.6)
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isEasyMode ? Icons.groups_rounded : Icons.person_rounded,
                        size: 16,
                        color: _isEasyMode ? AppColors.present : colorScheme.onSurface,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isEasyMode ? "Classroom" : "Single",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isEasyMode ? AppColors.present : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Secondary options menu (keeps AppBar clean and prevents title truncation)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurface),
            tooltip: "More Options",
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: colorScheme.surfaceContainerHigh,
            onSelected: (val) {
              if (val == 'gallery') _testFromPhoto();
              if (val == 'debug') _testDebugPiyushPhoto();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'gallery',
                child: Row(
                  children: [
                    Icon(Icons.photo_library_outlined, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text("Scan Photo from Gallery", style: TextStyle(color: colorScheme.onSurface, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'debug',
                child: Row(
                  children: [
                    Icon(Icons.bug_report_outlined, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text("Test Debug Photo", style: TextStyle(color: colorScheme.onSurface, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: isLandscape
          ? _buildLandscapeLayout(presentList, absentList)
          : _buildPortraitLayout(presentList, absentList),
    );
  }

  /// Responsive Landscape Layout for Classroom / Easy Mode
  Widget _buildLandscapeLayout(List<AttendanceRecord> presentList, List<AttendanceRecord> absentList) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Left: Wide Camera Preview with Sleek Viewfinder
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 6, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  _buildCameraPreview(),
                  _buildViewfinderOverlay(isLandscape: true),
                  _buildFloatingShutterBadge(),
                  _buildUnifiedStatusCapsule(compact: true),
                ],
              ),
            ),
          ),
        ),

        // Right: Stats, Tabs, Live Student Lists, and Action Button
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  _buildAttendanceStatsCard(compact: true),
                  _buildTabBar(),
                  Expanded(
                    child: _buildTabBarView(presentList, absentList),
                  ),
                  _buildEndAttendanceButton(compact: true),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Standard Portrait Layout for Single Student Mode
  Widget _buildPortraitLayout(List<AttendanceRecord> presentList, List<AttendanceRecord> absentList) {
    return Column(
      children: [
        // Camera Preview Area
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  _buildCameraPreview(),
                  _buildViewfinderOverlay(isLandscape: false),
                  _buildFloatingShutterBadge(),
                  _buildUnifiedStatusCapsule(compact: false),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Attendance Progress & Stats
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildAttendanceStatsCard(compact: false),
        ),

        // Tab Bar & Live Student Lists
        _buildTabBar(),
        Expanded(
          flex: 4,
          child: _buildTabBarView(presentList, absentList),
        ),

        // Complete Attendance Action Button
        _buildEndAttendanceButton(compact: false),
      ],
    );
  }

  /// Camera Feed Preview with Proper Aspect Ratio
  Widget _buildCameraPreview() {
    if (_isControllerInitialized && _cameraController != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _cameraController!.value.previewSize?.height ?? 1,
              height: _cameraController!.value.previewSize?.width ?? 1,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),
      );
    }
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded, size: 44, color: Colors.white30),
            SizedBox(height: 8),
            Text("Camera initializing...", style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// Modern Sleek Viewfinder Reticle with Corner Brackets
  Widget _buildViewfinderOverlay({required bool isLandscape}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = isLandscape
            ? (constraints.maxWidth * 0.82).clamp(240.0, 520.0)
            : (constraints.maxWidth * 0.68).clamp(200.0, 280.0);
        final boxHeight = isLandscape
            ? (constraints.maxHeight * 0.72).clamp(180.0, 340.0)
            : (constraints.maxHeight * 0.68).clamp(220.0, 320.0);

        final frameColor = _isProcessing
            ? Theme.of(context).colorScheme.primary
            : (_isEasyMode
                ? AppColors.present.withValues(alpha: 0.8)
                : _feedbackColor.withValues(alpha: 0.8));

        return Center(
          child: CustomPaint(
            size: Size(boxWidth, boxHeight),
            painter: _CornerBracketPainter(
              color: frameColor,
              cornerLength: 28,
              strokeWidth: 3.0,
              borderRadius: 16,
            ),
          ),
        );
      },
    );
  }

  /// Floating Shutter & Countdown Badge (Top Right of Camera)
  Widget _buildFloatingShutterBadge() {
    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (_isCapturing || _isProcessing) ? null : _triggerScan,
          borderRadius: BorderRadius.circular(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isCapturing || _isProcessing) ...[
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "Scanning",
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ] else ...[
                      const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        "${_countdown}s",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Single Unified Status Capsule (Bottom of Camera with Glassmorphism)
  Widget _buildUnifiedStatusCapsule({required bool compact}) {
    return Positioned(
      bottom: compact ? 10 : 14,
      left: compact ? 12 : 20,
      right: compact ? 12 : 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 7 : 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _feedbackColor.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isProcessing || _isCapturing) ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (_feedbackColor == AppColors.present) ...[
                  const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.present),
                  const SizedBox(width: 8),
                ] else if (_feedbackColor == AppColors.warning) ...[
                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                ] else if (_feedbackColor == AppColors.absent) ...[
                  const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.absent),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _feedbackColor,
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Clean Attendance Progress Card (Eliminates redundant headers)
  Widget _buildAttendanceStatsCard({required bool compact}) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalCount = _records.length;
    final presentCount = _presentStudentIds.length;
    final absentCount = (totalCount - presentCount).clamp(0, totalCount);
    final percent = totalCount > 0 ? (presentCount / totalCount) : 0.0;

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Present Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.present.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.present.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.present),
                    const SizedBox(width: 4),
                    Text(
                      "$presentCount Present",
                      style: const TextStyle(
                        color: AppColors.present,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Absent Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Text(
                  "$absentCount Absent",
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),

              // Total & %
              Text(
                "${(percent * 100).toInt()}% • $totalCount total",
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 5,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.present),
            ),
          ),
        ],
      ),
    );
  }

  /// Clean TabBar
  Widget _buildTabBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final presentCount = _records.where((r) => r.isPresent).length;
    final absentCount = _records.where((r) => r.isAbsent).length;

    return TabBar(
      controller: _tabController,
      indicatorColor: colorScheme.primary,
      indicatorWeight: 2.5,
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.2),
      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      tabs: [
        Tab(text: "Present ($presentCount)"),
        Tab(text: "Absent ($absentCount)"),
      ],
    );
  }

  /// TabBarView with Refined Student Tiles and Empty States
  Widget _buildTabBarView(List<AttendanceRecord> presentList, List<AttendanceRecord> absentList) {
    final colorScheme = Theme.of(context).colorScheme;

    return TabBarView(
      controller: _tabController,
      children: [
        // Present List
        presentList.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.how_to_reg_outlined,
                        size: 40,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "No students marked present yet",
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Point the camera at students to mark attendance",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: presentList.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                ),
                itemBuilder: (_, i) {
                  final r = presentList[i];
                  final initial = r.studentName.isNotEmpty ? r.studentName[0].toUpperCase() : "?";
                  final timeStr = r.attendanceTime != null && r.attendanceTime!.length >= 16
                      ? r.attendanceTime!.substring(11, 16)
                      : "";

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.present.withValues(alpha: 0.15),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: AppColors.present,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                      r.studentName,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      r.studentRegisterNumber,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (timeStr.isNotEmpty)
                          Text(
                            timeStr,
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle_rounded, color: AppColors.present, size: 18),
                      ],
                    ),
                  );
                },
              ),

        // Absent List
        absentList.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.celebration_rounded, size: 40, color: AppColors.present),
                      const SizedBox(height: 10),
                      const Text(
                        "All students marked present!",
                        style: TextStyle(
                          color: AppColors.present,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: absentList.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                ),
                itemBuilder: (_, i) {
                  final r = absentList[i];
                  final initial = r.studentName.isNotEmpty ? r.studentName[0].toUpperCase() : "?";

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                      r.studentName,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      r.studentRegisterNumber,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.absent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.absent.withValues(alpha: 0.25)),
                      ),
                      child: const Text(
                        "Absent",
                        style: TextStyle(
                          color: AppColors.absent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }

  /// Refined End Attendance Button (Replaces the aggressive red bar)
  Widget _buildEndAttendanceButton({required bool compact}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.all(compact ? 8.0 : 16.0),
      child: FilledButton.icon(
        onPressed: _confirmEndAttendance,
        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
        label: const Text(
          "Complete Session",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: Size.fromHeight(compact ? 42 : 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }
}

/// Custom painter for sleek corner-bracket camera viewfinder
class _CornerBracketPainter extends CustomPainter {
  final Color color;
  final double cornerLength;
  final double strokeWidth;
  final double borderRadius;

  _CornerBracketPainter({
    required this.color,
    required this.cornerLength,
    required this.strokeWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final cl = cornerLength;
    final r = borderRadius;

    // Top-Left Corner
    final tlPath = Path()
      ..moveTo(0, cl)
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(cl, 0);
    canvas.drawPath(tlPath, paint);

    // Top-Right Corner
    final trPath = Path()
      ..moveTo(w - cl, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, cl);
    canvas.drawPath(trPath, paint);

    // Bottom-Left Corner
    final blPath = Path()
      ..moveTo(0, h - cl)
      ..lineTo(0, h - r)
      ..arcToPoint(Offset(r, h), radius: Radius.circular(r))
      ..lineTo(cl, h);
    canvas.drawPath(blPath, paint);

    // Bottom-Right Corner
    final brPath = Path()
      ..moveTo(w - cl, h)
      ..lineTo(w - r, h)
      ..arcToPoint(Offset(w, h - r), radius: Radius.circular(r))
      ..lineTo(w, h - cl);
    canvas.drawPath(brPath, paint);
  }

  @override
  bool shouldRepaint(_CornerBracketPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.cornerLength != cornerLength ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}
