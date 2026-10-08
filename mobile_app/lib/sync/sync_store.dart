import 'dart:math';

import '../models/patient_record.dart';

/// The local side of uploading: which records still need to reach the
/// shared database, and what to remember once they have. Implemented by
/// AppDatabase; tests can use an in-memory fake.
abstract class SyncStore {
  /// Records with local changes not yet uploaded, oldest first. Includes
  /// deleted records that already exist on the server (so the deletion
  /// reaches it) but not ones deleted before they were ever uploaded.
  Future<List<PatientRecord>> getRecordsNeedingSync();

  Future<int> countPendingSync();

  /// The server accepted [localRev] of the record and assigned the official
  /// IDs. If the record changed again meanwhile it stays pending.
  Future<void> markSynced(
    int id, {
    required String patientId,
    required String patientStudyId,
    required int localRev,
  });

  /// The server refused the record (it stays pending; [message] is shown).
  Future<void> markSyncError(int id, String message);
}

/// Random (version 4) UUID identifying a record on the server, so retried
/// uploads are recognised instead of duplicated.
String newRecordId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
