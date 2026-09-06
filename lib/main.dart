import 'package:camera/camera.dart';
import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/pages/classes/create_class_screen.dart';
import 'package:face_att/pages/face_recognition/camera_screen.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (_) {}

  await Hive.initFlutter();
  await HiveBoxes.initialize();
  await AppDatabase.instance.database;

  final classes = await ClassRepository().getAllClasses();
  final hasClasses = classes.isNotEmpty;

  runApp(MyApp(hasClasses: hasClasses));
}

class MyApp extends StatelessWidget {
  final bool hasClasses;
  const MyApp({super.key, this.hasClasses = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.navyBackground,
        primaryColor: AppColors.primary,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryDark,
          primary: AppColors.primary,
          surface: AppColors.navySurface,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: hasClasses
          ? const HomeScreen()
          : const CreateClassScreen(isFirstRun: true),
    );
  }
}
