import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/patient_record.dart';
import 'reference_data_service.dart';

class PdfReportService {
  static Future<Uint8List> generateReport(PatientRecord record) async {
    final pdf = pw.Document();

    // Load logos
    pw.MemoryImage? icmrLogo;
    pw.MemoryImage? dhrLogo;
    pw.MemoryImage? amityLogo;

    try {
      final img1 = await rootBundle.load('assets/images/logo_1.jpeg');
      icmrLogo = pw.MemoryImage(img1.buffer.asUint8List());
      final img2 = await rootBundle.load('assets/images/logo_2.jpeg');
      dhrLogo = pw.MemoryImage(img2.buffer.asUint8List());
      final img3 = await rootBundle.load('assets/images/Amity_logo2.png');
      amityLogo = pw.MemoryImage(img3.buffer.asUint8List());
    } catch (_) {}

    final sdn = ReferenceDataService.instance.symptomDisplayNames;
    final List<String> activeSymptoms = [];
    record.symptoms.forEach((k, v) {
      if (v == 1) {
        activeSymptoms.add(sdn[k] ?? k);
      }
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header with 3 Institutional Logos
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (icmrLogo != null)
                  pw.Image(icmrLogo, width: 90, height: 45)
                else
                  pw.Text('ICMR-NIE',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 10)),
                if (dhrLogo != null)
                  pw.Image(dhrLogo, width: 80, height: 45)
                else
                  pw.Text('DHR',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 10)),
                if (amityLogo != null)
                  pw.Image(amityLogo, width: 80, height: 45)
                else
                  pw.Text('AMITY',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1.5, color: PdfColors.blue900),
            pw.SizedBox(height: 8),

            // Title
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    'Personalized Laboratory Test Recommendation System',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                  pw.Text(
                    'Clinical Diagnostic Decision Support Slip',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Status Banner
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: pw.BoxDecoration(
                color: record.isCompleted
                    ? PdfColors.green50
                    : PdfColors.red50,
                borderRadius: pw.BorderRadius.circular(4),
                border: pw.Border.all(
                  color: record.isCompleted
                      ? PdfColors.green700
                      : PdfColors.red700,
                  width: 0.8,
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Patient ID: ${record.patientId}  |  Study ID: ${record.patientStudyId.isNotEmpty ? record.patientStudyId : "—"}',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  pw.Text(
                    'Status: ${record.isCompleted ? "COMPLETED" : "PENDING RECOMMENDATION"}',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                      color: record.isCompleted
                          ? PdfColors.green900
                          : PdfColors.red900,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Patient Information Table
            pw.Text(
              '1. PATIENT & ADMINISTRATIVE DETAILS',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _buildTableRow('Patient Name', record.patientName,
                    'MRD ID', record.patientMrdId),
                _buildTableRow('Hospital', record.hospital,
                    'Department', record.department),
                _buildTableRow('Age / Sex', '${record.age} yrs / ${record.sexLabel}',
                    'Patient Type', record.patientTypeLabel),
                _buildTableRow('Date of Collection', record.dateOfCollection,
                    'Date of Admission', record.dateOfAdmission),
                _buildTableRow('Location', '${record.districtName}, ${record.stateName}',
                    'Onset / Duration', '${record.onsetOfIllness} (${record.durationOfIllness} days)'),
              ],
            ),
            pw.SizedBox(height: 14),

            // Clinical Presentation
            pw.Text(
              '2. CLINICAL PRESENTATION',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                            text: 'Primary Syndrome: ',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 9)),
                        pw.TextSpan(
                            text: record.syndromeName,
                            style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                            text: 'Active Symptoms (${activeSymptoms.length}): ',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 9)),
                        pw.TextSpan(
                            text: activeSymptoms.isNotEmpty
                                ? activeSymptoms.join(', ')
                                : 'None reported',
                            style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // AI Predictions Table
            pw.Text(
              '3. AI-POWERED PATHOGEN RECOMMENDATIONS (DUAL-STAGE GRTT)',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('#', isHeader: true),
                    _cell('Predicted Pathogen', isHeader: true),
                    _cell('Confidence Score', isHeader: true),
                  ],
                ),
                _predRow('1', record.top1Virus, '${record.top1Confidence.toStringAsFixed(2)}% (Primary)'),
                _predRow('2', record.top2Virus, '${record.top2Confidence.toStringAsFixed(2)}%'),
                _predRow('3', record.top3Virus, '${record.top3Confidence.toStringAsFixed(2)}%'),
                _predRow('4', record.top4Virus, '${record.top4Confidence.toStringAsFixed(2)}%'),
                _predRow('5', record.top5Virus, '${record.top5Confidence.toStringAsFixed(2)}%'),
              ],
            ),
            pw.SizedBox(height: 14),

            // Doctor Recommendation & Laboratory Section
            pw.Text(
              '4. CLINICIAN RECOMMENDATION & LABORATORY VALIDATION',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          'Lab ID: ${record.labId.isNotEmpty ? record.labId : "_______________"}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          'Date of Report: ________________',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Doctor Recommended Pathogen(s): ${record.confirmedPathogen.isNotEmpty ? record.confirmedPathogen : "______________________________________________________"}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Clinician Signature: __________________',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Lab In-charge Signature: __________________',
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
            ),

            pw.Spacer(),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.Text(
              'Medical Disclaimer: This AI-generated report is a diagnostic aid and does not substitute for qualified clinical evaluation or laboratory confirmation.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
              textAlign: pw.TextAlign.center,
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.TableRow _buildTableRow(
      String label1, String val1, String label2, String val2) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                    text: '$label1: ',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 8)),
                pw.TextSpan(
                    text: val1.isNotEmpty ? val1 : '—',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                    text: '$label2: ',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 8)),
                pw.TextSpan(
                    text: val2.isNotEmpty ? val2 : '—',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.TableRow _predRow(String rank, String virus, String conf) {
    return pw.TableRow(
      children: [
        _cell(rank),
        _cell(virus.isNotEmpty ? virus : '—'),
        _cell(conf),
      ],
    );
  }

  static pw.Widget _cell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static Future<void> printOrShare(PatientRecord record) async {
    final pdfBytes = await generateReport(record);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'ICMR_Patient_${record.patientId}.pdf',
    );
  }
}
