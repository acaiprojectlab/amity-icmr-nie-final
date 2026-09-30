import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/metadata_models.dart';

class ReferenceDataService {
  static final ReferenceDataService instance = ReferenceDataService._init();
  ReferenceDataService._init();

  Map<String, dynamic>? _modelConfig;
  Map<String, StateInfo>? _statesMap;
  List<SyndromeOption>? _syndromes;
  List<String>? _pathogens;

  Map<String, dynamic> get modelConfig => _modelConfig!;
  Map<String, StateInfo> get statesMap => _statesMap!;
  List<SyndromeOption> get syndromes => _syndromes!;
  List<String> get pathogens => _pathogens!;

  bool get isLoaded =>
      _modelConfig != null &&
      _statesMap != null &&
      _syndromes != null &&
      _pathogens != null;

  Future<void> loadAll() async {
    if (isLoaded) return;

    // 1. Model Config
    final configStr =
        await rootBundle.loadString('assets/data/model_config.json');
    _modelConfig = json.decode(configStr) as Map<String, dynamic>;

    // 2. State & District Map
    final statesStr =
        await rootBundle.loadString('assets/data/state_district_map.json');
    final Map<String, dynamic> rawStates = json.decode(statesStr);
    _statesMap = rawStates.map(
        (k, v) => MapEntry(k, StateInfo.fromJson(v as Map<String, dynamic>)));

    // 3. Syndrome Mapping
    final syndromeStr =
        await rootBundle.loadString('assets/data/syndrome_mapping.json');
    final List<dynamic> rawSyndromes = json.decode(syndromeStr);
    _syndromes = rawSyndromes
        .map((s) => SyndromeOption.fromJson(s as Map<String, dynamic>))
        .toList();

    // 4. Pathogen List
    final pathogenStr =
        await rootBundle.loadString('assets/data/pathogen_list.json');
    final List<dynamic> rawPathogens = json.decode(pathogenStr);
    _pathogens = rawPathogens.cast<String>();
  }

  Map<String, String> get symptomDisplayNames {
    final sdn =
        _modelConfig?['symptom_display_names'] as Map<String, dynamic>? ?? {};
    return sdn.map((k, v) => MapEntry(k, v.toString()));
  }

  List<String> get allSymptoms {
    final syms = _modelConfig?['symptoms'] as List<dynamic>? ?? [];
    return syms.cast<String>();
  }
}
