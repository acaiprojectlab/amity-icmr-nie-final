/// Prediction result data structures
library;

class RankedVirusPrediction {
  final int virusId;
  final String virusName;
  final double confidence; // Percentage (0 - 100)

  RankedVirusPrediction({
    required this.virusId,
    required this.virusName,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'virus_id': virusId,
        'virus': virusName,
        'confidence': confidence,
      };

  factory RankedVirusPrediction.fromJson(Map<String, dynamic> json) =>
      RankedVirusPrediction(
        virusId: json['virus_id'] as int,
        virusName: json['virus'] as String,
        confidence: (json['confidence'] as num).toDouble(),
      );
}

class SubClassificationResult {
  final int predictedSubVirusId;
  final String predictedSubVirusName;
  final double subConfidence;
  final List<RankedVirusPrediction> topSubPredictions;
  final List<String> excludedBySyndrome;
  final List<double> fullProbabilities;

  SubClassificationResult({
    required this.predictedSubVirusId,
    required this.predictedSubVirusName,
    required this.subConfidence,
    required this.topSubPredictions,
    required this.excludedBySyndrome,
    required this.fullProbabilities,
  });

  Map<String, dynamic> toJson() => {
        'predicted_sub_virus_id': predictedSubVirusId,
        'predicted_sub_virus': predictedSubVirusName,
        'sub_confidence': subConfidence,
        'top_5_sub_predictions':
            topSubPredictions.map((p) => p.toJson()).toList(),
        'excluded_by_syndrome': excludedBySyndrome,
      };
}

class FullPredictionResult {
  final int predictedVirusId;
  final String predictedVirusName;
  final double confidence; // Percentage
  final List<RankedVirusPrediction> top5Predictions;
  final List<String> excludedBySyndrome;
  final List<double> fullMajorProbabilities;
  final SubClassificationResult? subClassification;

  FullPredictionResult({
    required this.predictedVirusId,
    required this.predictedVirusName,
    required this.confidence,
    required this.top5Predictions,
    required this.excludedBySyndrome,
    required this.fullMajorProbabilities,
    this.subClassification,
  });

  Map<String, dynamic> toJson() => {
        'predicted_virus_id': predictedVirusId,
        'predicted_virus': predictedVirusName,
        'confidence': confidence,
        'top_5_predictions': top5Predictions.map((p) => p.toJson()).toList(),
        'excluded_by_syndrome': excludedBySyndrome,
        if (subClassification != null)
          'sub_classification': subClassification!.toJson(),
      };
}
