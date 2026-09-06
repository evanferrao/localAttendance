import 'package:face_att/database/database_schema.dart';
import 'package:face_att/services/teacher_auth_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  /// Allow injecting a database directly (useful in unit/integration tests with sqflite_common_ffi)
  void setDatabaseForTesting(Database db) {
    _db = db;
  }

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    String dbPath;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      dbPath = p.join(docDir.path, DatabaseSchema.databaseName);
    } catch (_) {
      final defaultDir = await getDatabasesPath();
      dbPath = p.join(defaultDir, DatabaseSchema.databaseName);
    }

    return await openDatabase(
      dbPath,
      version: DatabaseSchema.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        for (final query in DatabaseSchema.createTablesQueries) {
          await db.execute(query);
        }
        await seedInitialDataIfNeeded(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Schema migrations can be appended here non-destructively
      },
    );
  }

  /// Seeds default teacher if table is empty
  static Future<void> seedInitialDataIfNeeded(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ${DatabaseSchema.tableTeachers}'),
    );
    if (count == null || count == 0) {
      final defaultPasswordHash = TeacherAuthService.hashPassword('password');
      final now = DateTime.now().toIso8601String();
      await db.insert(DatabaseSchema.tableTeachers, {
        'username': 'teacher',
        'password_hash': defaultPasswordHash,
        'display_name': 'Teacher',
        'created_at': now,
      });
    }
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
