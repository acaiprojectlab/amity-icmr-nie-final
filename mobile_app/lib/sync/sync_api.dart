import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/patient_record.dart';

/// Address of the sync service (sync_service/ in the repository, hosted on
/// Render). Override with --dart-define=SYNC_URL=https://...
const syncServiceUrl = String.fromEnvironment(
  'SYNC_URL',
  defaultValue: 'https://amity-icmr-sync.onrender.com',
);

enum SyncFailure {
  /// No connection, or the service didn't answer in time.
  offline,

  /// The sign-in token was refused.
  unauthorized,

  /// The service refused this record's data (won't succeed on retry).
  rejected,

  /// The service or its database is having trouble; try again later.
  server,
}

class SyncException implements Exception {
  const SyncException(this.kind, this.message);

  final SyncFailure kind;
  final String message;

  @override
  String toString() => message;
}

class SyncedIds {
  const SyncedIds(this.patientId, this.patientStudyId);

  final String patientId;
  final String patientStudyId;
}

abstract class SyncApi {
  /// Wake the service (Render's free plan sleeps after 15 idle minutes and
  /// takes about a minute to start). Call before getting a sign-in token,
  /// which is only valid for about a minute.
  Future<void> wake();

  /// Create or update one record; returns its official IDs.
  Future<SyncedIds> putRecord(
      String recordId, Map<String, dynamic> payload, String sessionToken);
}

class HttpSyncApi implements SyncApi {
  HttpSyncApi({String baseUrl = syncServiceUrl, http.Client? client})
      : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client();

  static const _wakeTimeout = Duration(seconds: 90);
  static const _requestTimeout = Duration(seconds: 30);

  final String _base;
  final http.Client _client;

  @override
  Future<void> wake() async {
    final resp = await _send(
        () => _client.get(Uri.parse('$_base/health')), _wakeTimeout);
    if (resp.statusCode != 200) {
      throw const SyncException(SyncFailure.server,
          'The upload service is not available right now.');
    }
  }

  @override
  Future<SyncedIds> putRecord(String recordId, Map<String, dynamic> payload,
      String sessionToken) async {
    final resp = await _send(
      () => _client.put(
        Uri.parse('$_base/v1/records/$recordId'),
        headers: {
          'Authorization': 'Bearer $sessionToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ),
      _requestTimeout,
    );
    switch (resp.statusCode) {
      case 200:
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return SyncedIds(
          body['patient_id'] as String? ?? '',
          body['patient_study_id'] as String? ?? '',
        );
      case 401:
        throw const SyncException(
            SyncFailure.unauthorized, 'Please sign in again to upload.');
      case 400 || 404 || 413 || 422:
        throw SyncException(SyncFailure.rejected,
            'The upload service refused this record (error ${resp.statusCode}).');
      default:
        throw SyncException(SyncFailure.server,
            'The upload service had a problem (error ${resp.statusCode}).');
    }
  }

  Future<http.Response> _send(
      Future<http.Response> Function() request, Duration timeout) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const SyncException(
          SyncFailure.offline, 'The upload service did not respond.');
    } catch (_) {
      // Socket / TLS / client errors: no usable connection.
      throw const SyncException(SyncFailure.offline, 'No internet connection.');
    }
  }
}

/// The record as the sync service expects it (sync_service/records.py,
/// RecordIn). Times are sent in UTC; the phone stores local times.
Map<String, dynamic> recordPayload(PatientRecord r) {
  final tops = [
    (r.top1Virus, r.top1Confidence),
    (r.top2Virus, r.top2Confidence),
    (r.top3Virus, r.top3Confidence),
    (r.top4Virus, r.top4Confidence),
    (r.top5Virus, r.top5Confidence),
  ];
  return {
    'enrolled_at': _utcIso(r.createdAt) ?? DateTime.now().toUtc().toIso8601String(),
    'enrolled_by': r.enrolledBy,
    'patient': {
      'date_of_collection': r.dateOfCollection,
      'patient_name': r.patientName,
      'patient_mrd_id': r.patientMrdId,
      'hospital': r.hospital,
      'department': r.department,
      'department_specification': r.departmentSpecification,
      'date_of_admission': r.dateOfAdmission,
      'mobile_no': r.mobileNo,
      'address_line': r.addressLine,
      'age': r.age,
      'sex': r.sex,
      'patient_type': r.patientType,
      'onset_of_illness': r.onsetOfIllness,
      'duration_of_illness_days': r.durationOfIllness,
      'state_name': r.stateName,
      'district_name': r.districtName,
      'subdistrict': r.subdistrict,
      'pin_code': r.pinCode,
      'syndrome_name': r.syndromeName,
    },
    'symptoms': r.symptoms,
    'prediction': {
      'predicted_virus_name': r.predictedVirusName,
      'prediction_confidence_percent': r.predictionConfidence,
      'top': [
        for (final (virus, confidence) in tops)
          if (virus.isNotEmpty) {'virus': virus, 'confidence': confidence},
      ],
    },
    'doctor': {
      'lab_id': r.labId,
      'confirmed_pathogen': r.confirmedPathogen,
      'submitted_at': r.isCompleted ? _utcIso(r.doctorLabSubmittedAt!) : null,
    },
    'deleted': r.isDeleted,
  };
}

String? _utcIso(String localIso) =>
    DateTime.tryParse(localIso)?.toUtc().toIso8601String();
