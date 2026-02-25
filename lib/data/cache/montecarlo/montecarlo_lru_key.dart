
import 'package:shooting_sports_analyst/util.dart';

/// A key for a Monte Carlo simulation result for a given shooter in a given prediction set
/// with a given number of trials.
class MonteCarloSimulationLruKey {
  /// The ID of the prediction set against whose predictions the Monte Carlo simulation was run.
  final int predictionSetId;

  /// The number of trials run in the Monte Carlo simulation.
  final int trials;

  /// The member number of the shooter whose predictions this key points to.
  ///
  /// For shooters with multiple known member numbers, all should be cached.
  final String memberNumber;

  MonteCarloSimulationLruKey({
    required this.predictionSetId,
    required this.trials,
    required this.memberNumber,
  });

  @override
  bool operator ==(Object other) {
    if(other is! MonteCarloSimulationLruKey) return false;

    if(predictionSetId != other.predictionSetId) return false;
    if(trials != other.trials) return false;
    if(memberNumber != other.memberNumber) return false;

    return true;
  }

  @override
  int get hashCode => combineHashList64([predictionSetId.stableHash64, trials.stableHash64, memberNumber.stableHash64]);
}