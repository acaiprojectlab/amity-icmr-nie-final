import 'dart:io';

import 'package:amity_icmr_mobile/database/app_database.dart';
import 'package:amity_icmr_mobile/models/patient_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PatientRecord samplePatient(String patientId) => PatientRecord(
  patientId: patientId,
  patientStudyId: 'M01',
  patientMrdId: 'MRD-1',
  patientName: 'Test Patient',
  hospital: 'MMC',
  department: 'Medicine',
  departmentSpecification: '',
  dateOfCollection: '06-10-2026',
  dateOfAdmission: '06-10-2026',
  mobileNo: '9999999999',
  addressLine: '1 Main Road',
  stateName: 'Tamil Nadu',
  stateEncoded: 29,
  districtName: 'Chennai',
  districtEncoded: 3,
  subdistrict: '',
  pinCode: '600001',
  age: 34,
  sex: 1,
  patientType: 0,
  onsetOfIllness: '03-10-2026',
  durationOfIllness: 3,
  syndromeEncoded: 0,
  syndromeName: 'ARI/Influenza Like Illness (ILI)',
  symptoms: {'FEVER': 1, 'COUGH': 1, 'HEADACHE': 0},
  predictedVirusName: 'Influenza A H1N1',
  predictionConfidence: 0.61,
  top1Virus: 'Influenza A H1N1',
  top1Confidence: 0.61,
  top2Virus: 'Dengue Virus',
  top2Confidence: 0.2,
  top3Virus: '',
  top3Confidence: 0,
  top4Virus: '',
  top4Confidence: 0,
  top5Virus: '',
  top5Confidence: 0,
  createdAt: DateTime(2026, 10, 6).toIso8601String(),
);

/// The patients table exactly as earlier builds created it (no symptoms
/// column), as found on phones that already have the app installed.
const oldPatientsTable = '''
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
''';

void main() {
  setUpAll(() async {
    // Real SQLite (desktop build) so the same SQL the phone runs is tested.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Own folder per test file: files run in parallel.
    await databaseFactory.setDatabasesPath(
      Directory.systemTemp.createTempSync('amity_db_').path,
    );
    final path = join(await getDatabasesPath(), 'amity_icmr_patients.db');
    await databaseFactory.deleteDatabase(path);
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(oldPatientsTable),
      ),
    );
    // A patient saved by an earlier build (before uploading existed).
    await old.insert('patients', {
      'patient_id': 'P001',
      'patient_name': 'Saved Before Upload',
      'created_at': DateTime(2026, 10, 6).toIso8601String(),
    });
    await old.close();
  });

  test('enrolling a patient saves the record, symptoms included '
      '(on a database created by an earlier build)', () async {
    final db = AppDatabase.instance;
    await db.insertPatient(samplePatient('P001'));

    final saved = (await db.getPatients()).firstWhere(
      (r) => r.patientName == 'Test Patient',
    );
    expect(saved.patientId, 'P001');
    expect(saved.patientName, 'Test Patient');
    expect(saved.symptoms, {'FEVER': 1, 'COUGH': 1, 'HEADACHE': 0});
  });

  test('patients saved by an earlier build are queued for upload', () async {
    final queued = await AppDatabase.instance.getRecordsNeedingSync();
    final old = queued.firstWhere(
      (r) => r.patientName == 'Saved Before Upload',
    );
    expect(old.clientRecordId, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4')));
    expect(old.needsSync, isTrue);
    expect(old.synced, isFalse);
  });
}
