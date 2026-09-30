import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../models/prediction_result.dart';
import 'clinical_rules.dart';
import 'feature_engineer.dart';

class OnnxPredictor {
  final Map<String, dynamic> modelConfig;
  late final FeatureEngineer _featureEngineer;
  OrtSession? _session1;
  OrtSession? _session2;
  bool _isInitialized = false;

  Map<int, String> _virusMapping = {};
  Map<int, String> _otherVirusMapping = {};

  OnnxPredictor({required this.modelConfig}) {
    _featureEngineer = FeatureEngineer(modelConfig: modelConfig);
    _loadMappings();
  }

  void _loadMappings() {
    final vm = modelConfig['virus_mapping'] as Map<String, dynamic>? ?? {};
    _virusMapping = vm.map((k, v) => MapEntry(int.parse(k), v.toString()));

    final ovm =
        modelConfig['other_virus_mapping'] as Map<String, dynamic>? ?? {};
    _otherVirusMapping =
        ovm.map((k, v) => MapEntry(int.parse(k), v.toString()));
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    // Load Model 1
    final rawModel1 = await rootBundle.load('assets/models/grtt_major.onnx');
    final bytes1 = rawModel1.buffer.asUint8List();
    _session1 = OrtSession.fromBuffer(bytes1, sessionOptions);

    // Load Model 2
    final rawModel2 = await rootBundle.load('assets/models/grtt_other.onnx');
    final bytes2 = rawModel2.buffer.asUint8List();
    _session2 = OrtSession.fromBuffer(bytes2, sessionOptions);

    _isInitialized = true;
  }

  Future<FullPredictionResult> predict(Map<String, dynamic> patientData) async {
    if (!_isInitialized || _session1 == null || _session2 == null) {
      await initialize();
    }

    final syndromeEncoded = (patientData['Syndrome_encoded'] is int)
        ? patientData['Syndrome_encoded'] as int
        : (patientData['syndrome'] is int
            ? patientData['syndrome'] as int
            : null);

    // --- 1. MODEL 1 INFERENCE (Major Categories) ---
    final t1 = _featureEngineer.preprocess(patientData, 'model1');

    final xbTensor1 = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(t1.xb),
      [1, t1.xb.length],
    );
    final xcTensor1 = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(t1.xc),
      [1, t1.xc.length],
    );
    final xcatTensor1 = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(t1.xcat),
      [1, t1.xcat.length],
    );

    final runOptions = OrtRunOptions();
    final inputs1 = {
      'xb': xbTensor1,
      'xc': xcTensor1,
      'xcat': xcatTensor1,
    };

    final outputs1 = await _session1!.runAsync(runOptions, inputs1);
    xbTensor1.release();
    xcTensor1.release();
    xcatTensor1.release();

    final rawLogits1 = (outputs1![0]!.value as List<List<double>>)[0];
    outputs1[0]!.release();

    final probs1 = _softmax(rawLogits1);

    // Filter top 5 using Clinical Exclusion rules
    final filterResult1 = ClinicalRules.filterTopK(
      probabilities: probs1,
      virusMapping: _virusMapping,
      syndromeEncoded: syndromeEncoded,
      k: 5,
    );

    final top1Idx = filterResult1.topIndices[0];
    final top5Predictions1 = filterResult1.topIndices.map((idx) {
      return RankedVirusPrediction(
        virusId: idx,
        virusName: _virusMapping[idx] ?? 'Virus $idx',
        confidence: probs1[idx] * 100.0,
      );
    }).toList();

    // --- 2. MODEL 2 INFERENCE (Sub-Classification if Other_Viruses (15) in top 5) ---
    SubClassificationResult? subResult;
    if (filterResult1.topIndices.contains(15)) {
      final t2 = _featureEngineer.preprocess(patientData, 'model2');

      final xbTensor2 = OrtValueTensor.createTensorWithDataList(
        Float32List.fromList(t2.xb),
        [1, t2.xb.length],
      );
      final xcTensor2 = OrtValueTensor.createTensorWithDataList(
        Float32List.fromList(t2.xc),
        [1, t2.xc.length],
      );
      final xcatTensor2 = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(t2.xcat),
        [1, t2.xcat.length],
      );

      final inputs2 = {
        'xb': xbTensor2,
        'xc': xcTensor2,
        'xcat': xcatTensor2,
      };

      final outputs2 = await _session2!.runAsync(runOptions, inputs2);
      xbTensor2.release();
      xcTensor2.release();
      xcatTensor2.release();

      final rawLogits2 = (outputs2![0]!.value as List<List<double>>)[0];
      outputs2[0]!.release();

      final probs2 = _softmax(rawLogits2);

      final filterResult2 = ClinicalRules.filterTopK(
        probabilities: probs2,
        virusMapping: _otherVirusMapping,
        syndromeEncoded: syndromeEncoded,
        k: 5,
      );

      final topSubIdx = filterResult2.topIndices[0];
      final topSubPredictions = filterResult2.topIndices.map((idx) {
        return RankedVirusPrediction(
          virusId: idx,
          virusName: _otherVirusMapping[idx] ?? 'Sub-Virus $idx',
          confidence: probs2[idx] * 100.0,
        );
      }).toList();

      subResult = SubClassificationResult(
        predictedSubVirusId: topSubIdx,
        predictedSubVirusName: _otherVirusMapping[topSubIdx] ?? '',
        subConfidence: probs2[topSubIdx] * 100.0,
        topSubPredictions: topSubPredictions,
        excludedBySyndrome: filterResult2.excludedViruses,
        fullProbabilities: probs2,
      );
    }

    runOptions.release();

    return FullPredictionResult(
      predictedVirusId: top1Idx,
      predictedVirusName: _virusMapping[top1Idx] ?? 'Unknown',
      confidence: probs1[top1Idx] * 100.0,
      top5Predictions: top5Predictions1,
      excludedBySyndrome: filterResult1.excludedViruses,
      fullMajorProbabilities: probs1,
      subClassification: subResult,
    );
  }

  List<double> _softmax(List<double> logits) {
    double maxVal = logits.reduce(math.max);
    List<double> expVals = logits.map((l) => math.exp(l - maxVal)).toList();
    double sumExp = expVals.reduce((a, b) => a + b);
    return expVals.map((e) => e / sumExp).toList();
  }

  void dispose() {
    _session1?.release();
    _session2?.release();
    _session1 = null;
    _session2 = null;
    _isInitialized = false;
  }
}
