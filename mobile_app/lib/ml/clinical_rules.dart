/// Clinical Rules & Syndrome-Based Virus Exclusions (ICMR Clinical Reference)
library;

class ClinicalRules {
  static const Map<String, String> virusNameAliases = {
    'respiratory adenovirus': 'adenovirus',
    'adenovirus': 'adenovirus',
  };

  static String normalizeVirusName(String name) {
    String key = name.trim().toLowerCase();
    return virusNameAliases[key] ?? key;
  }

  /// Excluded viruses per syndrome (0 to 8)
  static const Map<int, Set<String>> syndromeExcludedViruses = {
    0: {
      // ARI/Influenza Like Illness (ILI)
      'Dengue Virus', 'HIV', 'Haemophilus influenzae', 'Hepatitis A Virus',
      'Hepatitis B Virus', 'Hepatitis C Virus', 'Hepatitis E Virus',
      'Herpes Simplex Virus (HSV)', 'Human papillomavirus (HPV)',
      'Japanese Encephalitis', 'Kyasanur Forest Disease', 'Leptospira',
      'Norovirus', 'Rotavirus', 'Rubella',
      'Scrub typhus (Orientia tsutsugamushi)', 'Toxoplasma', 'Unknown',
      'West Nile virus (WNV)',
    },
    1: {
      // Acute Diarrheal Disease
      'HIV', 'Haemophilus influenzae', 'Hepatitis B Virus',
      'Hepatitis C Virus', 'Herpes Simplex Virus (HSV)',
      'Human papillomavirus (HPV)', 'Japanese Encephalitis',
      'Kyasanur Forest Disease', 'Mumps Virus', 'Parvovirus', 'Rubella',
      'Toxoplasma', 'Varicella zoster virus (VZV)', 'West Nile virus (WNV)',
    },
    2: {
      // Acute Encephalitis Syndrome (AES)
      'HIV', 'Haemophilus influenzae', 'Hepatitis A Virus',
      'Hepatitis B Virus', 'Hepatitis C Virus', 'Hepatitis E Virus',
      'Human papillomavirus (HPV)', 'Influenza A H1N1', 'Influenza A H3N2',
      'Influenza B Victoria', 'Metapneumovirus', 'Norovirus',
      'Other Influenza', 'Respiratory Adenovirus',
      'Respiratory Syncytial Virus (RSV)', 'Rhinovirus', 'Toxoplasma',
    },
    3: {
      // Conjunctivitis
      'HIV', 'Haemophilus influenzae', 'Hepatitis A Virus',
      'Hepatitis B Virus', 'Hepatitis C Virus', 'Leptospira', 'Mumps Virus',
      'Respiratory Syncytial Virus (RSV)',
      'Scrub typhus (Orientia tsutsugamushi)', 'Toxoplasma',
    },
    4: {
      // Fever with Rash
      'HIV', 'Haemophilus influenzae', 'Hepatitis A Virus',
      'Hepatitis B Virus', 'Hepatitis C Virus', 'Hepatitis E Virus',
      'Influenza A H1N1', 'Influenza A H3N2', 'Influenza B Victoria',
      'Respiratory Syncytial Virus (RSV)', 'Rotavirus', 'SARS-Cov-2',
      'Toxoplasma',
    },
    5: {
      // Hemorrhagic fever
      'Enterovirus', 'HIV', 'Haemophilus influenzae', 'Hepatitis A Virus',
      'Hepatitis E Virus', 'Herpes Simplex Virus (HSV)', 'Measles Virus',
      'Mumps Virus', 'Norovirus', 'Parvovirus', 'Respiratory Adenovirus',
      'Respiratory Syncytial Virus (RSV)', 'Rubella', 'Toxoplasma',
    },
    6: {
      // Jaundice of < 4 weeks
      'Chikungunya Virus', 'Enterovirus', 'HIV', 'Haemophilus influenzae',
      'Human papillomavirus (HPV)', 'Influenza A H1N1', 'Influenza A H3N2',
      'Influenza B Victoria', 'Measles Virus', 'Mumps Virus', 'Parvovirus',
      'Respiratory Adenovirus', 'Respiratory Syncytial Virus (RSV)',
      'Rhinovirus', 'Rotavirus', 'Rubella', 'Toxoplasma',
    },
    7: {
      // Only Fever < 7 days
      'HIV', 'Haemophilus influenzae', 'Toxoplasma',
    },
    8: {
      // Severe Acute Respiratory Infection (SARI)
      'Dengue Virus', 'HIV', 'Haemophilus influenzae', 'Hepatitis A Virus',
      'Hepatitis B Virus', 'Hepatitis C Virus', 'Hepatitis E Virus',
      'Herpes Simplex Virus (HSV)', 'Human papillomavirus (HPV)',
      'Japanese Encephalitis', 'Kyasanur Forest Disease', 'Leptospira',
      'Norovirus', 'Other Influenza', 'Rotavirus', 'Rubella',
      'Scrub typhus (Orientia tsutsugamushi)', 'Toxoplasma',
      'West Nile virus (WNV)',
    },
  };

  /// Build index set of excluded classes for a given syndrome
  static Set<int> getExcludedIndices(
      int? syndromeEncoded, Map<int, String> virusMapping) {
    if (syndromeEncoded == null) return {};
    final excludedNames = syndromeExcludedViruses[syndromeEncoded] ?? {};
    if (excludedNames.isEmpty) return {};

    final normalizedExcluded =
        excludedNames.map((n) => normalizeVirusName(n)).toSet();

    final result = <int>{};
    virusMapping.forEach((idx, name) {
      if (normalizedExcluded.contains(normalizeVirusName(name))) {
        result.add(idx);
      }
    });
    return result;
  }

  /// Rank probabilities, filter out excluded classes, and return top-k indices and excluded names
  static FilterResult filterTopK({
    required List<double> probabilities,
    required Map<int, String> virusMapping,
    required int? syndromeEncoded,
    int k = 5,
  }) {
    // Rank all indices descending by probability
    final indexedProbs = List.generate(probabilities.length, (i) => i);
    indexedProbs.sort((a, b) => probabilities[b].compareTo(probabilities[a]));

    final rawTopK = indexedProbs.take(k).toList();
    final excludedSet = getExcludedIndices(syndromeEncoded, virusMapping);

    final filtered =
        indexedProbs.where((idx) => !excludedSet.contains(idx)).toList();

    final topIndices = (filtered.isEmpty ? rawTopK : filtered).take(k).toList();

    // Identify which from the raw top-k were excluded
    final excludedFromView = rawTopK
        .where((i) => excludedSet.contains(i))
        .map((i) => virusMapping[i] ?? 'Virus $i')
        .toList();

    return FilterResult(
      topIndices: topIndices,
      excludedViruses: excludedFromView,
    );
  }
}

class FilterResult {
  final List<int> topIndices;
  final List<String> excludedViruses;

  FilterResult({
    required this.topIndices,
    required this.excludedViruses,
  });
}
