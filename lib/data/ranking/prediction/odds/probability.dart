/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/place_evaluation.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/util.dart';

/// Represents a prediction probability with various odds formats.
class PredictionProbability {
  /// The minimum possible odds.
  static const worstPossibleOddsDefault = 1.0001;
  /// The maximum possible odds.
  static const bestPossibleOddsDefault = 10000.0;

  Map<String, double> info;

  /// The house edge for parlays.
  static const parlayHouseEdge = 0.09;
  /// The house edge for standard wagers.
  static const standardHouseEdge = 0.05;

  final double worstPossibleOdds;
  final double bestPossibleOdds;

  /// The raw probability (0.0 to 1.0).
  final double probability;

  /// The house edge, as a percentage.
  ///
  /// House edge reduces the payout.
  final double houseEdge;

  /// If the probability was calculated from a Monte Carlo simulation (whether calculated
  /// as part of this object or passed in), this will be the simulation result(s).
  ProbabilitySimulationResult? simulationResult;

  /// If this probably ran its own Monte Carlo simulation, this will be true.
  ///
  /// Has no meaning if [simulationResult] is null.
  bool ranOwnSimulation = false;

  PredictionProbability(this.probability, {
    this.houseEdge = 0.00,
    this.worstPossibleOdds = worstPossibleOddsDefault,
    this.bestPossibleOdds = bestPossibleOddsDefault,
    this.info = const{},
    this.simulationResult,
    this.ranOwnSimulation = false,
  }) {
    if (probability < 0 || probability > 1) {
      throw ArgumentError("Probability must be between 0 and 1, actual: $probability");
    }
  }

  factory PredictionProbability.fromRawProbability(double rawProbability, {
    double? houseEdge,
    double? bestPossibleOdds,
    double? worstPossibleOdds,
  }) {
    return PredictionProbability(rawProbability,
    houseEdge: houseEdge ?? standardHouseEdge,
    bestPossibleOdds: bestPossibleOdds ?? bestPossibleOddsDefault,
    worstPossibleOdds: worstPossibleOdds ?? worstPossibleOddsDefault,
    );
  }

  factory PredictionProbability.fromDecimalOdds(double decimalOdds, {
    double? houseEdge,
    double? bestPossibleOdds,
    double? worstPossibleOdds,
  }) {
    return PredictionProbability(1 / decimalOdds,
      houseEdge: houseEdge ?? standardHouseEdge,
      bestPossibleOdds: bestPossibleOdds ?? bestPossibleOddsDefault,
      worstPossibleOdds: worstPossibleOdds ?? worstPossibleOddsDefault,
    );
  }

  /// Calculate the probability of a parlay over the given predictions.
  factory PredictionProbability.fromParlayPredictions({
    required List<UserPrediction> predictions,
    required Map<UserPrediction, PredictionProbability> predictionProbabilities,
    double? houseEdge,
    double? houseEdgePerLeg,
    double? bestPossibleOdds,
    double? worstPossibleOdds,
  }) {
    // For a parlay, we need the probability that ALL predictions are correct
    // This is the product of individual probabilities, assuming independence
    var parlayProbability = 1.0;

    houseEdge ??= parlayHouseEdge;

    for (var leg in predictions) {
      var predictionProb = predictionProbabilities[leg]!.clampedRawProbability;
      if(houseEdgePerLeg != null) {
        houseEdge = houseEdge! * (1 + houseEdgePerLeg);
      }
      parlayProbability *= predictionProb;
    }

    var placePredictions = predictions.where((prediction) => prediction is PlacePrediction).map((prediction) => prediction as PlacePrediction).toList();
    var fullness = Parlay.parlayFillProportion(placePredictions).clamp(0.0, 1.0);
    // var legCount = predictions.length;

    // For parlays more than 75% full, decrease the probability by between 0% and 25%.
    // Probability is our estimate that the parlay is correct, so we decrease it to make
    // the payout higher.
    // if(fullness > 0.75) {
    //   parlayProbability *= (1 - (0.25 * (fullness - 0.75)));
    // }

    // For parlays less than 50% full, increase the probability by between 0% and 25%.
    // This reduces the payout for easy parlays.
    if(fullness < 0.50) {
      parlayProbability *= (1 + (0.25 * (0.50 - fullness)));
    }

    // For parlays with more than 5 legs, decrease the probability by 2% per leg, capped
    // at 10 legs.
    // if(legCount > 5) {
    //   parlayProbability *= (1 - (0.02 * (min(legCount, 10) - 5)));
    // }

    return PredictionProbability(parlayProbability,
      houseEdge: houseEdge!,
      bestPossibleOdds: bestPossibleOdds ?? PredictionProbability.bestPossibleOddsDefault,
      worstPossibleOdds: worstPossibleOdds ?? PredictionProbability.worstPossibleOddsDefault,
    );
  }

