import 'package:dynamic_color/dynamic_color.dart';
import 'package:face_att/database/app_database.dart';
import 'package:face_att/database/repositories/class_repository.dart';
import 'package:face_att/pages/classes/create_class_screen.dart';
import 'package:face_att/pages/home_screen.dart';
import 'package:face_att/pages/settings/model_setup_screen.dart';
import 'package:face_att/services/camera_service.dart';
import 'package:face_att/services/face_recognition/model_manager_service.dart';
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

  final hasModel = await ModelManagerService.instance.hasAnyModelAvailable();
  final classes = await ClassRepository().getAllClasses();
  final hasClasses = classes.isNotEmpty;

  runApp(MyApp(hasClasses: hasClasses, hasModel: hasModel));
}

class MyApp extends StatelessWidget {
  final bool hasClasses;
  final bool hasModel;
  const MyApp({super.key, this.hasClasses = false, this.hasModel = true});

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
              home: !hasModel
                  ? ModelSetupScreen(
                      isFirstRun: true,
                      hasClasses: hasClasses,
                    )
                  : (hasClasses
                      ? const HomeScreen()
                      : const CreateClassScreen(isFirstRun: true)),
            );
          },
        );
      },
    );
  }
}
