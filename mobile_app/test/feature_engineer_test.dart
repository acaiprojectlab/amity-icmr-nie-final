import 'package:flutter_test/flutter_test.dart';
import 'package:amity_icmr_mobile/ml/clinical_rules.dart';
import 'package:amity_icmr_mobile/ml/feature_engineer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClinicalRules Tests', () {
    test('Syndrome 0 (ILI) excludes Dengue, Japanese Encephalitis, etc.', () {
      final virusMapping = {
        0: 'Chikungunya Virus',
        1: 'Dengue Virus',
        8: 'Influenza A H1N1',
        11: 'Japanese Encephalitis',
      };

      final excluded = ClinicalRules.getExcludedIndices(0, virusMapping);
      expect(excluded.contains(1), isTrue); // Dengue excluded
      expect(excluded.contains(11), isTrue); // JE excluded
      expect(excluded.contains(8), isFalse); // Influenza NOT excluded
      expect(excluded.contains(0), isFalse); // Chikungunya NOT excluded
    });

    test('FilterTopK removes excluded classes and promotes candidates', () {
      final virusMapping = {
        0: 'Chikungunya Virus',
        1: 'Dengue Virus',
        2: 'Enterovirus',
        8: 'Influenza A H1N1',
        11: 'Japanese Encephalitis',
      };

      // Raw probabilities: Dengue is highest (0.50), but should be excluded for ILI (0)
      final probs = [0.20, 0.50, 0.10, 0.0, 0.0, 0.0, 0.0, 0.0, 0.15, 0.0, 0.0, 0.05];

      final result = ClinicalRules.filterTopK(
        probabilities: probs,
        virusMapping: virusMapping,
        syndromeEncoded: 0, // ILI
        k: 3,
      );

      // Top indices should not contain 1 (Dengue)
      expect(result.topIndices.contains(1), isFalse);
      expect(result.excludedViruses.contains('Dengue Virus'), isTrue);
      // Top 1 should be Chikungunya (0.20) or Influenza (0.15)
      expect(result.topIndices.first, equals(0));
    });
  });

  group('FeatureEngineer Normalization Tests', () {
    test('Preprocess produces exact tensor shapes', () {
      final mockModelConfig = {
        'model1': {
          'binary_cols': ['FEVER', 'COUGH'],
          'expected_cont_cols': ['age', 'durationofillness'],
          'cat_cols': ['lab_state', 'Syndrome_encoded'],
          'imputer_statistics': {'age': 30.0, 'durationofillness': 0.0},
          'scaler_params': {
            'age': {'mean': 30.0, 'scale': 15.0},
            'durationofillness': {'mean': 3.0, 'scale': 2.0},
          },
          'cat_encoders': {},
        },
        'symptoms': ['FEVER', 'COUGH', 'HEADACHE'],
      };

      final fe = FeatureEngineer(modelConfig: mockModelConfig);
      final patientData = {
        'age': 45,
        'durationofillness': 5,
        'FEVER': 1,
        'COUGH': 1,
        'lab_state': 29,
        'Syndrome_encoded': 0,
      };

      final tensors = fe.preprocess(patientData, 'model1');

      expect(tensors.xb.length, equals(2));
      expect(tensors.xc.length, equals(2));
      expect(tensors.xcat.length, equals(2));

      // Check normalized age: (45 - 30) / 15 = 1.0
      expect(tensors.xc[0], closeTo(1.0, 1e-5));
      // Check normalized duration: (5 - 3) / 2 = 1.0
      expect(tensors.xc[1], closeTo(1.0, 1e-5));
      // Check binary values
      expect(tensors.xb[0], equals(1.0));
      expect(tensors.xb[1], equals(1.0));
    });
  });
}