  factory PredictionProbability.fromParlayLegs(List<Wager> legs, {
    double? houseEdge,
    double? houseEdgePerLeg,
    double? bestPossibleOdds,
    double? worstPossibleOdds,
  }) {
    var predictionProbabilities = <UserPrediction, PredictionProbability>{};
    var predictions = <UserPrediction>[];
    for(var leg in legs) {
      predictions.add(leg.prediction);
      predictionProbabilities[leg.prediction] = leg.probability;
    }
    return PredictionProbability.fromParlayPredictions(
      predictions: predictions,
      predictionProbabilities: predictionProbabilities,
      houseEdge: houseEdge,
      houseEdgePerLeg: houseEdgePerLeg,
      bestPossibleOdds: bestPossibleOdds,
      worstPossibleOdds: worstPossibleOdds,
    );
  }

  /// Calculate the probability that the competitor and place range in [placePrediction] will occur.
  /// [shootersToPredictions] is a map of shooter ratings to their predictions for
  /// all of [placePrediction]'s competitors, including the competitor in question.
  ///
  /// [shootersToPredictions] can be omitted if [simulationResult] is provided.
  ///
  /// [bestPossibleOdds] and [worstPossibleOdds] are the minimum and maximum possible odds,
  /// used to clamp the probability.
  ///
  /// [simulationResult] can be provided to avoid re-running the simulation if a cached simulation
  /// result is available. All other variables are only used if a simulation is not provided.
  ///
  /// [random] can be provided to use a specific random number generator (i.e. for consistency
  /// across multiple calculations).
  ///
  /// [disasterChance] is the chance that a simulation will be skipped due to a 'disaster'
  /// (DQ, gun breaking, etc.)
  ///
  /// [houseEdge] is the house edge to apply to the probability, defaulting to [standardHouseEdge].
  ///
  /// [trials] is the number of trials to run for the simulation, defaulting to 10000.
  factory PredictionProbability.fromPlacePrediction(
    PlacePrediction placePrediction,
    Map<ShooterRating, AlgorithmPrediction>? shootersToPredictions,
  {
    double bestPossibleOdds = bestPossibleOddsDefault,
    double worstPossibleOdds = worstPossibleOddsDefault,
    MonteCarloSimulationResult? simulationResult,
    double? placeDelta,
    Random? random,
    double disasterChance = 0.01,
    double? houseEdge,
    int trials = 10000,
  }) {
    /// Calculate the probability that a shooter finishes within the specified place range
    // Use Monte Carlo simulation with the actual prediction data
    // mean = average expected score from 1000 Monte Carlo runs
    // oneSigma = standard deviation of those runs
    // ciOffset = trend shift (-0.9 to 0.9)

    if(shootersToPredictions == null && simulationResult == null) {
      throw ArgumentError("Either shootersToPredictions or simulationResult must be provided.");
    }
    bool ranOwnSimulation = simulationResult == null;

    if(simulationResult == null) {
      AlgorithmPrediction? targetPrediction = shootersToPredictions![placePrediction.shooter];
      if(targetPrediction == null) {
        throw ArgumentError("Shooter prediction not found for ${placePrediction.shooter.name}");
      }

      simulationResult = runOddsSimulation(
        target: placePrediction.shooter,
        shootersToPredictions: shootersToPredictions,
        trials: trials,
        random: random,
        disasterChance: disasterChance,
      );
    }

    final actualTrials = simulationResult.places.length;
    double probability;

    if(placeDelta != null) {
      // Continuous place evaluation: fractional contribution at boundaries so probability
      // is smooth in delta (same logic as Bayesian odds place evaluation).
      double sum = 0.0;
      for(var place in simulationResult.places) {
        final s = placeShifted(place, placeDelta);
        sum += placeRangeContribution(s, placePrediction.bestPlace, placePrediction.worstPlace);
      }
      final raw = sum / actualTrials;
      if(actualTrials <= 1) {
        probability = raw.clamp(0.0, 1.0);
      }
      else {
        final minProbability = 1 / actualTrials;
        final maxProbability = (actualTrials - 1) / actualTrials;
        probability = raw.clamp(minProbability, maxProbability);
      }
    }
    else {
      var successes = 0;
      for(var place in simulationResult.places) {
        if(place >= placePrediction.bestPlace && place <= placePrediction.worstPlace) {
          successes++;
        }
      }
      final minProbability = 1 / actualTrials;
      final maxProbability = (actualTrials - 1) / actualTrials;
      probability = (successes / actualTrials).clamp(minProbability, maxProbability);
    }

    Map<String, double> info = {};
    info[PlacePrediction.minPlaceInfo] = simulationResult.places.min.toDouble();
    info[PlacePrediction.maxPlaceInfo] = simulationResult.places.max.toDouble();
    info[PlacePrediction.medianPlaceInfo] = simulationResult.places.median.toDouble();
    info[PlacePrediction.meanPlaceInfo] = simulationResult.places.average;
    info[PlacePrediction.stdDevPlaceInfo] = simulationResult.places.stdDev();

    return PredictionProbability(
      probability,
      houseEdge: houseEdge ?? standardHouseEdge,
      worstPossibleOdds: worstPossibleOdds,
      bestPossibleOdds: bestPossibleOdds,
      info: info,
      simulationResult: ProbabilitySimulationResult(targetResult: simulationResult),
      ranOwnSimulation: ranOwnSimulation,
    );
  }

