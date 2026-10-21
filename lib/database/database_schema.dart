class DatabaseSchema {
  DatabaseSchema._();

  static const int version = 1;
  static const String databaseName = 'attendance_app.db';

  // Table names
  static const String tableTeachers = 'teachers';
  static const String tableStudents = 'students';
  static const String tableClasses = 'classes';
  static const String tableClassTeachers = 'class_teachers';
  static const String tableClassStudents = 'class_students';
  static const String tableAttendanceSessions = 'attendance_sessions';
  static const String tableAttendanceRecords = 'attendance_records';

  static const List<String> createTablesQueries = [
    // 1. Teachers
    '''
    CREATE TABLE $tableTeachers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      display_name TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    ''',

    // 2. Students (register_number is the only primary key)
    '''
    CREATE TABLE $tableStudents (
      register_number TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL,
      phone TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    ''',

    // 3. Classes
    '''
    CREATE TABLE $tableClasses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    ''',

    // 4. Class Teachers Junction
    '''
    CREATE TABLE $tableClassTeachers (
      class_id INTEGER NOT NULL,
      teacher_id INTEGER NOT NULL,
      PRIMARY KEY (class_id, teacher_id),
      FOREIGN KEY (class_id) REFERENCES $tableClasses(id) ON DELETE CASCADE,
      FOREIGN KEY (teacher_id) REFERENCES $tableTeachers(id) ON DELETE CASCADE
    );
    ''',

    // 5. Class Students Junction (keyed by register_number)
    '''
    CREATE TABLE $tableClassStudents (
      class_id INTEGER NOT NULL,
      register_number TEXT NOT NULL,
      PRIMARY KEY (class_id, register_number),
      FOREIGN KEY (class_id) REFERENCES $tableClasses(id) ON DELETE CASCADE,
      FOREIGN KEY (register_number) REFERENCES $tableStudents(register_number) ON DELETE CASCADE
    );
    ''',

    // 6. Attendance Sessions
    '''
    CREATE TABLE $tableAttendanceSessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      class_id INTEGER NOT NULL,
      teacher_id INTEGER NOT NULL,
      attendance_date TEXT NOT NULL,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      status TEXT NOT NULL,
      FOREIGN KEY (class_id) REFERENCES $tableClasses(id),
      FOREIGN KEY (teacher_id) REFERENCES $tableTeachers(id)
    );
    ''',

    // 7. Attendance Records with Historical Snapshot (keyed by register_number)
    '''
    CREATE TABLE $tableAttendanceRecords (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL,
      register_number TEXT NOT NULL,
      status TEXT NOT NULL,
      attendance_time TEXT,
      student_name TEXT NOT NULL,
      student_email TEXT NOT NULL,
      student_phone TEXT NOT NULL,
      UNIQUE(session_id, register_number),
      FOREIGN KEY (session_id) REFERENCES $tableAttendanceSessions(id) ON DELETE CASCADE,
      FOREIGN KEY (register_number) REFERENCES $tableStudents(register_number) ON DELETE CASCADE
    );
    ''',

    // Indexes for fast querying
    'CREATE INDEX idx_class_teachers_class ON $tableClassTeachers(class_id);',
    'CREATE INDEX idx_class_teachers_teacher ON $tableClassTeachers(teacher_id);',
    'CREATE INDEX idx_class_students_class ON $tableClassStudents(class_id);',
    'CREATE INDEX idx_class_students_reg ON $tableClassStudents(register_number);',
    'CREATE INDEX idx_attendance_sessions_class ON $tableAttendanceSessions(class_id);',
    'CREATE INDEX idx_attendance_sessions_date ON $tableAttendanceSessions(attendance_date);',
    'CREATE INDEX idx_attendance_records_session ON $tableAttendanceRecords(session_id);',
    'CREATE INDEX idx_attendance_records_reg ON $tableAttendanceRecords(register_number);',
  ];
}

