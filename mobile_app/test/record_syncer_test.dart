import 'dart:io';

import 'package:amity_icmr_mobile/database/app_database.dart';
import 'package:amity_icmr_mobile/models/patient_record.dart';
import 'package:amity_icmr_mobile/sync/record_syncer.dart';
import 'package:amity_icmr_mobile/sync/sync_api.dart';
import 'package:amity_icmr_mobile/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'patient_database_test.dart' show samplePatient;
import 'support/sync_fakes.dart';

final db = AppDatabase.instance;

Future<PatientRecord> enrol(String tempId, {String? recordId}) async {
  final base = samplePatient(tempId);
  final record = PatientRecord.fromMap({
    ...base.toMap(),
    'client_record_id': recordId ?? newRecordId(),
    'enrolled_by': 'user@example.com',
  });
  final id = await db.insertPatient(record);
  return (await db.getPatientById(id))!;
}

void main() {
  late FakeSyncApi api;
  late RecordSyncer syncer;
  late int tokenCount;
  late bool signedIn;
  late int uploadedCallbacks;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Own folder per test file: files run in parallel.
    await databaseFactory.setDatabasesPath(
      Directory.systemTemp.createTempSync('amity_db_').path,
    );
    await databaseFactory.deleteDatabase(
      join(await getDatabasesPath(), 'amity_icmr_patients.db'),
    );
  });

  setUp(() async {
    await (await db.database).delete('patients');
    api = FakeSyncApi();
    tokenCount = 0;
    signedIn = true;
    uploadedCallbacks = 0;
    syncer = RecordSyncer(
      store: db,
      api: api,
      sessionToken: () async => 'token-${++tokenCount}',
      isSignedIn: () => signedIn,
    )..onRecordsUploaded = () => uploadedCallbacks++;
  });

  tearDown(() => syncer.dispose());

  test('an enrolled patient uploads and gets its official IDs '
      '(read from the database, so any role\'s enrolments upload)', () async {
    final rec = await enrol('TMP-P001');
    expect(await db.countPendingSync(), 1);

    await syncer.syncNow();

    final saved = (await db.getPatientById(rec.id!))!;
    expect(saved.patientId, 'P042');
    expect(saved.patientStudyId, 'M17');
    expect(saved.synced, isTrue);
    expect(saved.needsSync, isFalse);
    expect(syncer.pending, 0);
    expect(syncer.lastError, isNull);
    expect(uploadedCallbacks, 1);
    expect(api.received.single['id'], rec.clientRecordId);
  });

  test('offline: the patient stays saved and waiting', () async {
    final rec = await enrol('TMP-P001');
    api.wakeError = const SyncException(
      SyncFailure.offline,
      'No internet connection.',
    );

    await syncer.syncNow();

    final saved = (await db.getPatientById(rec.id!))!;
    expect(saved.patientId, 'TMP-P001');
    expect(saved.needsSync, isTrue);
    expect(syncer.pending, 1);
    expect(syncer.lastError, 'No internet connection.');
    expect(
      tokenCount,
      0,
      reason: 'no token is requested before the service is awake',
    );

    api.wakeError = null; // back online
    await syncer.syncNow();
    expect((await db.getPatientById(rec.id!))!.patientId, 'P042');
  });

  test('an expired sign-in token is renewed once', () async {
    final rec = await enrol('TMP-P001');
    api.failOnce[rec.clientRecordId] = const SyncException(
      SyncFailure.unauthorized,
      'Please sign in again.',
    );

    await syncer.syncNow();

    expect(api.tokensSeen, ['token-1', 'token-2']);
    expect((await db.getPatientById(rec.id!))!.synced, isTrue);
  });

  test('a record refused by the server does not hold up the others', () async {
    final bad = await enrol('TMP-P001');
    final good = await enrol('TMP-P002');
    api.rejectAlways.add(bad.clientRecordId);

    await syncer.syncNow();

    expect((await db.getPatientById(good.id!))!.synced, isTrue);
    final refused = (await db.getPatientById(bad.id!))!;
    expect(refused.synced, isFalse);
    expect(refused.syncError, 'Refused (error 422).');
    expect(syncer.pending, 1);
  });

  test('a change made while uploading is uploaded next time', () async {
    final rec = await enrol('TMP-P001');
    api.duringPut = (_) async {
      api.duringPut = null;
      await db.updateDoctorRecommendation(
        id: rec.id!,
        labId: 'LAB-7',
        confirmedPathogen: 'Dengue Virus',
      );
    };

    await syncer.syncNow();
    var saved = (await db.getPatientById(rec.id!))!;
    expect(saved.patientId, 'P042', reason: 'official IDs are kept');
    expect(
      saved.needsSync,
      isTrue,
      reason: 'the DR update has not gone up yet',
    );

    await syncer.syncNow();
    saved = (await db.getPatientById(rec.id!))!;
    expect(saved.needsSync, isFalse);
    final doctor = api.received.last['doctor'] as Map<String, dynamic>;
    expect(doctor['lab_id'], 'LAB-7');
    expect(doctor['submitted_at'], endsWith('Z'));
  });

  test(
    'deletions: sent for uploaded records, never for unuploaded ones',
    () async {
      final uploaded = await enrol('TMP-P001');
      await syncer.syncNow();
      final neverUploaded = await enrol('TMP-P002');

      await db.softDeletePatient(uploaded.id!);
      await db.softDeletePatient(neverUploaded.id!);
      expect(await db.countPendingSync(), 1);

      await syncer.syncNow();
      expect(api.received.last['id'], uploaded.clientRecordId);
      expect(api.received.last['deleted'], isTrue);
      expect(
        api.received.where((r) => r['id'] == neverUploaded.clientRecordId),
        isEmpty,
      );
    },
  );

  test('signed out: nothing is uploaded', () async {
    await enrol('TMP-P001');
    signedIn = false;

    await syncer.syncNow();

    expect(api.received, isEmpty);
    expect(syncer.pending, 1);
  });

  test(
    'payload: UTC times, real symptoms, only filled prediction ranks',
    () async {
      final rec = await enrol('TMP-P001');
      final payload = recordPayload(rec);

      expect(payload['enrolled_at'], endsWith('Z'));
      expect(payload['symptoms'], {'FEVER': 1, 'COUGH': 1, 'HEADACHE': 0});
      final top = (payload['prediction'] as Map)['top'] as List;
      expect(top.length, 2);
      expect((payload['doctor'] as Map)['submitted_at'], isNull);
      expect(payload['deleted'], isFalse);
      expect((payload['patient'] as Map)['hospital'], 'MMC');
    },
  );
}
