import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../models/prediction_result.dart';
import '../../providers/app_provider.dart';
import '../../services/pdf_report_service.dart';
import '../../services/reference_data_service.dart';
import '../widgets/probability_chart.dart';
import 'records_screen.dart';

class PredictionResultScreen extends StatelessWidget {
  final FullPredictionResult result;

  const PredictionResultScreen({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final subResult = result.subClassification;

    // Extract Top-10 Major Probabilities
    final vm = ReferenceDataService.instance.modelConfig['virus_mapping']
            as Map<String, dynamic>? ??
        {};
    final List<int> majorIndices =
        List.generate(result.fullMajorProbabilities.length, (i) => i);
    majorIndices.sort((a, b) => result.fullMajorProbabilities[b]
        .compareTo(result.fullMajorProbabilities[a]));
    final top10MajorIndices = majorIndices.take(10).toList();
    final top10MajorLabels =
        top10MajorIndices.map((i) => vm[i.toString()]?.toString() ?? 'Virus $i').toList();
    final top10MajorValues = top10MajorIndices
        .map((i) => result.fullMajorProbabilities[i] * 100.0)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic Prediction Results'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Predicted Virus Hero Card
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00897B), Color(0xFF004D40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16.0),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00897B).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'MOST PROBABLE VIRUS',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '⚡ Edge Neural Inference',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    result.predictedVirusName == 'Other_Viruses' &&
                            subResult != null
                        ? 'Other Viruses → ${subResult.predictedSubVirusName}'
                        : result.predictedVirusName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${result.confidence.toStringAsFixed(2)}% Confidence Score',
                    style: TextStyle(
                      color: Colors.tealAccent[100],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Top-5 Ranked Predictions Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🏆 Top 5 Ranked Pathogens',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    if (result.excludedBySyndrome.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'ℹ️ Excluded as inconsistent with ${provider.syndromeName}: ${result.excludedBySyndrome.join(', ')}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(height: 12),
                    for (int i = 0; i < result.top5Predictions.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: i == 0
                                    ? const Color(0xFF1565C0)
                                    : Colors.grey[300],
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: i == 0 ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                result.top5Predictions[i].virusName,
                                style: TextStyle(
                                  fontWeight: i == 0
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              '${result.top5Predictions[i].confidence.toStringAsFixed(2)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: i == 0
                                    ? const Color(0xFF1565C0)
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < result.top5Predictions.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Secondary Sub-Classification Card (if available)
            if (subResult != null) ...[
              Card(
                elevation: 2,
                color: const Color(0xFFF9FBFD),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFF90CAF9))),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.hub_outlined,
                              color: Color(0xFF1565C0), size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Other Viruses Sub-Classification (Model 2)',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Top Sub-Category: ${subResult.predictedSubVirusName} (${subResult.subConfidence.toStringAsFixed(2)}%)',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      for (int i = 0;
                          i < subResult.topSubPredictions.length;
                          i++) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${i + 1}. ${subResult.topSubPredictions[i].virusName}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                '${subResult.topSubPredictions[i].confidence.toStringAsFixed(2)}%',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Top 10 Major Probability Distribution Chart
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📊 Top 10 Probability Distribution',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    ProbabilityChart(
                      labels: top10MajorLabels,
                      values: top10MajorValues,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons: Enrol Patient / PDF Report
            if (provider.lastEnrolledRecord != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patient Enrolled: ${provider.lastEnrolledRecord!.patientId}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const Text(
                            'Status: 🔴 Pending Doctor Recommendation',
                            style: TextStyle(fontSize: 11, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Download / Print PDF Clinical Slip'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  PdfReportService.printOrShare(provider.lastEnrolledRecord!);
                },
              ),
              // Patient records are admin-only.
              if (context.watch<AuthController>().canOpen(AppPage.records)) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_shared_outlined),
                  label: const Text('Go to View Records'),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const RecordsScreen()),
                    );
                  },
                ),
              ],
            ] else ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: const Text(
                  '📝 Enrol Patient (Save Offline Record)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  try {
                    final saved = await provider.enrolPatient();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '✅ Enrolled ${saved.patientId}! Pending Doctor Recommendation.'),
                        backgroundColor: Colors.green[700],
                      ),
                    );
                  } catch (e) {
                    // The raw error can contain every field of the record
                    // (the SQL statement and its values): log it, don't show it.
                    debugPrint('Enrolment failed: $e');
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not save this patient record. '
                            'Please try again.'),
                      ),
                    );
                  }
                },
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