  /// Calculate the probability that a shooter finishes within the specified percentage range.
  /// [shootersToPredictions] is a map of shooter ratings to their predictions for
  /// all of [percentagePrediction]'s competitors, including the competitor in question.
  ///
  /// [shootersToPredictions] can be omitted if [simulationResult] is provided.
  ///
  /// [bestPossibleOdds] and [worstPossibleOdds] are the minimum and maximum possible odds,
  /// used to clamp the probability.
  ///
  /// [simulationResult] can be provided to avoid re-running the simulation if a cached simulation
  /// result is available. All other variables are only used if a simulation is not provided.
  ///
  /// [random] can be provided to use a specific random number generator (i.e. for consistency
  /// across multiple calculations).
  ///
  /// [disasterChance] is the chance that a simulation will be skipped due to a 'disaster'
  /// (DQ, gun breaking, etc.)
  ///
  /// [houseEdge] is the house edge to apply to the probability, defaulting to [standardHouseEdge].
  ///
  /// [trials] is the number of trials to run for the simulation, defaulting to 10000.
  factory PredictionProbability.fromPercentagePrediction(
    PercentagePrediction percentagePrediction,
    Map<ShooterRating, AlgorithmPrediction>? shootersToPredictions,
  {
    double bestPossibleOdds = bestPossibleOddsDefault,
    double worstPossibleOdds = worstPossibleOddsDefault,
    MonteCarloSimulationResult? simulationResult,
    double? ratioDelta,
    Random? random,
    double disasterChance = 0.01,
    double? houseEdge,
    int trials = 10000,
  }) {
    /// Calculate the probability that a shooter finishes within the specified place range
    // Use Monte Carlo simulation with the actual prediction data
    // mean = average expected score from 1000 Monte Carlo runs
    // oneSigma = standard deviation of those runs
    // ciOffset = trend shift (-0.9 to 0.9)

    if(shootersToPredictions == null && simulationResult == null) {
      throw ArgumentError("Either shootersToPredictions or simulationResult must be provided.");
    }

    var successes = 0;

    bool ranOwnSimulation = simulationResult == null;

    if(simulationResult == null) {
      simulationResult ??= runOddsSimulation(
        target: percentagePrediction.shooter,
        shootersToPredictions: shootersToPredictions!,
        trials: trials,
        random: random,
        disasterChance: disasterChance,
      );
    }

    for(var percentage in simulationResult.percentages) {
      double actualPercentage = percentage;
      if(ratioDelta != null && ratioDelta != 0) {
        actualPercentage += ratioDelta;
      }
      if(percentagePrediction.above) {
        if(actualPercentage >= percentagePrediction.ratio) {
          successes++;
        }
      }
      else {
        if(actualPercentage <= percentagePrediction.ratio) {
          successes++;
        }
      }
    }

    final actualTrials = simulationResult.percentages.length;

    var minProbability = 1 / actualTrials;
    var maxProbability = (actualTrials - 1) / actualTrials;
    var probability = (successes / actualTrials).clamp(minProbability, maxProbability);

    Map<String, double> info = {};
    info[PercentagePrediction.minPercentageInfo] = simulationResult.percentages.min.toDouble();
    info[PercentagePrediction.maxPercentageInfo] = simulationResult.percentages.max.toDouble();
    info[PercentagePrediction.medianPercentageInfo] = simulationResult.percentages.median;
    info[PercentagePrediction.meanPercentageInfo] = simulationResult.percentages.average;
    info[PercentagePrediction.stdDevPercentageInfo] = simulationResult.percentages.stdDev();

    return PredictionProbability(
      probability,
      houseEdge: houseEdge ?? standardHouseEdge,
      worstPossibleOdds: worstPossibleOdds,
      bestPossibleOdds: bestPossibleOdds,
      info: info,
      simulationResult: ProbabilitySimulationResult(targetResult: simulationResult),
      ranOwnSimulation: ranOwnSimulation,
    );
  }

