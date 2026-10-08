import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/patient_record.dart';
import '../sync/sync_store.dart';

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

class AppDatabase implements SyncStore {
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
      version: 2,
      onCreate: _createDB,
      onOpen: _upgradeOnOpen,
    );
  }

  /// Columns added after the first release. Earlier builds created the table
  /// without them (and, lacking `symptoms_json`, failed to save any patient),
  /// so they are added on open -- checked every time, so it works whatever
  /// build created the file.
  static const _addedColumns = {
    'symptoms_json': 'TEXT',
    'client_record_id': 'TEXT',
    'enrolled_by': 'TEXT',
    'synced': 'INTEGER NOT NULL DEFAULT 0',
    'needs_sync': 'INTEGER NOT NULL DEFAULT 0',
    'local_rev': 'INTEGER NOT NULL DEFAULT 0',
    'sync_error': 'TEXT',
  };

  Future<void> _upgradeOnOpen(Database db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(patients)'))
        .map((c) => c['name'])
        .toSet();
    for (final entry in _addedColumns.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
            'ALTER TABLE patients ADD COLUMN ${entry.key} ${entry.value}');
      }
    }
    // Patients saved before uploading existed get an upload ID and are
    // queued, so they reach the shared database too.
    final unqueued = await db.query('patients',
        columns: ['id'],
        where: "client_record_id IS NULL OR client_record_id = ''");
    for (final row in unqueued) {
      await db.update(
        'patients',
        {'client_record_id': newRecordId(), 'needs_sync': 1},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
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
        symptoms_json TEXT,
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
        is_deleted INTEGER NOT NULL DEFAULT 0,
        client_record_id TEXT,
        enrolled_by TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        needs_sync INTEGER NOT NULL DEFAULT 0,
        local_rev INTEGER NOT NULL DEFAULT 0,
        sync_error TEXT
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

  /// Insert enrolled patient (queued for upload)
  Future<int> insertPatient(PatientRecord record) async {
    final db = await database;
    final map = record.toMap();
    map.remove('id'); // let SQLite autoincrement
    if ((map['client_record_id'] as String?)?.isNotEmpty != true) {
      map['client_record_id'] = newRecordId();
    }
    map['needs_sync'] = 1;
    map['synced'] = 0;
    return await db.insert('patients', map);
  }

  Future<PatientRecord?> getPatientById(int id) async {
    final db = await database;
    final rows =
        await db.query('patients', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PatientRecord.fromMap(rows.first);
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
    return await db.rawUpdate(
      'UPDATE patients SET lab_id = ?, confirmed_pathogen = ?, '
      'doctor_lab_submitted_at = ?, needs_sync = 1, sync_error = NULL, '
      'local_rev = local_rev + 1 WHERE id = ?',
      [labId, confirmedPathogen, DateTime.now().toIso8601String(), id],
    );
  }

  /// Soft-delete patient record. Only records already uploaded need the
  /// deletion sent; one never uploaded simply never reaches the server.
  Future<int> softDeletePatient(int id) async {
    final db = await database;
    return await db.rawUpdate(
      'UPDATE patients SET is_deleted = 1, '
      'needs_sync = CASE WHEN synced = 1 THEN 1 ELSE 0 END, '
      'local_rev = local_rev + 1 WHERE id = ?',
      [id],
    );
  }

  // --- Upload queue (SyncStore) ---

  @override
  Future<List<PatientRecord>> getRecordsNeedingSync() async {
    final db = await database;
    final rows = await db.query(
      'patients',
      where: 'needs_sync = 1 AND NOT (is_deleted = 1 AND synced = 0)',
      orderBy: 'id ASC',
    );
    return rows.map(PatientRecord.fromMap).toList();
  }

  @override
  Future<int> countPendingSync() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM patients '
      'WHERE needs_sync = 1 AND NOT (is_deleted = 1 AND synced = 0)',
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  @override
  Future<void> markSynced(
    int id, {
    required String patientId,
    required String patientStudyId,
    required int localRev,
  }) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE patients SET patient_id = ?, patient_study_id = ?, synced = 1, '
      'sync_error = NULL, '
      'needs_sync = CASE WHEN local_rev = ? THEN 0 ELSE 1 END WHERE id = ?',
      [patientId, patientStudyId, localRev, id],
    );
  }

  @override
  Future<void> markSyncError(int id, String message) async {
    final db = await database;
    await db.update('patients', {'sync_error': message},
        where: 'id = ?', whereArgs: [id]);
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
