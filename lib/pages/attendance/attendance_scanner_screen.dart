import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

class _AttendanceScannerScreenState extends State<AttendanceScannerScreen> with TickerProviderStateMixin {
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

  int _countdown = kCaptureIntervalSeconds;
  Timer? _intervalTimer;

  // In-memory protection against duplicate attendance writes
  final Set<int> _presentStudentIds = {};
  Set<int> _enrolledStudentIds = {};
  List<Student> _enrolledStudents = [];
  Set<String> _allowedStudentIds = {};
  List<AttendanceRecord> _records = [];

  String _statusMessage = "Position student face in frame";
  Color _feedbackColor = Colors.white70;

  late TabController _tabController;
  late AnimationController _scanPulseController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scanPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scanAnimation = CurvedAnimation(
      parent: _scanPulseController,
      curve: Curves.easeInOut,
    );
    _loadClassAndRecords();
    _initializeCamera();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _intervalTimer?.cancel();
    _scanPulseController.dispose();
    _cameraController?.dispose();
    _cameraController = null;
    _tabController.dispose();
    super.dispose();
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
          _statusMessage = "No camera hardware detected (use Photo Test button below)";
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
          _statusMessage = "Camera initialization failed: $e";
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
          _statusMessage = "Scanning in ${_countdown}s...";
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
      _statusMessage = "Capturing photo for face verification...";
      _feedbackColor = Colors.cyanAccent;
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
          _feedbackColor = Colors.orangeAccent;
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
      _statusMessage = "Analyzing face with ArcFace...";
      _feedbackColor = AppColors.primaryLight;
    });

    try {
      if (_enrolledStudents.isEmpty) {
        if (mounted) {
          setState(() {
            _statusMessage = "No students enrolled in this class. Enroll students first.";
            _feedbackColor = AppColors.warning;
            _countdown = kCaptureIntervalSeconds;
          });
        }
        return;
      }

      final faceData = await _mlService.detectFaceOnImageBytes(
        bytes,
        sensorOrientation: _cameraController?.description.sensorOrientation,
      );
      if (faceData == null) {
        if (mounted) {
          setState(() {
            _statusMessage = "No face detected • Position face inside frame";
            _feedbackColor = AppColors.textSecondary;
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
              _statusMessage = "Spoof alert: $spoofWarning";
              _feedbackColor = AppColors.warning;
              _countdown = kCaptureIntervalSeconds;
            });
          }
          return;
        }
        _livenessService.process(faceData.mlKitFace!);
      }

      // 5-point landmark aligned ArcFace embedding (512-dim) via background isolate
      final effectiveBytes = faceData.correctedImageBytes ?? bytes;
      final embedding = await _mlService.getEmbeddingFromImageBytes(
        effectiveBytes,
        boundingBox: faceData.boundingBox,
        landmarks: faceData.landmarks,
      );

      // Perform InsightFace recognition MATCHING ONLY CANDIDATES IN THIS CLASS!
      final result = _mlService.recognizeFace(
        embedding,
        allowedStudentIds: _allowedStudentIds,
      );
      await _handleRecognitionResult(result);
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

  Future<void> _handleRecognitionResult(RecognitionResult result) async {
    if (!result.accepted || result.studentId == null) {
      if (mounted) {
        setState(() {
          _statusMessage = "Face not recognized for ${widget.classModel.name}";
          _feedbackColor = AppColors.absent;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    // Lookup student in this class's enrolled students list first
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

    // Fallback: check repository if not found in list
    if (student == null) {
      if (parsedId != null) {
        student = await _studentRepo.getStudentById(parsedId);
      }
      student ??= await _studentRepo.getStudentByRegisterNumber(result.studentId!);
    }

    if (student == null || student.id == null) {
      if (mounted) {
        setState(() {
          _statusMessage = "Recognized ${result.name}, but record not found";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    // 1. Verify student is enrolled in the selected class
    final isEnrolled = _enrolledStudentIds.contains(student.id!);
    if (!isEnrolled) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student!.name} is not enrolled in ${widget.classModel.name}";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    // 2. Check if already marked present (In-memory duplicate protection)
    if (_presentStudentIds.contains(student.id!)) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student!.name} is already marked present.";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
      return;
    }

    // 3. Mark present via AttendanceService
    final markResult = await _attendanceService.markStudentPresent(
      sessionId: widget.session.id!,
      studentId: student.id!,
    );

    if (markResult == MarkAttendanceResult.markedPresent || markResult == MarkAttendanceResult.alreadyPresent) {
      _presentStudentIds.add(student.id!);
      await _loadClassAndRecords();

      if (mounted) {
        setState(() {
          _statusMessage = "✓ Marked Present: ${student!.name} (${student.registerNumber})";
          _feedbackColor = AppColors.present;
          _countdown = kCaptureIntervalSeconds;
        });
      }
    } else if (markResult == MarkAttendanceResult.studentNotInClass) {
      if (mounted) {
        setState(() {
          _statusMessage = "${student!.name} is not enrolled in this class.";
          _feedbackColor = AppColors.warning;
          _countdown = kCaptureIntervalSeconds;
        });
      }
    }
  }

  /// Photo test fallback (e.g. from file or debug photo)
  Future<void> _testFromPhoto() async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;

    final bytes = await xFile.readAsBytes();
    await _processImageBytes(bytes);
  }

  /// Direct debug photo scan for 23BRS1150_PIYUSH_R_SAINI.jpeg
  Future<void> _testDebugPiyushPhoto() async {
    try {
      final bytes = await _mlService.loadDebugPhotoBytes();
      await _processImageBytes(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.redAccent, content: Text("Debug photo error: $e")),
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
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text("End Attendance?", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Class: ${widget.classModel.name}", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Text("Present: $presentCount / $totalCount", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            Text("Absent: $absentCount / $totalCount", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text("Are you sure you want to end this attendance session?", style: TextStyle(color: Colors.white54)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text("End Attendance"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 1. Stop timers
      _intervalTimer?.cancel();
      // 2. Dispose camera
      _cameraController?.dispose();
      _cameraController = null;
      // 3. Complete session
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
    final presentList = _records.where((r) => r.isPresent).toList();
    final absentList = _records.where((r) => r.isAbsent).toList();

    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text("Attendance Scanner"),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library, color: AppColors.primaryLight),
            tooltip: "Scan Photo from Gallery",
            onPressed: _testFromPhoto,
          ),
          IconButton(
            icon: const Icon(Icons.bug_report, color: AppColors.accentCyan),
            tooltip: "Test 23BRS1150 Debug Photo",
            onPressed: _testDebugPiyushPhoto,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: AppColors.navySurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.classModel.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      "${widget.session.attendanceDate} • ${widget.teacher.displayName}",
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    "Present: ${_presentStudentIds.length} / ${_records.length}",
                    style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

          // Camera Frame / Preview
          Expanded(
            flex: 5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isControllerInitialized && _cameraController != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: _cameraController!.value.aspectRatio,
                      child: CameraPreview(_cameraController!),
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_off, size: 48, color: Colors.white30),
                          SizedBox(height: 8),
                          Text("Camera not active", style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  ),

                // Face Oval Overlay Guide with Smooth 60FPS Scanning Laser Animation
                AnimatedBuilder(
                  animation: _scanAnimation,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 220,
                          height: 290,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(Radius.elliptical(220, 290)),
                            border: Border.all(
                              color: _isProcessing
                                  ? Colors.cyanAccent
                                  : Colors.greenAccent.withValues(alpha: 0.5 + 0.3 * _scanAnimation.value),
                              width: _isProcessing ? 3.0 : 2.5,
                            ),
                          ),
                        ),
                        // Smooth animated laser scanning line
                        ClipOval(
                          child: SizedBox(
                            width: 218,
                            height: 288,
                            child: Stack(
                              children: [
                                Positioned(
                                  top: _scanAnimation.value * 270,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 3,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          _isProcessing ? Colors.cyanAccent : Colors.greenAccent,
                                          Colors.transparent,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_isProcessing ? Colors.cyanAccent : Colors.greenAccent).withValues(alpha: 0.8),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                // Live status banner overlay at bottom of camera with fluid spinner
                Positioned(
                  bottom: 16,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _feedbackColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isProcessing || _isCapturing) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _feedbackColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),


          // Tabs: Present | Absent
          Container(
            color: AppColors.navySurface,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: [
                Tab(text: "Present (${presentList.length})"),
                Tab(text: "Absent (${absentList.length})"),
              ],
            ),
          ),

          // Live Lists
          Expanded(
            flex: 4,
            child: TabBarView(
              controller: _tabController,
              children: [
                // Present List
                presentList.isEmpty
                    ? const Center(child: Text("No students marked present yet", style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        itemCount: presentList.length,
                        itemBuilder: (_, i) {
                          final r = presentList[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                            title: Text(r.studentName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text(r.studentRegisterNumber, style: const TextStyle(color: Colors.white54)),
                            trailing: Text(
                              r.attendanceTime != null ? r.attendanceTime!.substring(11, 19) : "",
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          );
                        },
                      ),

                // Absent List
                absentList.isEmpty
                    ? const Center(child: Text("All students present!", style: TextStyle(color: Colors.greenAccent)))
                    : ListView.builder(
                        itemCount: absentList.length,
                        itemBuilder: (_, i) {
                          final r = absentList[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.radio_button_unchecked, color: Colors.redAccent, size: 20),
                            title: Text(r.studentName, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(r.studentRegisterNumber, style: const TextStyle(color: Colors.white54)),
                            trailing: const Text("Absent", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                          );
                        },
                      ),
              ],
            ),
          ),

          // Bottom End Attendance button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _confirmEndAttendance,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text("End Attendance", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
