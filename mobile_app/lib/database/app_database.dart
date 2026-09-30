import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/patient_record.dart';

class DashboardMetrics {
  final int enrolled;
  final int drCompleted;
  final int drPending;
  final int daily;
  final int weekly;
  final int monthly;

  DashboardMetrics({
    required this.enrolled,
    required this.drCompleted,
    required this.drPending,
    required this.daily,
    required this.weekly,
    required this.monthly,
  });
}

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('amity_icmr_patients.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Patients table
    await db.execute('''
      CREATE TABLE patients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id TEXT NOT NULL,
        patient_study_id TEXT,
        patient_mrd_id TEXT,
        patient_name TEXT,
        hospital TEXT,
        department TEXT,
        department_specification TEXT,
        date_of_collection TEXT,
        date_of_admission TEXT,
        mobile_no TEXT,
        address_line TEXT,
        state_name TEXT,
        state_encoded INTEGER,
        district_name TEXT,
        district_encoded INTEGER,
        subdistrict TEXT,
        pin_code TEXT,
        age INTEGER,
        sex INTEGER,
        patient_type INTEGER,
        onset_of_illness TEXT,
        duration_of_illness INTEGER,
        syndrome_encoded INTEGER,
        syndrome_name TEXT,
        predicted_virus_name TEXT,
        prediction_confidence REAL,
        top_1_virus TEXT,
        top_1_confidence REAL,
        top_2_virus TEXT,
        top_2_confidence REAL,
        top_3_virus TEXT,
        top_3_confidence REAL,
        top_4_virus TEXT,
        top_4_confidence REAL,
        top_5_virus TEXT,
        top_5_confidence REAL,
        lab_id TEXT,
        confirmed_pathogen TEXT,
        doctor_lab_submitted_at TEXT,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 2. Counters table for atomic sequential ID generation
    await db.execute('''
      CREATE TABLE counters (
        id TEXT PRIMARY KEY,
        sequence_value INTEGER NOT NULL
      )
    ''');
  }

  /// Generate next sequential Patient ID (P001, P002...)
  Future<String> getNextPatientId() async {
    final db = await database;
    return await db.transaction((txn) async {
      final List<Map<String, dynamic>> res = await txn.query(
        'counters',
        where: 'id = ?',
        whereArgs: ['patient_id'],
      );

      int nextVal = 1;
      if (res.isNotEmpty) {
        nextVal = (res.first['sequence_value'] as int) + 1;
        await txn.update(
          'counters',
          {'sequence_value': nextVal},
          where: 'id = ?',
          whereArgs: ['patient_id'],
        );
      } else {
        await txn.insert('counters', {
          'id': 'patient_id',
          'sequence_value': 1,
        });
      }
      return 'P${nextVal.toString().padLeft(3, '0')}';
    });
  }

  /// Generate next hospital-prefixed Patient Study ID (M01, T01...)
  Future<String> getNextStudyId(String hospital) async {
    if (hospital.isEmpty || hospital == 'Select...') {
      return '';
    }
    String prefix = 'M';
    if (hospital == 'TMC') {
      prefix = 'T';
    } else if (hospital.isNotEmpty) {
      prefix = hospital[0].toUpperCase();
    }

    final counterKey = 'study_id_$prefix';
    final db = await database;
    return await db.transaction((txn) async {
      final List<Map<String, dynamic>> res = await txn.query(
        'counters',
        where: 'id = ?',
        whereArgs: [counterKey],
      );

      int nextVal = 1;
      if (res.isNotEmpty) {
        nextVal = (res.first['sequence_value'] as int) + 1;
        await txn.update(
          'counters',
          {'sequence_value': nextVal},
          where: 'id = ?',
          whereArgs: [counterKey],
        );
      } else {
        await txn.insert('counters', {
          'id': counterKey,
          'sequence_value': 1,
        });
      }
      return '$prefix${nextVal.toString().padLeft(2, '0')}';
    });
  }

  /// Insert enrolled patient
  Future<int> insertPatient(PatientRecord record) async {
    final db = await database;
    final map = record.toMap();
    map.remove('id'); // let SQLite autoincrement
    return await db.insert('patients', map);
  }

  /// Fetch all patient records with optional filters
  Future<List<PatientRecord>> getPatients({
    bool includeDeleted = false,
    String status = 'All', // 'All', 'Pending', 'Completed'
    String searchQuery = '',
    String? hospital,
    String? department,
  }) async {
    final db = await database;
    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (!includeDeleted) {
      whereClauses.add('is_deleted = 0');
    }

    if (status == 'Pending') {
      whereClauses.add('(doctor_lab_submitted_at IS NULL OR doctor_lab_submitted_at = "")');
    } else if (status == 'Completed') {
      whereClauses.add('(doctor_lab_submitted_at IS NOT NULL AND doctor_lab_submitted_at != "")');
    }

    if (hospital != null && hospital.isNotEmpty && hospital != 'All') {
      whereClauses.add('hospital = ?');
      whereArgs.add(hospital);
    }

    if (department != null && department.isNotEmpty && department != 'All') {
      whereClauses.add('department = ?');
      whereArgs.add(department);
    }

    if (searchQuery.isNotEmpty) {
      final q = '%$searchQuery%';
      whereClauses.add(
          '(patient_id LIKE ? OR patient_study_id LIKE ? OR patient_mrd_id LIKE ? OR patient_name LIKE ?)');
      whereArgs.addAll([q, q, q, q]);
    }

    final whereString =
        whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final result = await db.query(
      'patients',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'id DESC',
    );

    return result.map((json) => PatientRecord.fromMap(json)).toList();
  }

  /// Update Doctor Recommendation & Lab confirmation
  Future<int> updateDoctorRecommendation({
    required int id,
    required String labId,
    required String confirmedPathogen,
  }) async {
    final db = await database;
    return await db.update(
      'patients',
      {
        'lab_id': labId,
        'confirmed_pathogen': confirmedPathogen,
        'doctor_lab_submitted_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft-delete patient record
  Future<int> softDeletePatient(int id) async {
    final db = await database;
    return await db.update(
      'patients',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get summary KPI dashboard metrics
  Future<DashboardMetrics> getDashboardMetrics() async {
    final db = await database;
    final liveRecords = await db.query(
      'patients',
      where: 'is_deleted = 0',
    );

    int enrolled = liveRecords.length;
    int completed = 0;
    int pending = 0;
    int daily = 0;
    int weekly = 0;
    int monthly = 0;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = now.subtract(const Duration(days: 7));
    final monthStart = now.subtract(const Duration(days: 30));

    for (final r in liveRecords) {
      final submittedAt = r['doctor_lab_submitted_at'] as String?;
      if (submittedAt != null && submittedAt.isNotEmpty) {
        completed++;
      } else {
        pending++;
      }

      final createdAtStr = r['created_at'] as String?;
      if (createdAtStr != null) {
        final created = DateTime.tryParse(createdAtStr);
        if (created != null) {
          if (created.isAfter(todayStart)) daily++;
          if (created.isAfter(weekStart)) weekly++;
          if (created.isAfter(monthStart)) monthly++;
        }
      }
    }

    return DashboardMetrics(
      enrolled: enrolled,
      drCompleted: completed,
      drPending: pending,
      daily: daily,
      weekly: weekly,
      monthly: monthly,
    );
  }
}
