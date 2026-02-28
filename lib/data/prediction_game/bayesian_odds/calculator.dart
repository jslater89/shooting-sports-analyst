
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/config.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/wager_data.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/providers.dart';

final _log = SSALogger("BayesianOddsCalculator");

/// A calculation function for Bayesian odds adjustment, set up to be runnable
/// with [Isolate.run] (i.e. including only objects that can be sent over
/// [SendPort]s).
///
/// Calculates the Bayesian odds update for a given set of prior predictions and
/// a set of Monte Carlo samples.
///
/// [subject] is the individual comeptitor for whom the odds update
/// is being calculated.
///
/// [subjectHistoryLength] is the length of the history of the subject.
///
/// [wagers] is the list of wagers to use for the Bayesian odds update.
/// Use [BayesianOddsWager.fromDbWager] to convert a [DbWager] to a [BayesianOddsWager].
///
/// [subjectMonteCarlo] is the Monte Carlo simulation results for the subject.
///
Future<double> calculateBayesianOddsUpdate({
  /// The configuration for the Bayesian odds update.
  required BayesianOddsConfig config,
  required int subjectHistoryLength,
  required List<BayesianOddsWager> wagers,
  required MonteCarloSimulationResult subjectMonteCarlo,
}) async {
  FlutterOrNative.debugModeProvider = ServerDebugProvider(isMultiIsolate: false);
  FlutterOrNative.isolateModeProvider = ServerDebugProvider(isMultiIsolate: false);
  SSALogger.fileOutput = false;

  final type = wagers.first.prediction.type;
  for(var wager in wagers) {
    if(wager.prediction.type != type) {
      throw ArgumentError("All wagers must have the same prediction type.");
    }
  }

  double nEff;
  _log.v("nEff calculation: ${config.nEffScale} * log(1 + ${subjectHistoryLength}).clamp(${config.nEffMin}, ${config.nEffMax})");
  nEff = (config.nEffScale * log(1 + subjectHistoryLength)).clamp(config.nEffMin, config.nEffMax);
  _log.v("nEff: $nEff");

  final Map<BayesianOddsWager, double> weight = {};
  final Map<BayesianOddsWager, Map<BayesianOddsWager, double>> additionalWeight = {};
  final Map<BayesianOddsWager, double> pShifted = {};
  final Map<BayesianOddsWager, double> alpha = {};
  final Map<BayesianOddsWager, double> pPosterior = {};

  // TODO: similarity calculation between wagers
  /*
  We do actually need to calculate similarity between wagers, because otherwise we underweight
  closely-related wagers. Consider two wagers: Smith >= 80%, weight 5. Both of these add
  5 * (p_shifted - p_posterior) to the error, but p_posterior is the same for both, so optimizing
  delta for one necessarily optimizes delta for the other. The pair has impact when there are
  other predictions at play, counting for more in the sum-of-errors calculation, but we're still
  losing signal—multiple predictions at or near one point should make a bigger hump in the
  new-information distribution.

  A simple fix is to percolate weight between wagers. Each wager gets a raw and effective
  weight. For each wager:

  1. Find nearby wagers. For place range wagers, any overlap between ranges will do. For
  percent wagers, look for within a few percent.
  2. Each nearby wager adds similarity * nearby_raw_weight / nearby_count to the current
     wager's effective weight.
     Similarity can be Jaccard index for place range, and exponential decay for percent.
  3. The algorithm progresses as normal, using effective weight.

  This adds extra bulk to each prior where there's a stack of them. This knob should perhaps
  be turned with caution: it makes _every_ prior stronger, which means that large aggregations
  of wagers pull more strongly than they would in the merged-market case. Perhaps use the
  raw weight as the multiplier in sum-of-squared-errors, but use the effective weight to calculate
  the posterior in the prep code.

  We can reduce the time complexity of this by sorting wagers by some measure (percentage, or
  center of place range), and only considering certain nearby wagers (maybe up to N), but
  that may be premature optimization.
  */

  for(var wager in wagers) {
    additionalWeight[wager] = {};
    int nearbyCount = 0;
    for(var otherWager in wagers) {
      if(wager == otherWager) continue;

      final similarity = _similarity(wager, otherWager);
      if(similarity == 0.0) continue;
      if(similarity.isNaN) {
        _log.w("Similarity between ${wager.prediction.toString()} and ${otherWager.prediction.toString()} is NaN.");
        continue;
      }

      final otherWeight = otherWager.calculateWeight(config);
      additionalWeight[wager]![otherWager] = similarity * otherWeight;
      nearbyCount++;
    }

    for(var similarityEntry in additionalWeight[wager]!.entries) {
      additionalWeight[wager]![similarityEntry.key] = similarityEntry.value / nearbyCount;
    }
  }


  // Calculate the weights and model probabilities for each wager.
  for(var wager in wagers) {
    _log.v("Initial data for ${wager.prediction.toString()}:");
    weight[wager] = wager.calculateWeight(config, logComponents: true);

    if(type == DbPredictionType.place) {
      pShifted[wager] = wager.evaluatePlaceAgainstSimulation(monteCarlo: subjectMonteCarlo);
    }
    else if(type == DbPredictionType.percentage) {
      pShifted[wager] = wager.evaluatePercentAgainstSimulation(monteCarlo: subjectMonteCarlo);
    }
    else {
      throw ArgumentError("Unsupported prediction type: ${type}");
    }

    final posteriorWeight = weight[wager]! + additionalWeight[wager]!.values.sum;
    alpha[wager] = pShifted[wager]! * nEff;
    pPosterior[wager] = (alpha[wager]! + posteriorWeight) / (nEff + posteriorWeight);

    _log.v("Weight for ${wager.prediction.toString()}: ${weight[wager]!.toStringAsFixed(4)}");
    _log.v("Weight from nearby wagers: ${additionalWeight[wager]!.entries.map((e) => "${e.key.prediction.toString()}: ${e.value.toStringAsFixed(4)}").join(", ")}");
    _log.v("Alpha: ${alpha[wager]!.toStringAsFixed(4)}");
    _log.v("Prior: ${pShifted[wager]!.toStringAsFixed(4)}");
    _log.v("Posterior: ${pPosterior[wager]!.toStringAsFixed(4)}");
    _log.v("Initial error: ${_objective(pShifted: pShifted[wager]!, pPosterior: pPosterior[wager]!, weight: weight[wager]!)}");
    _log.v("\n");
  }

  // Lo/hi search bounds for the delta calculation, in places or ratio-space percentage points.
  double searchLo = type == DbPredictionType.place ? -40.0 : -0.3;
  double searchHi = type == DbPredictionType.place ? 40.0 : 0.3;

  double delta = _calculateDelta(
    wagers: wagers,
    type: type,
    subjectMonteCarlo: subjectMonteCarlo,
    weight: weight,
    pShifted: pShifted,
    pPosterior: pPosterior,
    searchLo: searchLo,
    searchHi: searchHi,
  );

  return delta;
}