  /// Calculate the probability that a shooter finishes within the specified percentage spread range.
  /// [shootersToPredictions] is a map of shooter ratings to their predictions for
  /// all of [percentageSpreadPrediction]'s competitors, including the competitor in question.
  ///
  /// [bestPossibleOdds] and [worstPossibleOdds] are the minimum and maximum possible odds,
  /// used to clamp the probability.
  ///
  /// [favoriteSimulationResult] and [underdogSimulationResult] can be provided to avoid re-running the
  /// simulation if a cached simulation result is available. All other variables are only used if a
  /// simulation is not provided.
  ///
  /// [random] can be provided to use a specific random number generator (i.e. for consistency
  /// across multiple calculations).
  ///
  /// [disasterChance] is the chance that a simulation will be skipped due to a 'disaster'
  /// (DQ, gun breaking, etc.)
  ///
  /// [houseEdge] is the house edge to apply to the probability, defaulting to [standardHouseEdge].
  ///
  /// [trials] is the number of trials to run for the simulation, defaulting to 10000.
  factory PredictionProbability.fromPercentageSpreadPrediction(
    PercentageSpreadPrediction percentageSpreadPrediction,
    Map<ShooterRating, AlgorithmPrediction>? shootersToPredictions,
  {
    double bestPossibleOdds = bestPossibleOddsDefault,
    double worstPossibleOdds = worstPossibleOddsDefault,
    MonteCarloSimulationResult? favoriteSimulationResult,
    MonteCarloSimulationResult? underdogSimulationResult,
    double? favoriteRatioDelta,
    double? underdogRatioDelta,
    Random? random,
    double disasterChance = 0.01,
    double? houseEdge,
    int trials = 10000,
  }) {
    var successes = 0;

    if(shootersToPredictions == null && (favoriteSimulationResult == null || underdogSimulationResult == null)) {
      throw ArgumentError("Either shootersToPredictions or both favoriteSimulationResult and underdogSimulationResult must be provided.");
    }

    if(favoriteSimulationResult != null && underdogSimulationResult != null) {
      if(favoriteSimulationResult.percentages.length != underdogSimulationResult.percentages.length) {
        throw ArgumentError("Favorite and underdog simulation results must have the same number of trials.");
      }
    }

    bool ranOwnSimulation = favoriteSimulationResult == null || underdogSimulationResult == null;
    if(favoriteSimulationResult == null) {
      favoriteSimulationResult ??= runOddsSimulation(
        target: percentageSpreadPrediction.favorite,
        shootersToPredictions: shootersToPredictions!,
        trials: trials,
        random: random,
        disasterChance: disasterChance,
      );
    }
    if(underdogSimulationResult == null) {
      underdogSimulationResult ??= runOddsSimulation(
        target: percentageSpreadPrediction.underdog,
        shootersToPredictions: shootersToPredictions!,
        trials: trials,
        random: random,
        disasterChance: disasterChance,
      );
    }

    final actualTrials = favoriteSimulationResult.percentages.length;
    var predictedGaps = <double>[];
    for(int i = 0; i < actualTrials; i++) {
      double favoritePercentage = favoriteSimulationResult.percentages[i];
      if(favoriteRatioDelta != null && favoriteRatioDelta != 0) {
        favoritePercentage += favoriteRatioDelta;
      }
      double underdogPercentage = underdogSimulationResult.percentages[i];
      if(underdogRatioDelta != null && underdogRatioDelta != 0) {
        underdogPercentage += underdogRatioDelta;
      }
      var gap = favoritePercentage - underdogPercentage;
      predictedGaps.add(gap);
      if(percentageSpreadPrediction.favoriteCovers) {
        if(gap >= percentageSpreadPrediction.ratioSpread) {
          successes++;
        }
      }
      else {
        if(gap <= percentageSpreadPrediction.ratioSpread) {
          successes++;
        }
      }
    }

    var minProbability = 1 / actualTrials;
    var maxProbability = (actualTrials - 1) / actualTrials;
    var probability = (successes / actualTrials).clamp(minProbability, maxProbability);

    Map<String, double> info = {};
    info[PercentageSpreadPrediction.minPercentageSpreadInfo] = predictedGaps.min.toDouble();
    info[PercentageSpreadPrediction.maxPercentageSpreadInfo] = predictedGaps.max.toDouble();
    info[PercentageSpreadPrediction.medianPercentageSpreadInfo] = predictedGaps.median;
    info[PercentageSpreadPrediction.meanPercentageSpreadInfo] = predictedGaps.average;
    info[PercentageSpreadPrediction.stdDevPercentageSpreadInfo] = predictedGaps.stdDev() * 2;

    return PredictionProbability(
      probability,
      houseEdge: houseEdge ?? standardHouseEdge,
      worstPossibleOdds: worstPossibleOdds,
      bestPossibleOdds: bestPossibleOdds,
      info: info,
      simulationResult: ProbabilitySimulationResult(targetResult: favoriteSimulationResult, underdogResult: underdogSimulationResult),
      ranOwnSimulation: ranOwnSimulation,
    );
  }

