/// Complete Patient Record Model matching ICMR clinical schema
library;

import 'dart:convert';

class PatientRecord {
  final int? id; // Local SQLite auto-increment primary key
  final String patientId; // Sequential P001, P002...
  final String patientStudyId; // Hospital-prefixed M01, T01...
  final String patientMrdId;
  final String patientName;
  final String hospital;
  final String department;
  final String departmentSpecification;
  final String dateOfCollection; // DD-MM-YYYY
  final String dateOfAdmission; // DD-MM-YYYY
  final String mobileNo;
  final String addressLine;
  final String stateName;
  final int stateEncoded;
  final String districtName;
  final int districtEncoded;
  final String subdistrict;
  final String pinCode;
  final int age;
  final int sex; // 0: Female, 1: Male, 2: Other
  final int patientType; // 0: Outpatient, 1: Inpatient
  final String onsetOfIllness; // DD-MM-YYYY
  final int durationOfIllness; // in days
  final int syndromeEncoded;
  final String syndromeName;
  final Map<String, int> symptoms; // 35 symptom keys -> 0 or 1

  // Prediction Fields
  final String predictedVirusName;
  final double predictionConfidence;
  final String top1Virus;
  final double top1Confidence;
  final String top2Virus;
  final double top2Confidence;
  final String top3Virus;
  final double top3Confidence;
  final String top4Virus;
  final double top4Confidence;
  final String top5Virus;
  final double top5Confidence;

  // Doctor Recommendation & Laboratory Confirmation
  final String labId;
  final String confirmedPathogen; // Comma-separated (up to 5)
  final String? doctorLabSubmittedAt; // ISO timestamp string if completed
  final String createdAt; // ISO timestamp
  final bool isDeleted; // Soft-delete flag

  PatientRecord({
    this.id,
    required this.patientId,
    required this.patientStudyId,
    required this.patientMrdId,
    required this.patientName,
    required this.hospital,
    required this.department,
    required this.departmentSpecification,
    required this.dateOfCollection,
    required this.dateOfAdmission,
    required this.mobileNo,
    required this.addressLine,
    required this.stateName,
    required this.stateEncoded,
    required this.districtName,
    required this.districtEncoded,
    required this.subdistrict,
    required this.pinCode,
    required this.age,
    required this.sex,
    required this.patientType,
    required this.onsetOfIllness,
    required this.durationOfIllness,
    required this.syndromeEncoded,
    required this.syndromeName,
    required this.symptoms,
    required this.predictedVirusName,
    required this.predictionConfidence,
    required this.top1Virus,
    required this.top1Confidence,
    required this.top2Virus,
    required this.top2Confidence,
    required this.top3Virus,
    required this.top3Confidence,
    required this.top4Virus,
    required this.top4Confidence,
    required this.top5Virus,
    required this.top5Confidence,
    this.labId = '',
    this.confirmedPathogen = '',
    this.doctorLabSubmittedAt,
    required this.createdAt,
    this.isDeleted = false,
  });

  bool get isCompleted =>
      doctorLabSubmittedAt != null && doctorLabSubmittedAt!.isNotEmpty;

  String get sexLabel {
    if (sex == 0) return 'Female';
    if (sex == 1) return 'Male';
    return 'Other';
  }

