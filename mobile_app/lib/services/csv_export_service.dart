import 'package:csv/csv.dart';
import '../models/patient_record.dart';
import 'reference_data_service.dart';

class CsvExportService {
  static String generateCsv(List<PatientRecord> records) {
    final sdn = ReferenceDataService.instance.symptomDisplayNames;

    final headers = [
      "Date of Collection",
      "Patient MRD ID",
      "Hospital",
      "Patient Study ID",
      "Department",
      "Date of Admission",
      "Patient Name",
      "Address",
      "State",
      "District",
      "Subdistrict",
      "Pin Code",
      "Mobile No",
      "Lab ID",
      "Doctor Recommended Pathogen",
      "Status",
      "Age",
      "Sex",
      "Patient Type",
      "Syndrome",
      "Selected Symptoms",
      "Onset of Illness",
      "Duration of Illness (days)",
      "Top 1 Virus",
      "Top 1 Probability (%)",
      "Top 2 Virus",
      "Top 2 Probability (%)",
      "Top 3 Virus",
      "Top 3 Probability (%)",
      "Top 4 Virus",
      "Top 4 Probability (%)",
      "Top 5 Virus",
      "Top 5 Probability (%)"
    ];

    List<List<dynamic>> rows = [headers];

    for (final r in records) {
      // Build selected symptoms string
      final List<String> activeSymptoms = [];
      r.symptoms.forEach((k, v) {
        if (v == 1) {
          activeSymptoms.add(sdn[k] ?? k);
        }
      });

      rows.add([
        r.dateOfCollection.isNotEmpty ? r.dateOfCollection : "—",
        r.patientMrdId.isNotEmpty ? r.patientMrdId : "—",
        r.hospital.isNotEmpty ? r.hospital : "—",
        r.patientStudyId.isNotEmpty ? r.patientStudyId : "—",
        r.department.isNotEmpty ? r.department : "—",
        r.dateOfAdmission.isNotEmpty ? r.dateOfAdmission : "—",
        r.patientName.isNotEmpty ? r.patientName : "—",
        r.addressLine.isNotEmpty ? r.addressLine : "—",
        r.stateName.isNotEmpty ? r.stateName : "—",
        r.districtName.isNotEmpty ? r.districtName : "—",
        r.subdistrict.isNotEmpty ? r.subdistrict : "—",
        r.pinCode.isNotEmpty ? r.pinCode : "—",
        r.mobileNo.isNotEmpty ? r.mobileNo : "—",
        r.labId.isNotEmpty ? r.labId : "",
        r.confirmedPathogen.isNotEmpty ? r.confirmedPathogen : "—",
        r.isCompleted ? "Completed" : "Pending",
        r.age,
        r.sexLabel,
        r.patientTypeLabel,
        r.syndromeName.isNotEmpty ? r.syndromeName : "—",
        activeSymptoms.isNotEmpty ? activeSymptoms.join(", ") : "—",
        r.onsetOfIllness.isNotEmpty ? r.onsetOfIllness : "—",
        r.durationOfIllness,
        r.top1Virus,
        r.top1Confidence.toStringAsFixed(2),
        r.top2Virus,
        r.top2Confidence.toStringAsFixed(2),
        r.top3Virus,
        r.top3Confidence.toStringAsFixed(2),
        r.top4Virus,
        r.top4Confidence.toStringAsFixed(2),
        r.top5Virus,
        r.top5Confidence.toStringAsFixed(2),
      ]);
    }

    return csv.encode(rows);
  }
}
