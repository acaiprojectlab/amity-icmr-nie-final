import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_models.dart';
import 'sync_api.dart';
import 'sync_store.dart';

/// Uploads patients enrolled on this phone to the shared (web) database,
/// whenever there is a connection: right after a change, when someone signs
/// in, when the app comes back to the foreground, and every minute while
/// anything is waiting. Records are always saved on the phone first, so
/// enrolment never depends on the network.
///
/// Reads the queue straight from the local database (not from AppProvider's
/// lists, which only admins load), so standard users' enrolments upload too.
class RecordSyncer extends ChangeNotifier {
  RecordSyncer({
    required this._store,
    required this._api,
    required this._sessionToken,
    required this._isSignedIn,
    this.retryInterval = const Duration(minutes: 1),
  });

  final SyncStore _store;
  final SyncApi _api;
  final Future<String> Function() _sessionToken;
  final bool Function() _isSignedIn;
  final Duration retryInterval;

  /// Called after records were uploaded (their IDs may have changed).
  VoidCallback? onRecordsUploaded;

  int _pending = 0;
  bool _running = false;
  String? _lastError;
  DateTime? _lastSuccessAt;
  Future<void>? _inFlight;
  Timer? _retryTimer;
  bool _disposed = false;

  /// Records waiting to be uploaded.
  int get pending => _pending;
  bool get isRunning => _running;

  /// Why the last attempt stopped early (null after a clean run).
  String? get lastError => _lastError;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// Start the once-a-minute retry while anything is waiting.
  void start() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(retryInterval, (_) {
      if (_pending > 0) syncNow();
    });
    syncNow();
  }

  Future<void> refreshPendingCount() async {
    try {
      _setPending(await _store.countPendingSync());
    } catch (e) {
      if (kDebugMode) debugPrint('Could not count pending uploads: $e');
    }
  }

  /// Upload everything waiting. Never throws; concurrent calls share one run.
  Future<void> syncNow() => _inFlight ??= _run().whenComplete(() {
        _inFlight = null;
      });

  Future<void> _run() async {
    if (_disposed) return;
    var uploaded = 0;
    try {
      final records = await _store.getRecordsNeedingSync();
      _setPending(records.length);
      if (records.isEmpty || !_isSignedIn()) return;

      _running = true;
      _notify();

      await _api.wake();
      var token = await _sessionToken();
      for (final record in records) {
        SyncedIds ids;
        try {
          ids = await _api.putRecord(
              record.clientRecordId, recordPayload(record), token);
        } on SyncException catch (e) {
          if (e.kind == SyncFailure.unauthorized) {
            // Tokens last about a minute: get a fresh one and retry once.
            token = await _sessionToken();
            ids = await _api.putRecord(
                record.clientRecordId, recordPayload(record), token);
          } else if (e.kind == SyncFailure.rejected) {
            await _store.markSyncError(record.id!, e.message);
            continue; // don't let one bad record hold up the rest
          } else {
            rethrow;
          }
        }
        await _store.markSynced(
          record.id!,
          patientId: ids.patientId,
          patientStudyId: ids.patientStudyId,
          localRev: record.localRev,
        );
        uploaded++;
      }
      _lastError = null;
      _lastSuccessAt = DateTime.now();
    } on SyncException catch (e) {
      _lastError = e.message;
    } on AuthException catch (e) {
      _lastError = e.message;
    } catch (e) {
      _lastError = 'Upload failed. It will be retried automatically.';
      if (kDebugMode) debugPrint('Upload failed: $e');
    } finally {
      _running = false;
      // Even a partly finished run may have changed IDs.
      if (uploaded > 0 && !_disposed) onRecordsUploaded?.call();
      await refreshPendingCount();
      _notify();
    }
  }

  void _setPending(int value) {
    if (value == _pending) return;
    _pending = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    super.dispose();
  }
}
