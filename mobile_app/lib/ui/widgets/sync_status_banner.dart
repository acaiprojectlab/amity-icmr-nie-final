import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/patient_record.dart';
import '../../sync/record_syncer.dart';

/// "3 patients waiting to upload" with an Upload now button; hidden when
/// everything is uploaded.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<RecordSyncer>();
    final n = sync.pending;
    if (n == 0) return const SizedBox.shrink();
    const amber = Color(0xFFB26A00);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sync.isRunning
                      ? 'Uploading $n patient${n == 1 ? '' : 's'}…'
                      : '$n patient${n == 1 ? '' : 's'} waiting to upload',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13, color: amber),
                ),
                const SizedBox(height: 2),
                Text(
                  sync.isRunning
                      ? 'The upload service may take up to a minute to wake up.'
                      : sync.lastError ??
                          'They upload automatically when the phone is online.',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                ),
              ],
            ),
          ),
          if (sync.isRunning)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: sync.syncNow,
              child: const Text('Upload now'),
            ),
        ],
      ),
    );
  }
}

/// Small "Uploaded" / "Waiting to upload" label for one record.
class RecordSyncChip extends StatelessWidget {
  const RecordSyncChip({super.key, required this.record});

  final PatientRecord record;

  @override
  Widget build(BuildContext context) {
    final waiting = record.needsSync || !record.synced;
    final color = record.syncError != null
        ? const Color(0xFFC62828)
        : waiting
            ? const Color(0xFFB26A00)
            : const Color(0xFF2E7D32);
    return Tooltip(
      message: record.syncError ??
          (waiting
              ? 'Saved on this phone; uploads automatically when online.'
              : 'Saved in the shared database.'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(waiting ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
              size: 14, color: color),
          const SizedBox(width: 3),
          Text(
            record.syncError != null
                ? 'Upload refused'
                : waiting
                    ? 'Waiting to upload'
                    : 'Uploaded',
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
