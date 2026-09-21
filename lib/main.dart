import 'package:dynamic_color/dynamic_color.dart';
import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/pages/classes/create_class_screen.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:face_att/services/camera_service.dart';
import 'package:face_att/services/theme_service.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await CameraProvider.initialize();

  await Hive.initFlutter();
  await HiveBoxes.initialize();
  await AppDatabase.instance.database;

  ThemeService().init();

  final classes = await ClassRepository().getAllClasses();
  final hasClasses = classes.isNotEmpty;

  runApp(MyApp(hasClasses: hasClasses));
}

class MyApp extends StatelessWidget {
  final bool hasClasses;
  const MyApp({super.key, this.hasClasses = false});

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeService();

    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final lightTheme = themeService.buildLightTheme(lightDynamic);
            final darkTheme = themeService.buildDarkTheme(darkDynamic);

            return MaterialApp(
              title: 'Face Attendance',
              debugShowCheckedModeBanner: false,
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: themeService.flutterThemeMode,
              home: hasClasses
                  ? const HomeScreen()
                  : const CreateClassScreen(isFirstRun: true),
            );
          },
        );
      },
    );
  }
}
