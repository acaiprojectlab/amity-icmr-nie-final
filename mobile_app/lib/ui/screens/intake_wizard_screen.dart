import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../services/reference_data_service.dart';
import '../widgets/symptom_chip_selector.dart';
import 'prediction_result_screen.dart';

class IntakeWizardScreen extends StatefulWidget {
  const IntakeWizardScreen({super.key});

  @override
  State<IntakeWizardScreen> createState() => _IntakeWizardScreenState();
}

class _IntakeWizardScreenState extends State<IntakeWizardScreen> {
  int _currentStep = 0;
  final _df = DateFormat('dd-MM-yyyy');

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final refService = ReferenceDataService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Intake & Diagnosis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Form',
            onPressed: () {
              provider.resetForm();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Form reset to default values')),
              );
            },
          ),
        ],
      ),
      body: Stepper(
        type: StepperType.horizontal,
        currentStep: _currentStep,
        onStepTapped: (step) {
          setState(() {
            _currentStep = step;
          });
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: Row(
              children: [
                if (_currentStep < 1)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Validate Step 1
                        if (provider.hospital.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Please select a Hospital')),
                          );
                          return;
                        }
                        setState(() {
                          _currentStep++;
                        });
                      },
                      child: const Text('Next: Clinical Presentation →'),
                    ),
                  )
                else
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: provider.isPredicting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.psychology_outlined),
                      label: Text(
                        provider.isPredicting
                            ? 'Analyzing with Edge AI...'
                            : 'Predict Virus (Edge AI)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: provider.isPredicting
                          ? null
                          : () async {
                              // Validate symptom selection
                              final hasSymptoms = provider.symptoms.values
                                  .any((val) => val == 1);
                              if (!hasSymptoms) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Please select at least 1 symptom before predicting.'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }

                              final nav = Navigator.of(context);
                              final messenger = ScaffoldMessenger.of(context);

                              try {
                                final result = await provider.runPrediction();
                                nav.push(
                                  MaterialPageRoute(
                                    builder: (_) => PredictionResultScreen(
                                      result: result,
                                    ),
                                  ),
                                );
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Prediction Error: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _currentStep--;
                      });
                    },
                    child: const Text('← Back'),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          // Step 1: Patient Demographics & Administrative Details
          Step(
            title: const Text('Patient Info'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Administrative & Site Details',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Collection Date
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today, size: 20),
                  title: const Text('Date of Collection'),
                  subtitle: Text(_df.format(provider.dateOfCollection)),
                  trailing: const Icon(Icons.edit, size: 16),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: provider.dateOfCollection,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) provider.setDateOfCollection(picked);
                  },
                ),
                const Divider(height: 1),

                // Patient Name & MRD ID
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: provider.patientName,
                        decoration: const InputDecoration(
                          labelText: 'Patient Name',
                          hintText: 'e.g., John Doe',
                        ),
                        onChanged: (val) => provider.setPatientName(val),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: provider.patientMrdId,
                        decoration: const InputDecoration(
                          labelText: 'MRD ID',
                          hintText: 'e.g., A123456',
                        ),
                        onChanged: (val) => provider.setPatientMrdId(val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Hospital & Department Selection
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: provider.hospital,
                        decoration: const InputDecoration(labelText: 'Hospital *'),
                        items: const [
                          DropdownMenuItem(value: 'MMC', child: Text('MMC')),
                          DropdownMenuItem(value: 'TMC', child: Text('TMC')),
                        ],
                        onChanged: (val) {
                          if (val != null) provider.setHospital(val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: provider.department,
                        decoration:
                            const InputDecoration(labelText: 'Department *'),
                        items: const [
                          DropdownMenuItem(
                              value: 'Medicine', child: Text('Medicine')),
                          DropdownMenuItem(
                              value: 'Pediatrics', child: Text('Pediatrics')),
                          DropdownMenuItem(
                              value: 'Other', child: Text('Other')),
                        ],
                        onChanged: (val) {
                          if (val != null) provider.setDepartment(val);
                        },
                      ),
                    ),
                  ],
                ),
                if (provider.department == 'Other') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: provider.departmentOther,
                    decoration: const InputDecoration(
                      labelText: 'Specify Department',
                      hintText: 'Type department name',
                    ),
                    onChanged: (val) => provider.setDepartmentOther(val),
                  ),
                ],
                const SizedBox(height: 12),

                // Admission Date & Mobile
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event, size: 20),
                        title: const Text('Date of Admission'),
                        subtitle: Text(_df.format(provider.dateOfAdmission)),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: provider.dateOfAdmission,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) provider.setDateOfAdmission(picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: provider.mobileNo,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile No (10-digit)',
                          hintText: '9876543210',
                        ),
                        onChanged: (val) => provider.setMobileNo(val),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Text(
                  'Location & Demographics',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // State & District Dropdowns
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: provider.selectedState,
                        decoration: const InputDecoration(labelText: 'State'),
                        items: refService.statesMap.keys
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) provider.setState(val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: provider.selectedDistrict.isNotEmpty
                            ? provider.selectedDistrict
                            : (refService.statesMap[provider.selectedState]
                                        ?.districts.isNotEmpty ??
                                    false
                                ? refService
                                    .statesMap[provider.selectedState]!
                                    .districts
                                    .first
                                    .name
                                : null),
                        decoration:
                            const InputDecoration(labelText: 'District'),
                        items: (refService.statesMap[provider.selectedState]
                                    ?.districts ??
                                [])
                            .map((d) => DropdownMenuItem(
                                value: d.name, child: Text(d.name)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) provider.setDistrict(val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Address Line, Subdistrict, Pin Code
                TextFormField(
                  initialValue: provider.addressLine,
                  decoration: const InputDecoration(
                    labelText: 'Street Address',
                    hintText: 'City / Street',
                  ),
                  onChanged: (val) => provider.setAddressLine(val),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: provider.subdistrict,
                        decoration:
                            const InputDecoration(labelText: 'Subdistrict'),
                        onChanged: (val) => provider.setSubdistrict(val),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: provider.pinCode,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'PIN Code (6 digits)'),
                        onChanged: (val) => provider.setPinCode(val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Age, Sex, Patient Type
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: provider.age.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Age (Years)'),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null) provider.setAge(parsed);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: provider.sex,
                        decoration: const InputDecoration(labelText: 'Sex *'),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Female')),
                          DropdownMenuItem(value: 1, child: Text('Male')),
                          DropdownMenuItem(value: 2, child: Text('Other')),
                        ],
                        onChanged: (val) {
                          if (val != null) provider.setSex(val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: provider.patientType,
                        decoration:
                            const InputDecoration(labelText: 'Patient Type *'),
                        items: const [
                          DropdownMenuItem(
                              value: 0, child: Text('Outpatient')),
                          DropdownMenuItem(value: 1, child: Text('Inpatient')),
                        ],
                        onChanged: (val) {
                          if (val != null) provider.setPatientType(val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Onset Date & Computed Duration
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sick_outlined, size: 20),
                  title: const Text('Onset of Illness'),
                  subtitle: Text(
                      '${_df.format(provider.onsetOfIllness)} (${provider.durationOfIllness} days duration)'),
                  trailing: const Icon(Icons.edit, size: 16),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: provider.onsetOfIllness,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) provider.setOnsetOfIllness(picked);
                  },
                ),
              ],
            ),
          ),

          // Step 2: Syndrome & Symptoms Presentation
          Step(
            title: const Text('Clinical Symptoms'),
            isActive: _currentStep >= 1,
            state: StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Syndrome Classification',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // Syndrome Dropdown
                DropdownButtonFormField<int>(
                  initialValue: provider.syndromeEncoded,
                  decoration: const InputDecoration(
                    labelText: 'Primary Syndrome *',
                    helperText:
                        'Drives clinical syndromic exclusion & reranking rules',
                  ),
                  isExpanded: true,
                  items: refService.syndromes.map((syn) {
                    return DropdownMenuItem<int>(
                      value: syn.encodedValue,
                      child: Text(
                        syn.overallSyndrome,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final option = refService.syndromes
                          .firstWhere((s) => s.encodedValue == val);
                      provider.setSyndrome(option);
                    }
                  },
                ),
                const SizedBox(height: 20),

                const Text(
                  'Clinical Symptoms (Select all present)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // 35 Symptoms Chip Selector
                const SymptomChipSelector(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