  /// Get the raw probability.
  double get rawProbability => probability;

  /// Get the raw probability, clamped to between [bestPossibleOdds] and [worstPossibleOdds].
  double get clampedRawProbability {
    var clampedRawDecimalOdds = rawDecimalOdds.clamp(worstPossibleOdds, bestPossibleOdds);
    return 1.0 / clampedRawDecimalOdds;
  }

  /// Get the probability adjusted for house edge.
  double get probabilityWithHouseEdge => probability / (1 - houseEdge);

  /// Get the raw decimal odds (before house edge).
  double get rawDecimalOdds => 1.0 / probability;

  /// Get the decimal odds (after house edge), clamped between worstPossibleOdds and bestPossibleOdds.
  double get decimalOdds => (1 / probabilityWithHouseEdge).clamp(worstPossibleOdds, bestPossibleOdds);

  /// Get the fractional odds as a string.
  String get fractionalOdds {
    var numerator = decimalOdds - 1.0;

    // Convert to fractional odds (e.g., 2.5 -> 3/2)
    // Find the simplest fraction representation
    var gcd = _gcd((numerator * 100).round(), 100);
    var num = (numerator * 100).round() ~/ gcd;
    var den = 100 ~/ gcd;

    return "$num/$den";
  }

  /// Get the moneyline odds as a string.
  String get moneylineOdds {
    if(decimalOdds == 2.0) {
      return "+100";
    }
    else if (decimalOdds > 2.0) {
      // Positive moneyline for underdogs
      var payout = (decimalOdds - 1.0) * 100;
      return "+${payout.round()}";
    } else {
      // Negative moneyline for favorites
      var stake = -100 / (decimalOdds - 1.0);
      return "${stake.round()}";
    }
  }

  String get rawMoneylineOdds {
    if(rawDecimalOdds == 2.0) {
      return "+100";
    }
    else if (rawDecimalOdds > 2.0) {
      // Positive moneyline for underdogs
      var payout = (rawDecimalOdds - 1.0) * 100;
      return "+${payout.round()}";
    } else {
      // Negative moneyline for favorites
      var stake = -100 / (rawDecimalOdds - 1.0);
      return "${stake.round()}";
    }
  }

  int _gcd(int a, int b) {
    while (b != 0) {
      var temp = b;
      b = a % b;
      a = temp;
    }
    return a;
  }

  PredictionProbability copyWith({
    double? probability,
    double? houseEdge,
    double? worstPossibleOdds,
    double? bestPossibleOdds,
    Map<String, double>? info,
  }) => PredictionProbability(
    probability ?? this.probability,
    houseEdge: houseEdge ?? this.houseEdge,
    worstPossibleOdds: worstPossibleOdds ?? this.worstPossibleOdds,
    bestPossibleOdds: bestPossibleOdds ?? this.bestPossibleOdds,
    info: info ?? this.info,
  );
}

class ProbabilitySimulationResult {
  final MonteCarloSimulationResult targetResult;
  final MonteCarloSimulationResult? underdogResult;

  ProbabilitySimulationResult({
    required this.targetResult,
    this.underdogResult,
  });
}