import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_att/database/repositories/attendance_record_repository.dart';
import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/attendance_record.dart';
import 'package:face_att/models/attendance_session.dart';
import 'package:face_att/models/class_model.dart';
import 'package:face_att/models/student.dart';
import 'package:face_att/models/teacher.dart';
import 'package:face_att/pages/attendance/attendance_summary_screen.dart';
import 'package:face_att/pages/attendance/widgets/attendance_stats_card.dart';
import 'package:face_att/pages/attendance/widgets/end_attendance_dialog.dart';
import 'package:face_att/pages/attendance/widgets/scanner_app_bar_actions.dart';
import 'package:face_att/pages/attendance/widgets/scanner_camera_view.dart';
import 'package:face_att/pages/attendance/widgets/scanner_hud_overlay.dart';
import 'package:face_att/pages/attendance/widgets/scanner_student_tabs.dart';
import 'package:face_att/services/camera_service.dart';
import 'package:face_att/services/face_recognition/liveness_service.dart';
import 'package:face_att/services/face_recognition/ml_service.dart';
import 'package:face_att/services/face_recognition/spoof_guard.dart';
import 'package:face_att/services/face_recognition/student_recognition_resolver.dart';
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
    await CameraProvider.initialize();

    final camera = CameraProvider.frontCamera;
    if (camera == null) {
      if (mounted) {
        setState(() {
          _statusMessage = "No camera hardware detected";
        });
      }
      return;
    }

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

      final student = await StudentRecognitionResolver.resolveStudentForResult(
        result: result,
        enrolledStudents: _enrolledStudents,
        studentRepo: _studentRepo,
      );

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

    final student = await StudentRecognitionResolver.resolveStudentForResult(
      result: result,
      enrolledStudents: _enrolledStudents,
      studentRepo: _studentRepo,
    );

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
          _statusMessage = "${student.name} is not enrolled in this class";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    if (_presentStudentIds.contains(student.id!)) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student.name} is already marked present";
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
          _statusMessage = "✓ Marked Present: ${student.name}";
          _feedbackColor = AppColors.present;
          _countdown = kCaptureIntervalSeconds;
        });
      }
    } else if (markResult == MarkAttendanceResult.studentNotInClass) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student.name} is not enrolled in this class";
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
    final confirmed = await EndAttendanceDialog.show(
      context,
      className: widget.classModel.name,
      presentCount: _presentStudentIds.length,
      totalCount: _records.length,
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
          ScannerAppBarActions(
            isClassroomMode: _isEasyMode,
            onToggleMode: _toggleMode,
            onScanFromGallery: _testFromPhoto,
            onTestDebugPhoto: _testDebugPiyushPhoto,
          ),
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
                  ScannerHudOverlay(
                    isLandscape: true,
                    isProcessing: _isProcessing,
                    isCapturing: _isCapturing,
                    isEasyMode: _isEasyMode,
                    countdown: _countdown,
                    statusMessage: _statusMessage,
                    feedbackColor: _feedbackColor,
                    onTriggerScan: _triggerScan,
                    compact: true,
                  ),
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
                  AttendanceStatsCard(
                    totalCount: _records.length,
                    presentCount: _presentStudentIds.length,
                    compact: true,
                  ),
                  Expanded(
                    child: ScannerStudentTabs(
                      tabController: _tabController,
                      presentList: presentList,
                      absentList: absentList,
                    ),
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
                  ScannerHudOverlay(
                    isLandscape: false,
                    isProcessing: _isProcessing,
                    isCapturing: _isCapturing,
                    isEasyMode: _isEasyMode,
                    countdown: _countdown,
                    statusMessage: _statusMessage,
                    feedbackColor: _feedbackColor,
                    onTriggerScan: _triggerScan,
                    compact: false,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Attendance Progress & Stats
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AttendanceStatsCard(
            totalCount: _records.length,
            presentCount: _presentStudentIds.length,
            compact: false,
          ),
        ),

        // Tab Bar & Live Student Lists
        Expanded(
          flex: 4,
          child: ScannerStudentTabs(
            tabController: _tabController,
            presentList: presentList,
            absentList: absentList,
          ),
        ),

        // Complete Attendance Action Button
        _buildEndAttendanceButton(compact: false),
      ],
    );
  }

  /// Camera Feed Preview with Proper Aspect Ratio
  Widget _buildCameraPreview() {
    return ScannerCameraView(
      controller: _cameraController,
      isInitialized: _isControllerInitialized,
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
