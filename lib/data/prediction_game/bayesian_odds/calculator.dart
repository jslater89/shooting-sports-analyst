
import 'dart:math';

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
  */

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

    alpha[wager] = pShifted[wager]! * nEff;
    pPosterior[wager] = (alpha[wager]! + weight[wager]!) / (nEff + weight[wager]!);
    _log.v("Weight for ${wager.prediction.toString()}: ${weight[wager]!.toStringAsFixed(4)}");
    _log.v("Alpha for ${wager.prediction.toString()}: ${alpha[wager]!.toStringAsFixed(4)}");
    _log.v("Posterior for ${wager.prediction.toString()}: ${pPosterior[wager]!.toStringAsFixed(4)}");
    _log.v("Initial error for ${wager.prediction.toString()}: ${_objective(pShifted: pShifted[wager]!, pPosterior: pPosterior[wager]!, weight: weight[wager]!)}");
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
