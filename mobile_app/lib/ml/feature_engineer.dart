import 'dart:math' as math;

/// Preprocessing & Feature Engineering matching PyTorch / sklearn training pipeline
class PreprocessedTensors {
  final List<double> xb; // Binary features
  final List<double> xc; // Continuous normalized features
  final List<int> xcat; // Categorical encoded features

  PreprocessedTensors({
    required this.xb,
    required this.xc,
    required this.xcat,
  });
}

class FeatureEngineer {
  final Map<String, dynamic> modelConfig;

  FeatureEngineer({required this.modelConfig});

  PreprocessedTensors preprocess(
    Map<String, dynamic> patientData,
    String modelKey, // 'model1' or 'model2'
  ) {
    final cfg = modelConfig[modelKey] as Map<String, dynamic>;
    final binaryCols = (cfg['binary_cols'] as List<dynamic>).cast<String>();
    final expectedContCols =
        (cfg['expected_cont_cols'] as List<dynamic>).cast<String>();
    final catCols = (cfg['cat_cols'] as List<dynamic>).cast<String>();
    final imputerStats = (cfg['imputer_statistics'] as Map?) ?? {};
    final scalerParams = (cfg['scaler_params'] as Map?) ?? {};
    final catEncoders = (cfg['cat_encoders'] as Map?) ?? {};

    // 1. Build rich feature dictionary
    final features = _computeEngineeredFeatures(patientData);

    // 2. Binary features vector (xb)
    final List<double> xb = [];
    for (final col in binaryCols) {
      final val = features[col];
      xb.add(val != null ? (val as num).toDouble() : 0.0);
    }

    // 3. Continuous features vector (xc) with Imputation & StandardScaling
    final List<double> xc = [];
    for (final col in expectedContCols) {
      double val = features.containsKey(col) && features[col] != null
          ? (features[col] as num).toDouble()
          : (imputerStats[col] != null
              ? (imputerStats[col] as num).toDouble()
              : 0.0);

      // Apply standard scaling: (val - mean) / scale
      if (scalerParams.containsKey(col)) {
        final sp = scalerParams[col] as Map;
        final mean = (sp['mean'] as num).toDouble();
        final scale = (sp['scale'] as num).toDouble();
        if (scale > 1e-7) {
          val = (val - mean) / scale;
        }
      }
      xc.add(val);
    }

    // 4. Categorical features vector (xcat)
    final List<int> xcat = [];
    for (final col in catCols) {
      int encodedVal = 0;
      if (features.containsKey(col) && features[col] != null) {
        final rawVal = features[col];
        final encoder = catEncoders[col];

        if (encoder is List) {
          final strVal = rawVal.toString();
          final idx = encoder.indexOf(strVal);
          encodedVal = idx >= 0 ? idx : 0;
        } else if (encoder is Map) {
          final strVal = rawVal.toString();
          encodedVal = (encoder[strVal] as int?) ?? 0;
        } else {
          // Direct integer conversion fallback
          if (rawVal is num) {
            encodedVal = rawVal.toInt();
          } else {
            encodedVal = int.tryParse(rawVal.toString()) ?? 0;
          }
        }
      }
      xcat.add(encodedVal);
    }

    return PreprocessedTensors(xb: xb, xc: xc, xcat: xcat);
  }