double _similarity(BayesianOddsWager a, BayesianOddsWager b, {double percentSteepness = 20, double percentMaxDistance = 0.05}) {
  if(a.prediction.type == DbPredictionType.place && b.prediction.type == DbPredictionType.place) {
    return _jaccardIndex(a, b);
  }
  else if(a.prediction.type == DbPredictionType.percentage && b.prediction.type == DbPredictionType.percentage) {
    return _percentageSimilarity(a, b, steepness: percentSteepness, maxDistance: percentMaxDistance);
  }
  _log.w("Similarity calculation between ${a.prediction.toString()} and ${b.prediction.toString()} is not supported.");
  return 0.0;
}

double _jaccardIndex(BayesianOddsWager wager, BayesianOddsWager otherWager) {
  if(wager.prediction.type != DbPredictionType.place || otherWager.prediction.type != DbPredictionType.place) {
    throw ArgumentError("Jaccard index can only be calculated for place predictions.");
  }

  var (int a, int b) = (wager.prediction.bestPlace!, wager.prediction.worstPlace!);
  var (int x, int y) = (otherWager.prediction.bestPlace!, otherWager.prediction.worstPlace!);

  int left = max(a, x);
  int right = min(b, y);
  int intersection = max(0, right - left + 1);
  int size1 = b - a + 1;
  int size2 = y - x + 1;
  int union = size1 + size2 - intersection;
  if(union == 0) {
    return 0.0;
  }
  return intersection / union;
}

double _percentageSimilarity(BayesianOddsWager a, BayesianOddsWager b, {double steepness = 20, double maxDistance = 0.05}) {
  if(a.prediction.type != DbPredictionType.percentage || b.prediction.type != DbPredictionType.percentage) {
    throw ArgumentError("Percentage similarity can only be calculated for percentage predictions.");
  }

  double distance = (a.prediction.percentage! - b.prediction.percentage!).abs();
  if(distance > maxDistance) {
    return 0.0;
  }
  double x = distance / maxDistance;
  return 1 / (1 + exp(steepness * (x - 0.5)));
}

double _calculateDelta({
  required List<BayesianOddsWager> wagers,
  required DbPredictionType type,
  required MonteCarloSimulationResult subjectMonteCarlo,
  required Map<BayesianOddsWager, double> weight,
  required Map<BayesianOddsWager, double> pShifted,
  required Map<BayesianOddsWager, double> pPosterior,
  required double searchLo,
  required double searchHi,
}) {

  double gr = (sqrt(5) + 1) / 2;
  double a = searchLo, b = searchHi;
  double c = b - (b - a) / gr;
  double d = a + (b - a) / gr;

  for(int i = 0; i < 50; i++) {
    // _log.v("Iteration $i: a = ${a.toStringAsFixed(4)}, b = ${b.toStringAsFixed(4)}, c = ${c.toStringAsFixed(4)}, d = ${d.toStringAsFixed(4)}");
    if((b - a).abs() < 0.001) break;

    // Calculate shifted probabilities for each wager at c and d

    double objectiveC = 0.0;
    double objectiveD = 0.0;
    for(var wager in wagers) {
       final pShiftedC = wager.evaluateAgainstSimulation(type: type, delta: c, subjectMonteCarlo: subjectMonteCarlo);
       final pShiftedD = wager.evaluateAgainstSimulation(type: type, delta: d, subjectMonteCarlo: subjectMonteCarlo);

       objectiveC += _objective(pShifted: pShiftedC, pPosterior: pPosterior[wager]!, weight: weight[wager]!);
       objectiveD += _objective(pShifted: pShiftedD, pPosterior: pPosterior[wager]!, weight: weight[wager]!);
    }

    // _log.v("Error at c: ${objectiveC.toStringAsFixed(4)}");
    // _log.v("Error at d: ${objectiveD.toStringAsFixed(4)}");
    // _log.v("\n");

    if(objectiveC < objectiveD) {
      b = d;
    }
    else {
      a = c;
    }
    c = b - (b - a) / gr;
    d = a + (b - a) / gr;
  }

  return (a + b) / 2;
}

double _objective({
  required double pShifted,
  required double pPosterior,
  required double weight,
}) {
  return weight * (pShifted - pPosterior) * (pShifted - pPosterior);
}
