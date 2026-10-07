import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../models/patient_record.dart';
import '../../providers/app_provider.dart';
import '../../services/csv_export_service.dart';
import '../../services/pdf_report_service.dart';
import '../widgets/auth_widgets.dart';
import 'update_dr_screen.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Admin-only, re-checked here behind the navigation (like the web's
    // require_page_access).
    if (!context.watch<AuthController>().canOpen(AppPage.records)) {
      return const AccessDeniedView();
    }
    final provider = context.watch<AppProvider>();
    final records = provider.records;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enrolled Patient Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export All Records as CSV',
            onPressed: records.isEmpty
                ? null
                : () async {
                    final csvStr = CsvExportService.generateCsv(records);
                    await Printing.sharePdf(
                      bytes: Uint8List.fromList(csvStr.codeUnits),
                      filename:
                          'ICMR_Patient_Records_${DateTime.now().millisecondsSinceEpoch}.csv',
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => provider.refreshRecords(),
          ),
          const AccountButton(),
        ],
      ),
      body: Column(
        children: [
          // Status Tabs Filter (All / Pending / Completed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                _buildStatusTab('All', '📋 All (${records.length})', provider),
                const SizedBox(width: 8),
                _buildStatusTab('Pending', '🔴 Pending', provider),
                const SizedBox(width: 8),
                _buildStatusTab('Completed', '🟢 Completed', provider),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search Patient ID / Name / MRD ID...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          provider.setSearchQuery('');
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
                ),
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
              ),
              onChanged: (val) {
                provider.setSearchQuery(val.trim());
              },
            ),
          ),

          // Records List
          Expanded(
            child: provider.isLoadingRecords
                ? const Center(child: CircularProgressIndicator())
                : records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open_outlined,
                                size: 54, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No patient records found',
                              style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: records.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final rec = records[index];
                          return _buildPatientCard(rec, provider);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTab(
      String statusKey, String label, AppProvider provider) {
    final isSelected = provider.statusFilter == statusKey;
    return Expanded(
      child: InkWell(
        onTap: () => provider.setStatusFilter(statusKey),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Colors.grey[800],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPatientCard(PatientRecord rec, AppProvider provider) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Patient ID, Study ID, Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        rec.patientId,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ),
                    if (rec.patientStudyId.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          rec.patientStudyId,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.purple,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: rec.isCompleted
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    rec.isCompleted ? '🟢 Completed' : '🔴 Pending DR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: rec.isCompleted
                          ? Colors.green[800]
                          : Colors.red[800],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Patient Name & MRD ID
            if (rec.patientName.isNotEmpty) ...[
              Text(
                rec.patientName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              '${rec.age} yrs, ${rec.sexLabel} • ${rec.hospital} (${rec.department})',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),

            // Syndrome & Predicted Pathogen
            Row(
              children: [
                const Icon(Icons.coronavirus_outlined,
                    size: 14, color: Color(0xFF1565C0)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Predicted: ${rec.top1Virus} (${rec.top1Confidence.toStringAsFixed(1)}%)',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Action Buttons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.medical_services_outlined, size: 16),
                  label: Text(
                      rec.isCompleted ? 'Edit DR' : 'Update DR',
                      style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UpdateDrScreen(record: rec),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf,
                      size: 18, color: Color(0xFF1565C0)),
                  tooltip: 'Print / Share PDF Slip',
                  onPressed: () => PdfReportService.printOrShare(rec),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  tooltip: 'Delete Record',
                  onPressed: () => _confirmDelete(rec, provider),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(PatientRecord rec, AppProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Patient Record?'),
        content: Text(
          'Are you sure you want to delete ${rec.patientId} (${rec.patientName.isNotEmpty ? rec.patientName : "De-identified"})? It will be removed from your active list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              if (rec.id != null) {
                await provider.softDeleteRecord(rec.id!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Record ${rec.patientId} deleted.')),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