  Map<String, dynamic> _computeEngineeredFeatures(
      Map<String, dynamic> patientData) {
    final Map<String, dynamic> f = Map.from(patientData);

    // SEX safety: map anything other than 0/1 to 0 for model inference
    int sexVal = (f['SEX'] is int) ? f['SEX'] as int : 0;
    if (sexVal != 0 && sexVal != 1) {
      sexVal = 0;
    }
    f['SEX'] = sexVal;

    // Age & Age Groups
    double age = (f['age'] is num) ? (f['age'] as num).toDouble() : 30.0;
    age = age.clamp(0.0, 120.0);
    f['age'] = age;

    int ageGroup;
    if (age < 5) {
      ageGroup = 0;
    } else if (age < 18) {
      ageGroup = 1;
    } else if (age < 45) {
      ageGroup = 2;
    } else if (age < 65) {
      ageGroup = 3;
    } else {
      ageGroup = 4;
    }
    f['age_group'] = ageGroup;

    // Duration of illness
    double duration = (f['durationofillness'] is num)
        ? (f['durationofillness'] as num).toDouble()
        : 0.0;
    f['durationofillness'] = duration;
    f['duration_of_illness'] = duration;

    // Symptom Groups
    final respiratoryCols = [
      'COUGH',
      'BREATHLESSNESS',
      'RHINORRHEA',
      'SORETHROAT'
    ];
    final giCols = [
      'DIARRHEA',
      'DYSENTERY',
      'NAUSEA',
      'VOMITING',
      'ABDOMINALPAIN'
    ];
    final neuroCols = [
      'HEADACHE',
      'ALTEREDSENSORIUM',
      'SEIZURES',
      'SOMNOLENCE',
      'NECKRIGIDITY',
      'IRRITABLITY'
    ];
    final skinCols = [
      'PAPULARRASH',
      'PUSTULARRASH',
      'MACULOPAPULARRASH',
      'BULLAE'
    ];
    final systemicCols = ['MYALGIA', 'ARTHRALGIA', 'CHILLS', 'RIGORS', 'MALAISE'];

    double countGroup(List<String> cols) {
      double sum = 0.0;
      for (final c in cols) {
        if (f[c] != null && (f[c] as num) > 0) sum += 1.0;
      }
      return sum;
    }

    final respSum = countGroup(respiratoryCols);
    final giSum = countGroup(giCols);
    final neuroSum = countGroup(neuroCols);
    final skinSum = countGroup(skinCols);
    final sysSum = countGroup(systemicCols);

    // Total symptom count across all 35 symptoms
    double totalSymptoms = 0.0;
    final allSymptoms = (modelConfig['symptoms'] as List<dynamic>? ?? [])
        .cast<String>();
    for (final s in allSymptoms) {
      if (f[s] != null && (f[s] as num) > 0) totalSymptoms += 1.0;
    }

    f['symptom_count'] = totalSymptoms;
    f['respiratory_symptoms'] = respSum;
    f['gi_symptoms'] = giSum;
    f['neuro_symptoms'] = neuroSum;
    f['skin_symptoms'] = skinSum;
    f['systemic_symptoms'] = sysSum;
    f['symptom_diversity'] = totalSymptoms;

    // Temporal features
    int month = (f['month'] is int) ? f['month'] as int : 1;
    int season;
    if (month == 12 || month == 1 || month == 2) {
      season = 0; // Winter
    } else if (month >= 3 && month <= 5) {
      season = 1; // Summer
    } else if (month >= 6 && month <= 9) {
      season = 2; // Monsoon
    } else {
      season = 3; // Post-monsoon
    }

    f['season'] = season;
    final isMonsoon = (month >= 6 && month <= 9) ? 1.0 : 0.0;
    final isWinter = (month == 12 || month == 1 || month == 2) ? 1.0 : 0.0;
    f['is_monsoon'] = isMonsoon;
    f['is_winter'] = isWinter;

    f['month_sin'] = math.sin(2.0 * math.pi * month / 12.0);
    f['month_cos'] = math.cos(2.0 * math.pi * month / 12.0);
    f['week_of_year'] = month * 4.0;
    f['day_of_year'] = month * 30.0;
    f['quarter'] = ((month - 1) ~/ 3) + 1;

    // District and State
    double distEnc = (f['districtencoded'] is num)
        ? (f['districtencoded'] as num).toDouble()
        : ((f['district_encoded'] is num)
            ? (f['district_encoded'] as num).toDouble()
            : 0.0);
    f['district_encoded'] = distEnc;

    double stateEnc = (f['labstate'] is num)
        ? (f['labstate'] as num).toDouble()
        : ((f['lab_state'] is num)
            ? (f['lab_state'] as num).toDouble()
            : 0.0);
    f['lab_state'] = stateEnc;

    // Year Normalized (2015 fixed for model)
    f['year'] = 2015;
    f['year_normalized'] = (2015.0 - 2012.0) / (2026.0 - 2012.0);

    // Cross Interactions
    double fever = (f['FEVER'] != null && (f['FEVER'] as num) > 0) ? 1.0 : 0.0;
    double cough = (f['COUGH'] != null && (f['COUGH'] as num) > 0) ? 1.0 : 0.0;
    double headache =
        (f['HEADACHE'] != null && (f['HEADACHE'] as num) > 0) ? 1.0 : 0.0;
    double patientType =
        (f['PATIENTTYPE'] is num) ? (f['PATIENTTYPE'] as num).toDouble() : 1.0;

    f['monsoon_respiratory'] = isMonsoon * respSum;
    f['winter_respiratory'] = isWinter * respSum;
    f['monsoon_fever'] = isMonsoon * fever;
    f['state_season'] = stateEnc * 10.0 + season;
    f['district_season'] = distEnc * 10.0 + season;
    f['district_month'] = distEnc * 100.0 + month;

    f['state_respiratory'] = stateEnc * respSum;
    f['state_fever'] = stateEnc * fever;
    f['state_gi'] = stateEnc * giSum;

    f['fever_respiratory'] = fever * respSum;
    f['fever_gi'] = fever * giSum;
    f['fever_neuro'] = fever * neuroSum;
    f['fever_skin'] = fever * skinSum;
    f['fever_duration'] = fever * duration;
    f['fever_headache'] = fever * headache;
    f['fever_cough'] = fever * cough;

    final severityScore = totalSymptoms * duration;
    f['severity_score'] = severityScore;
    f['age_symptom'] = age * totalSymptoms;
    f['age_duration'] = age * duration;
    f['patienttype_age'] = patientType * ageGroup;
    f['sex_respiratory'] = sexVal * respSum;
    f['duration_symptom_ratio'] = duration / (totalSymptoms + 1.0);

    // Syndrome Interactions
    double syndromeEnc = (f['Syndrome_encoded'] is num)
        ? (f['Syndrome_encoded'] as num).toDouble()
        : ((f['syndrome'] is num) ? (f['syndrome'] as num).toDouble() : 0.0);
    f['Syndrome_encoded'] = syndromeEnc;

    f['syndrome_fever'] = syndromeEnc * fever;
    f['syndrome_respiratory'] = syndromeEnc * respSum;
    f['syndrome_gi'] = syndromeEnc * giSum;
    f['syndrome_neuro'] = syndromeEnc * neuroSum;
    f['syndrome_skin'] = syndromeEnc * skinSum;
    f['syndrome_systemic'] = syndromeEnc * sysSum;
    f['syndrome_severity'] = syndromeEnc * severityScore;
    f['syndrome_age'] = syndromeEnc * age;
    f['syndrome_symptom_count'] = syndromeEnc * totalSymptoms;

    return f;
  }
}
