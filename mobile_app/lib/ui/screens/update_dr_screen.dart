import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/patient_record.dart';
import '../../providers/app_provider.dart';
import '../../services/reference_data_service.dart';

class UpdateDrScreen extends StatefulWidget {
  final PatientRecord record;

  const UpdateDrScreen({super.key, required this.record});

  @override
  State<UpdateDrScreen> createState() => _UpdateDrScreenState();
}

class _UpdateDrScreenState extends State<UpdateDrScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _labIdController;
  final List<String> _selectedPathogens = [];
  String _pathogenSearch = '';

  @override
  void initState() {
    super.initState();
    _labIdController = TextEditingController(text: widget.record.labId);

    // Parse existing confirmed pathogens
    if (widget.record.confirmedPathogen.isNotEmpty) {
      final parts = widget.record.confirmedPathogen
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty);
      _selectedPathogens.addAll(parts);
    }
  }

  @override
  void dispose() {
    _labIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final allPathogens = ReferenceDataService.instance.pathogens;

    final filteredPathogens = allPathogens.where((p) {
      return p.toLowerCase().contains(_pathogenSearch.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Update DR: ${widget.record.patientId}'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Patient Summary Box
              Container(
                padding: const EdgeInsets.all(14.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patient: ${widget.record.patientId} (${widget.record.patientName.isNotEmpty ? widget.record.patientName : "De-identified"})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AI Prediction: ${widget.record.top1Virus} (${widget.record.top1Confidence.toStringAsFixed(1)}%)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Lab ID Input (Required)
              TextFormField(
                controller: _labIdController,
                decoration: const InputDecoration(
                  labelText: 'Laboratory Sample ID *',
                  hintText: 'e.g., LAB-2026-0891',
                  prefixIcon: Icon(Icons.biotech_outlined),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Lab ID is required to complete recommendation';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Doctor Recommended Pathogens
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Doctor Recommended Pathogen(s)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_selectedPathogens.length}/5 max',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedPathogens.length == 5
                          ? Colors.orange[800]
                          : Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Selected Pathogens Chips
              if (_selectedPathogens.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedPathogens.map((p) {
                    return Chip(
                      label: Text(p, style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() {
                          _selectedPathogens.remove(p);
                        });
                      },
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],

              // Search Box for 100+ Pathogens
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search 100+ ICMR Pathogen list...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _pathogenSearch = val.trim();
                  });
                },
              ),
              const SizedBox(height: 8),

              // Pathogens List View
              Container(
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: filteredPathogens.length,
                  itemBuilder: (context, index) {
                    final pathogen = filteredPathogens[index];
                    final isChecked = _selectedPathogens.contains(pathogen);

                    return CheckboxListTile(
                      dense: true,
                      title: Text(
                        pathogen,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isChecked ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      value: isChecked,
                      onChanged: (bool? checked) {
                        setState(() {
                          if (checked == true) {
                            if (_selectedPathogens.length < 5) {
                              _selectedPathogens.add(pathogen);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'You can select a maximum of 5 pathogens.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          } else {
                            _selectedPathogens.remove(pathogen);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),

              // Save Button
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  'Save Doctor Recommendation',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A65A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    if (widget.record.id != null) {
                      final messenger = ScaffoldMessenger.of(context);
                      final nav = Navigator.of(context);
                      await provider.updateDoctorRecommendation(
                        recordId: widget.record.id!,
                        labId: _labIdController.text.trim(),
                        recommendedPathogens: _selectedPathogens,
                      );
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                              '✅ Doctor Recommendation saved & case marked COMPLETED!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      nav.pop();
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
