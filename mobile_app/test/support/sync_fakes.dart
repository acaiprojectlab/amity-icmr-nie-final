import 'package:amity_icmr_mobile/models/patient_record.dart';
import 'package:amity_icmr_mobile/sync/sync_api.dart';
import 'package:amity_icmr_mobile/sync/sync_store.dart';

/// Empty upload queue (widget tests that aren't about uploading).
class EmptySyncStore implements SyncStore {
  @override
  Future<List<PatientRecord>> getRecordsNeedingSync() async => const [];

  @override
  Future<int> countPendingSync() async => 0;

  @override
  Future<void> markSynced(
    int id, {
    required String patientId,
    required String patientStudyId,
    required int localRev,
  }) async {}

  @override
  Future<void> markSyncError(int id, String message) async {}
}

/// Stand-in for the sync service: hands out official IDs like the server's
/// counters, remembers what it received, and can simulate failures.
class FakeSyncApi implements SyncApi {
  int nextPatient = 42;
  int nextStudy = 17;
  final ids = <String, SyncedIds>{};
  final received = <Map<String, dynamic>>[];
  final tokensSeen = <String>[];

  /// Thrown by wake() (e.g. offline).
  SyncException? wakeError;

  /// Thrown once per listed record id, then that record succeeds.
  final failOnce = <String, SyncException>{};

  /// Always refused (bad data).
  final rejectAlways = <String>{};

  /// Runs while a PUT is "in flight" (to change the record meanwhile).
  Future<void> Function(String recordId)? duringPut;

  @override
  Future<void> wake() async {
    if (wakeError != null) throw wakeError!;
  }

  @override
  Future<SyncedIds> putRecord(
    String recordId,
    Map<String, dynamic> payload,
    String sessionToken,
  ) async {
    tokensSeen.add(sessionToken);
    final failure = failOnce.remove(recordId);
    if (failure != null) throw failure;
    if (rejectAlways.contains(recordId)) {
      throw const SyncException(SyncFailure.rejected, 'Refused (error 422).');
    }
    await duringPut?.call(recordId);
    received.add({'id': recordId, ...payload});
    return ids.putIfAbsent(
      recordId,
      () => SyncedIds(
        'P${(nextPatient++).toString().padLeft(3, '0')}',
        'M${(nextStudy++).toString().padLeft(2, '0')}',
      ),
    );
  }
}