  String get patientTypeLabel =>
      patientType == 1 ? 'Inpatient' : 'Outpatient';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patient_id': patientId,
      'patient_study_id': patientStudyId,
      'patient_mrd_id': patientMrdId,
      'patient_name': patientName,
      'hospital': hospital,
      'department': department,
      'department_specification': departmentSpecification,
      'date_of_collection': dateOfCollection,
      'date_of_admission': dateOfAdmission,
      'mobile_no': mobileNo,
      'address_line': addressLine,
      'state_name': stateName,
      'state_encoded': stateEncoded,
      'district_name': districtName,
      'district_encoded': districtEncoded,
      'subdistrict': subdistrict,
      'pin_code': pinCode,
      'age': age,
      'sex': sex,
      'patient_type': patientType,
      'onset_of_illness': onsetOfIllness,
      'duration_of_illness': durationOfIllness,
      'syndrome_encoded': syndromeEncoded,
      'syndrome_name': syndromeName,
      'predicted_virus_name': predictedVirusName,
      'prediction_confidence': predictionConfidence,
      'top_1_virus': top1Virus,
      'top_1_confidence': top1Confidence,
      'top_2_virus': top2Virus,
      'top_2_confidence': top2Confidence,
      'top_3_virus': top3Virus,
      'top_3_confidence': top3Confidence,
      'top_4_virus': top4Virus,
      'top_4_confidence': top4Confidence,
      'top_5_virus': top5Virus,
      'top_5_confidence': top5Confidence,
      'lab_id': labId,
      'confirmed_pathogen': confirmedPathogen,
      'doctor_lab_submitted_at': doctorLabSubmittedAt,
      'created_at': createdAt,
      'is_deleted': isDeleted ? 1 : 0,
      // All symptoms in one JSON column ({"fever": 1, ...}); the table has
      // no per-symptom columns.
      'symptoms_json': jsonEncode(symptoms),
    };
  }

  factory PatientRecord.fromMap(Map<String, dynamic> map) {
    Map<String, int> symptomsMap = {};
    final symptomsJson = map['symptoms_json'];
    if (symptomsJson is String && symptomsJson.isNotEmpty) {
      (jsonDecode(symptomsJson) as Map<String, dynamic>).forEach((k, v) {
        symptomsMap[k] = (v as num?)?.toInt() ?? 0;
      });
    } else {
      // Older layout with one sym_<name> column per symptom.
      map.forEach((k, v) {
        if (k.startsWith('sym_')) {
          String symKey = k.substring(4);
          symptomsMap[symKey] = (v as int?) ?? 0;
        }
      });
    }

    return PatientRecord(
      id: map['id'] as int?,
      patientId: (map['patient_id'] as String?) ?? '',
      patientStudyId: (map['patient_study_id'] as String?) ?? '',
      patientMrdId: (map['patient_mrd_id'] as String?) ?? '',
      patientName: (map['patient_name'] as String?) ?? '',
      hospital: (map['hospital'] as String?) ?? '',
      department: (map['department'] as String?) ?? '',
      departmentSpecification:
          (map['department_specification'] as String?) ?? '',
      dateOfCollection: (map['date_of_collection'] as String?) ?? '',
      dateOfAdmission: (map['date_of_admission'] as String?) ?? '',
      mobileNo: (map['mobile_no'] as String?) ?? '',
      addressLine: (map['address_line'] as String?) ?? '',
      stateName: (map['state_name'] as String?) ?? '',
      stateEncoded: (map['state_encoded'] as int?) ?? 0,
      districtName: (map['district_name'] as String?) ?? '',
      districtEncoded: (map['district_encoded'] as int?) ?? 0,
      subdistrict: (map['subdistrict'] as String?) ?? '',
      pinCode: (map['pin_code'] as String?) ?? '',
      age: (map['age'] as int?) ?? 0,
      sex: (map['sex'] as int?) ?? 0,
      patientType: (map['patient_type'] as int?) ?? 0,
      onsetOfIllness: (map['onset_of_illness'] as String?) ?? '',
      durationOfIllness: (map['duration_of_illness'] as int?) ?? 0,
      syndromeEncoded: (map['syndrome_encoded'] as int?) ?? 0,
      syndromeName: (map['syndrome_name'] as String?) ?? '',
      symptoms: symptomsMap,
      predictedVirusName: (map['predicted_virus_name'] as String?) ?? '',
      predictionConfidence:
          ((map['prediction_confidence'] as num?) ?? 0).toDouble(),
      top1Virus: (map['top_1_virus'] as String?) ?? '',
      top1Confidence: ((map['top_1_confidence'] as num?) ?? 0).toDouble(),
      top2Virus: (map['top_2_virus'] as String?) ?? '',
      top2Confidence: ((map['top_2_confidence'] as num?) ?? 0).toDouble(),
      top3Virus: (map['top_3_virus'] as String?) ?? '',
      top3Confidence: ((map['top_3_confidence'] as num?) ?? 0).toDouble(),
      top4Virus: (map['top_4_virus'] as String?) ?? '',
      top4Confidence: ((map['top_4_confidence'] as num?) ?? 0).toDouble(),
      top5Virus: (map['top_5_virus'] as String?) ?? '',
      top5Confidence: ((map['top_5_confidence'] as num?) ?? 0).toDouble(),
      labId: (map['lab_id'] as String?) ?? '',
      confirmedPathogen: (map['confirmed_pathogen'] as String?) ?? '',
      doctorLabSubmittedAt: map['doctor_lab_submitted_at'] as String?,
      createdAt: (map['created_at'] as String?) ?? '',
      isDeleted: ((map['is_deleted'] as int?) ?? 0) == 1,
    );
  }
}
