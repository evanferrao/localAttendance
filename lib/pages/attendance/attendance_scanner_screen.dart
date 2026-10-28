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

class _AttendanceScannerScreenState extends State<AttendanceScannerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  bool _isLoadingPhoto = false;
  bool _isDisposed = false;

  /// Mode: false = Single Mode (Portrait, 1 student)
  ///       true = Classroom Mode (Landscape, identifies multiple students)
  bool _isEasyMode = false;
  bool _showStudentListInLandscape = false;

  int _countdown = kCaptureIntervalSeconds;
  Timer? _intervalTimer;

  // In-memory tracking
  final Set<String> _presentRegisterNumbers = {};
  Set<String> _enrolledRegisterNumbers = {};
  List<Student> _enrolledStudents = [];
  List<AttendanceRecord> _records = [];

  String _statusMessage = "Position face inside frame";
  Color _feedbackColor = Colors.white70;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _loadClassAndRecords();
    _initializeCamera();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || !mounted) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Pause periodic timer when app is paused or when an external intent (like gallery) opens
      _intervalTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (!_isProcessing && !_isCapturing && !_isLoadingPhoto) {
        _startCountdownLoop();
      }
    }
  }

  /// Toggle between Single Mode (Portrait) and Classroom Mode (Landscape Multi-Student)
  Future<void> _toggleMode() async {
    if (_isCapturing || _isProcessing || _isLoadingPhoto) return;

    final newMode = !_isEasyMode;
    setState(() {
      _isEasyMode = newMode;
      _showStudentListInLandscape = false;
      _isControllerInitialized = false;
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

    // Switch camera: Multiple student mode uses back camera; single mode uses front camera
    await _initializeCamera(useBackCamera: newMode);
  }

  /// Flip camera manually between front and back
  Future<void> _flipCamera() async {
    if (_isCapturing || _isProcessing || _isLoadingPhoto || _cameraController == null) return;
    final currentDirection = _cameraController!.description.lensDirection;
    final wantBackCamera = currentDirection != CameraLensDirection.back;

    setState(() {
      _isControllerInitialized = false;
    });

    await _initializeCamera(useBackCamera: wantBackCamera);
  }

  Future<void> _loadClassAndRecords() async {
    final records = await _recordRepo.getRecordsForSession(widget.session.id!);
    final presentRegNos = await _recordRepo.getPresentRegisterNumbers(widget.session.id!);
    final enrolledStudents = await _studentRepo.getStudentsForClass(widget.classModel.id!);

    final allowedRegNos = <String>{};
    for (final s in enrolledStudents) {
      if (s.registerNumber.isNotEmpty) {
        allowedRegNos.add(s.registerNumber.trim().toUpperCase());
      }
    }

    if (mounted) {
      setState(() {
        _records = records;
        _presentRegisterNumbers.clear();
        _presentRegisterNumbers.addAll(presentRegNos.map((r) => r.trim().toUpperCase()));
        _enrolledStudents = enrolledStudents;
        _enrolledRegisterNumbers = enrolledStudents.map((s) => s.registerNumber.trim().toUpperCase()).toSet();
      });
    }
  }

  Future<void> _initializeCamera({bool? useBackCamera}) async {
    await CameraProvider.initialize();

    final wantBackCamera = useBackCamera ?? _isEasyMode;
    final camera = CameraProvider.cameraForMode(isMultipleStudentMode: wantBackCamera);
    if (camera == null) {
      if (mounted) {
        setState(() {
          _statusMessage = "No camera hardware detected";
        });
      }
      return;
    }

    // Dispose old controller before initializing a new one
    final oldController = _cameraController;
    _cameraController = null;
    if (oldController != null) {
      await oldController.dispose();
    }

    final newController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await newController.initialize();
      await newController.setFlashMode(FlashMode.off);

      if (_isDisposed || !mounted) {
        await newController.dispose();
        return;
      }
      setState(() {
        _cameraController = newController;
        _isControllerInitialized = true;
      });

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
      if (_isCapturing || _isProcessing || _isLoadingPhoto) return;

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
    if (_isCapturing || _isProcessing || _isLoadingPhoto || !_isControllerInitialized || _cameraController == null) return;
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

  Future<void> _processImageBytes(Uint8List bytes, {bool isStaticImage = false}) async {
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
        await _processEasyModeBatch(bytes, isStaticImage: isStaticImage);
      } else {
        await _processNormalModeSingle(bytes, isStaticImage: isStaticImage);
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
  Future<void> _processNormalModeSingle(Uint8List bytes, {bool isStaticImage = false}) async {
    final faceData = await _mlService.detectFaceOnImageBytes(
      bytes,
      sensorOrientation: isStaticImage ? null : _cameraController?.description.sensorOrientation,
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

    // Check Anti-Spoofing and Liveness if mlKitFace is available (only for live camera frames)
    if (!isStaticImage && faceData.mlKitFace != null) {
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
      allowedRegisterNumbers: _enrolledRegisterNumbers,
    );
    await _handleRecognitionResult(result);
  }

  /// Classroom Mode: Identifies multiple students simultaneously
  Future<void> _processEasyModeBatch(Uint8List bytes, {bool isStaticImage = false}) async {
    final faces = await _mlService.detectAllFacesOnImageBytes(
      bytes,
      sensorOrientation: isStaticImage ? null : _cameraController?.description.sensorOrientation,
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
      final result = _mlService.recognizeFace(
        emb,
        allowedRegisterNumbers: _enrolledRegisterNumbers,
      );

      if (!result.accepted || result.registerNumber == null) {
        unrecognizedCount++;
        continue;
      }

      final student = await StudentRecognitionResolver.resolveStudentForResult(
        result: result,
        enrolledStudents: _enrolledStudents,
        studentRepo: _studentRepo,
      );

      if (student == null) {
        unrecognizedCount++;
        continue;
      }

      final reg = student.registerNumber.trim().toUpperCase();
      if (!_enrolledRegisterNumbers.contains(reg)) {
        continue;
      }

      if (_presentRegisterNumbers.contains(reg)) {
        if (!alreadyPresent.contains(student.displayName)) {
          alreadyPresent.add(student.displayName);
        }
        continue;
      }

      final markResult = await _attendanceService.markStudentPresent(
        sessionId: widget.session.id!,
        registerNumber: student.registerNumber,
      );

      if (markResult == MarkAttendanceResult.markedPresent || markResult == MarkAttendanceResult.alreadyPresent) {
        _presentRegisterNumbers.add(reg);
        newlyMarked.add(student.displayName);
      }
    }

    if (newlyMarked.isNotEmpty) {
      await _loadClassAndRecords();
    }

    if (mounted) {
      setState(() {
        _countdown = kCaptureIntervalSeconds;
        final totalFaces = faces.length;
        if (newlyMarked.isNotEmpty) {
          final count = newlyMarked.length;
          final names = count <= 2
              ? newlyMarked.join(", ")
              : "${newlyMarked.take(2).join(', ')} +${count - 2} more";
          _statusMessage = "$totalFaces face(s) • Marked $count: $names";
          _feedbackColor = AppColors.present;
        } else if (alreadyPresent.isNotEmpty) {
          final count = alreadyPresent.length;
          _statusMessage = "$totalFaces face(s) • $count student(s) already marked present";
          _feedbackColor = AppColors.warning;
        } else if (unrecognizedCount > 0) {
          _statusMessage = "$totalFaces face(s) detected • $unrecognizedCount not recognized";
          _feedbackColor = AppColors.absent;
        }
      });
    }
  }

  Future<void> _handleRecognitionResult(RecognitionResult result) async {
    if (!result.accepted || result.registerNumber == null) {
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

    if (student == null) {
      if (mounted) {
        setState(() {
          _statusMessage = "Recognized ${result.name}, record not found";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    final reg = student.registerNumber.trim().toUpperCase();
    final isEnrolled = _enrolledRegisterNumbers.contains(reg);
    if (!isEnrolled) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student.displayName} is not enrolled in this class";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    if (_presentRegisterNumbers.contains(reg)) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student.displayName} is already marked present";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    final markResult = await _attendanceService.markStudentPresent(
      sessionId: widget.session.id!,
      registerNumber: student.registerNumber,
    );

    if (markResult == MarkAttendanceResult.markedPresent || markResult == MarkAttendanceResult.alreadyPresent) {
      _presentRegisterNumbers.add(reg);
      await _loadClassAndRecords();

      if (mounted) {
        setState(() {
          _statusMessage = "Marked Present: ${student.displayName}";
          _feedbackColor = AppColors.present;
          _countdown = kCaptureIntervalSeconds;
        });
      }
    } else if (markResult == MarkAttendanceResult.studentNotInClass) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student.displayName} is not enrolled in this class";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
    }
  }

  Future<void> _testFromPhoto() async {
    if (_isLoadingPhoto) return;
    _intervalTimer?.cancel();

    // If camera capture or verification is currently in flight, wait for it to cleanly complete
    // so no hardware or model contention occurs
    if (_isCapturing || _isProcessing) {
      if (mounted) {
        setState(() {
          _statusMessage = "Finishing current scan before loading photo...";
        });
      }
      while ((_isCapturing || _isProcessing) && mounted && !_isDisposed) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (_isDisposed || !mounted) return;

    setState(() {
      _isLoadingPhoto = true;
      _statusMessage = "Select a student photo from gallery";
    });

    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );

      if (_isDisposed || !mounted) return;

      if (xFile == null) {
        if (mounted) {
          setState(() {
            _statusMessage = _isEasyMode
                ? "Classroom Mode • Scanning multiple students..."
                : "Single Mode • Position student face in frame";
            _feedbackColor = _isEasyMode ? AppColors.present : Colors.white70;
          });
        }
        return;
      }

      final bytes = await xFile.readAsBytes();
      if (_isDisposed || !mounted) return;

      await _processImageBytes(bytes, isStaticImage: true);
    } catch (e) {
      debugPrint("Photo load error: $e");
      if (mounted) {
        setState(() {
          _statusMessage = "Could not load photo: $e";
          _feedbackColor = AppColors.absent;
        });
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() {
          _isLoadingPhoto = false;
        });
        _startCountdownLoop();
      }
    }
  }

  Future<void> _testDebugPiyushPhoto() async {
    if (_isLoadingPhoto) return;
    _intervalTimer?.cancel();

    if (_isCapturing || _isProcessing) {
      while ((_isCapturing || _isProcessing) && mounted && !_isDisposed) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (_isDisposed || !mounted) return;

    setState(() {
      _isLoadingPhoto = true;
      _statusMessage = "Loading debug test photo...";
    });

    try {
      final bytes = await _mlService.loadDebugPhotoBytes();
      if (_isDisposed || !mounted) return;
      await _processImageBytes(bytes, isStaticImage: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.absent, content: Text("Debug photo error: $e")),
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() {
          _isLoadingPhoto = false;
        });
        _startCountdownLoop();
      }
    }
  }

  Future<void> _confirmEndAttendance() async {
    final confirmed = await EndAttendanceDialog.show(
      context,
      className: widget.classModel.name,
      presentCount: _presentRegisterNumbers.length,
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
            onFlipCamera: _flipCamera,
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

  /// Responsive Landscape Layout for Classroom / Easy Mode (Uses the Entire Camera)
  Widget _buildLandscapeLayout(List<AttendanceRecord> presentList, List<AttendanceRecord> absentList) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Camera Viewfinder Area: Takes full screen when list is hidden, or dominant 7-flex when list is open
        Expanded(
          flex: _showStudentListInLandscape ? 7 : 1,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // 1. Full camera preview with correct aspect ratio
              Positioned.fill(
                child: _buildCameraPreview(fit: BoxFit.contain),
              ),

              // 2. HUD Overlay (Corner brackets reticle, shutter badge, unified status capsule)
              Positioned.fill(
                child: ScannerHudOverlay(
                  isLandscape: true,
                  isProcessing: _isProcessing || _isLoadingPhoto,
                  isCapturing: _isCapturing,
                  isEasyMode: _isEasyMode,
                  countdown: _countdown,
                  statusMessage: _statusMessage,
                  feedbackColor: _feedbackColor,
                  onTriggerScan: _triggerScan,
                  compact: true,
                ),
              ),

              // 3. Floating Quick Stats & Drawer Opener (when student list is collapsed)
              if (!_showStudentListInLandscape)
                Positioned(
                  top: 12,
                  left: 14,
                  child: _buildFloatingStatsPill(),
                ),

              // 4. Floating Complete Button (when student list is collapsed)
              if (!_showStudentListInLandscape)
                Positioned(
                  top: 12,
                  left: 170,
                  child: _buildFloatingCompleteButton(),
                ),
            ],
          ),
        ),

        // Slide-in Student List Panel
        if (_showStudentListInLandscape)
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 12, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    // Header with Close / Fullscreen button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Attendance List",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.fullscreen_rounded, size: 20),
                            tooltip: "Full Camera View",
                            onPressed: () {
                              setState(() {
                                _showStudentListInLandscape = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    AttendanceStatsCard(
                      totalCount: _records.length,
                      presentCount: _presentRegisterNumbers.length,
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

  /// Floating Stats Pill in Landscape Mode
  Widget _buildFloatingStatsPill() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _showStudentListInLandscape = true;
          });
        },
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_alt_rounded, size: 14, color: AppColors.present),
                  const SizedBox(width: 5),
                  Text(
                    "${_presentRegisterNumbers.length}/${_records.length} Present",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Floating Complete Button in Landscape Mode
  Widget _buildFloatingCompleteButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _confirmEndAttendance,
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    "Complete",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
                  _buildCameraPreview(fit: BoxFit.cover),
                  ScannerHudOverlay(
                    isLandscape: false,
                    isProcessing: _isProcessing || _isLoadingPhoto,
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
            presentCount: _presentRegisterNumbers.length,
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

  /// Camera Feed Preview with Proper Aspect Ratio and BoxFit
  Widget _buildCameraPreview({BoxFit fit = BoxFit.contain}) {
    return ScannerCameraView(
      controller: _cameraController,
      isInitialized: _isControllerInitialized,
      fit: fit,
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
