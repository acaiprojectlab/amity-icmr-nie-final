/// Metadata models for States, Districts, Syndromes, and Pathogens
library;

class StateInfo {
  final String stateName;
  final int stateEncoded;
  final List<DistrictInfo> districts;

  StateInfo({
    required this.stateName,
    required this.stateEncoded,
    required this.districts,
  });

  factory StateInfo.fromJson(Map<String, dynamic> json) {
    var distList = (json['districts'] as List<dynamic>?)
            ?.map((d) => DistrictInfo.fromJson(d as Map<String, dynamic>))
            .toList() ??
        [];
    return StateInfo(
      stateName: json['state_name'] as String,
      stateEncoded: json['state_encoded'] as int,
      districts: distList,
    );
  }
}

class DistrictInfo {
  final String name;
  final int encoded;

  DistrictInfo({
    required this.name,
    required this.encoded,
  });

  factory DistrictInfo.fromJson(Map<String, dynamic> json) {
    return DistrictInfo(
      name: json['name'] as String,
      encoded: json['encoded'] as int,
    );
  }
}

class SyndromeOption {
  final String overallSyndrome;
  final String syndromeLabel;
  final int encodedValue;

  SyndromeOption({
    required this.overallSyndrome,
    required this.syndromeLabel,
    required this.encodedValue,
  });

  factory SyndromeOption.fromJson(Map<String, dynamic> json) {
    return SyndromeOption(
      overallSyndrome: json['overall_syndrome'] as String,
      syndromeLabel: json['syndrome_label'] as String,
      encodedValue: json['encoded_value'] as int,
    );
  }
}
