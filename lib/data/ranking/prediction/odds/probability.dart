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

  PredictionProbability(this.probability, {
    this.houseEdge = 0.00,
    this.worstPossibleOdds = worstPossibleOddsDefault,
    this.bestPossibleOdds = bestPossibleOddsDefault,
    this.info = const{},
  }) {
    if (probability <= 0 || probability >= 1) {
      throw ArgumentError("Probability must be between 0 and 1");
    }
  }

  /// Calculate the probability of a parlay over the given predictions.
  factory PredictionProbability.fromParlayPredictions({
    required List<UserPrediction> predictions,
    required Map<UserPrediction, PredictionProbability> predictionProbabilities,
    double? houseEdge,
    double? houseEdgePerLeg,
  }) {
    // For a parlay, we need the probability that ALL predictions are correct
    // This is the product of individual probabilities, assuming independence
    var parlayProbability = 1.0;

    houseEdge ??= parlayHouseEdge;

    for (var leg in predictions) {
      var predictionProb = predictionProbabilities[leg]!.rawProbability;
      if(houseEdgePerLeg != null) {
        houseEdge = houseEdge! * (1 + houseEdgePerLeg);
      }
      parlayProbability *= predictionProb;
    }

    var placePredictions = predictions.where((prediction) => prediction is PlacePrediction).map((prediction) => prediction as PlacePrediction).toList();
    var fullness = Parlay.parlayFillProportion(placePredictions).clamp(0.0, 1.0);
    var legCount = predictions.length;

    // For parlays more than 75% full, decrease the probability by between 0% and 25%.
    // Probability is our estimate that the parlay is correct, so we decrease it to make
    // the payout higher.
    if(fullness > 0.75) {
      parlayProbability *= (1 - (0.25 * (fullness - 0.75)));
    }
    // For parlays less than 50% full, increase the probability by between 0% and 25%.
    // This reduces the payout for easy parlays.
    else if(fullness < 0.50) {
      parlayProbability *= (1 + (0.25 * (0.50 - fullness)));
    }

    // For parlays with more than 5 legs, decrease the probability by 2% per leg, capped
    // at 10 legs.
    if(legCount > 5) {
      parlayProbability *= (1 - (0.02 * (min(legCount, 10) - 5)));
    }

    return PredictionProbability(parlayProbability, houseEdge: houseEdge!);
  }

  factory PredictionProbability.fromParlayLegs(List<Wager> legs, {
    double? houseEdge,
    double? houseEdgePerLeg,
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
      houseEdgePerLeg: houseEdgePerLeg
    );
  }

  /// Calculate the probability that the competitor and place range in [placePrediction] will occur.
  /// [shootersToPredictions] is a map of shooter ratings to their predictions for
  /// all of [placePrediction]'s competitors, including the competitor in question.
  factory PredictionProbability.fromPlacePrediction(
    PlacePrediction placePrediction,
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
  {
    Random? random,
    double disasterChance = 0.01,
    double? houseEdge,
    double bestPossibleOdds = bestPossibleOddsDefault,
    double worstPossibleOdds = worstPossibleOddsDefault,
  }) {
    /// Calculate the probability that a shooter finishes within the specified place range
    // Use Monte Carlo simulation with the actual prediction data
    // mean = average expected score from 1000 Monte Carlo runs
    // oneSigma = standard deviation of those runs
    // ciOffset = trend shift (-0.9 to 0.9)

    var trials = 10000;
    var successes = 0;

    var actualRandom = random ?? Random();
    var shooterPrediction = shootersToPredictions[placePrediction.shooter];
    if(shooterPrediction == null) {
      throw ArgumentError("Shooter prediction not found for ${placePrediction.shooter.name}");
    }

    var bestPlace = placePrediction.bestPlace;
    var worstPlace = placePrediction.worstPlace;

    var predictedPlaces = <int>[];

    for (var i = 0; i < trials; i++) {
      if(actualRandom.nextDouble() < disasterChance) {
        continue;
      }

      // Generate a random expected score for this shooter using a normal distribution

      // Adjust mean by up to 10% based on trend.
      var sigmaMultiplier = shooterPrediction.algorithm.predictionSettings.placeSigmaMultiplier;
      var finalSigma = shooterPrediction.oneSigma * sigmaMultiplier;
      var actualMean = shooterPrediction.mean + finalSigma * shooterPrediction.ciOffset;
      var z = _nextDistributedValue(actualRandom, shooterPrediction.ciOffset);
      var shooterExpectedScore = actualMean + finalSigma * z;

      // Generate random expected scores for all other shooters
      var otherExpectedScores = <double>[];
      for (var otherPred in shootersToPredictions.values) {
        if (otherPred == shooterPrediction) continue;

        var otherMean = otherPred.mean + otherPred.oneSigma * otherPred.ciOffset;
        var z = _nextDistributedValue(actualRandom, otherPred.ciOffset);
        var otherExpectedScore = otherMean + otherPred.oneSigma * z;

        otherExpectedScores.add(otherExpectedScore);
      }

      // Count how many shooters have higher expected scores (higher score = better placement)
      var betterCount = otherExpectedScores.where((score) => score > shooterExpectedScore).length;
      var place = betterCount + 1;

      predictedPlaces.add(place);

      if (place >= bestPlace && place <= worstPlace) {
        successes++;
      }
    }

    Map<String, double> info = {};
    info[PlacePrediction.minPlaceInfo] = predictedPlaces.min.toDouble();
    info[PlacePrediction.maxPlaceInfo] = predictedPlaces.max.toDouble();
    info[PlacePrediction.medianPlaceInfo] = predictedPlaces.median.toDouble();
    info[PlacePrediction.meanPlaceInfo] = predictedPlaces.average;
    info[PlacePrediction.stdDevPlaceInfo] = predictedPlaces.stdDev();

    var minProbability = 1 / trials;
    var maxProbability = (trials - 1) / trials;
    var probability = (successes / trials).clamp(minProbability, maxProbability);

    return PredictionProbability(
      probability,
      houseEdge: houseEdge ?? standardHouseEdge,
      worstPossibleOdds: worstPossibleOdds,
      bestPossibleOdds: bestPossibleOdds,
      info: info,
    );
  }

  factory PredictionProbability.fromPercentagePrediction(
    PercentagePrediction percentagePrediction,
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
  {
    Random? random,
    double disasterChance = 0.01,
    double? houseEdge,
    double bestPossibleOdds = bestPossibleOddsDefault,
    double worstPossibleOdds = worstPossibleOddsDefault,
  }) {
    /// Calculate the probability that a shooter finishes within the specified place range
    // Use Monte Carlo simulation with the actual prediction data
    // mean = average expected score from 1000 Monte Carlo runs
    // oneSigma = standard deviation of those runs
    // ciOffset = trend shift (-0.9 to 0.9)

    var trials = 10000;
    var successes = 0;

    var actualRandom = random ?? Random();
    var shooterPrediction = shootersToPredictions[percentagePrediction.shooter];
    if(shooterPrediction == null) {
      throw ArgumentError("Shooter prediction not found for ${percentagePrediction.shooter.name}");
    }
    var ratio = percentagePrediction.ratio;

    var predictedPercentages = <double>[];

    for (var i = 0; i < trials; i++) {
      if(actualRandom.nextDouble() < disasterChance) {
        continue;
      }

      // Generate a random expected score for this shooter using a normal distribution
      var sigmaMultiplier = shooterPrediction.algorithm.predictionSettings.percentSigmaMultiplier;
      var finalSigma = shooterPrediction.oneSigma * sigmaMultiplier;
      var actualMean = shooterPrediction.mean + finalSigma * shooterPrediction.ciOffset;
      var z = _nextDistributedValue(actualRandom, shooterPrediction.ciOffset);
      var shooterExpectedScore = actualMean + finalSigma * z;

      // Generate random expected scores for all other shooters
      var otherExpectedScores = <double>[];
      var bestExpectedScore = shooterExpectedScore;
      var minimumRatingScore = shooterExpectedScore;
      var bestRating = double.negativeInfinity;
      var worstRating = double.infinity;
      for (var otherPred in shootersToPredictions.values) {
        if (otherPred == shooterPrediction) continue;

        var otherMean = otherPred.mean + otherPred.oneSigma * otherPred.ciOffset;
        var z = _nextDistributedValue(actualRandom, otherPred.ciOffset);
        var otherExpectedScore = otherMean + otherPred.oneSigma * z;

        otherExpectedScores.add(otherExpectedScore);
        if(otherExpectedScore > bestExpectedScore) {
          bestExpectedScore = otherExpectedScore;
        }
        if(otherPred.shooter.rating > bestRating) {
          bestRating = otherPred.shooter.rating;
        }
        if(otherPred.shooter.rating < worstRating) {
          worstRating = otherPred.shooter.rating;
          minimumRatingScore = otherExpectedScore;
        }
      }

      // Check if this shooter's expected score is better than the percentage prediction
      double shooterRatio;

      // If the rating system outputs ratios, we need to renormalize so that the winner is 1.0
      if(shooterPrediction.algorithm.predictionsOutputRatios) {
        shooterExpectedScore = shooterExpectedScore / bestExpectedScore;
        minimumRatingScore = minimumRatingScore / bestExpectedScore;
        bestExpectedScore = 1.0;
      }

      if(shooterPrediction.algorithm.supportsRatioFloor) {
        var ratingDelta = bestRating - worstRating;
        var ratioFloor = shooterPrediction.algorithm.estimateRatioFloor(ratingDelta, settings: shooterPrediction.settings);
        var ratioMultiplier = 1.0 - ratioFloor;
        shooterRatio = ((shooterExpectedScore - minimumRatingScore) / (bestExpectedScore - minimumRatingScore)) * ratioMultiplier + ratioFloor;
      }
      else if(shooterPrediction.algorithm.predictionsOutputRatios) {
        shooterRatio = shooterExpectedScore;
      }
      else {
        throw UnsupportedError("Rating system ${shooterPrediction.algorithm} cannot generate percentage predictions");
      }
      predictedPercentages.add(shooterRatio);
      if(percentagePrediction.above ? shooterRatio >= ratio : shooterRatio <= ratio) {
        successes++;
      }
    }

    var minProbability = 1 / trials;
    var maxProbability = (trials - 1) / trials;
    var probability = (successes / trials).clamp(minProbability, maxProbability);

    Map<String, double> info = {};
    info[PercentagePrediction.minPercentageInfo] = predictedPercentages.min.toDouble();
    info[PercentagePrediction.maxPercentageInfo] = predictedPercentages.max.toDouble();
    info[PercentagePrediction.medianPercentageInfo] = predictedPercentages.median;
    info[PercentagePrediction.meanPercentageInfo] = predictedPercentages.average;
    info[PercentagePrediction.stdDevPercentageInfo] = predictedPercentages.stdDev();

    return PredictionProbability(
      probability,
      houseEdge: houseEdge ?? standardHouseEdge,
      worstPossibleOdds: worstPossibleOdds,
      bestPossibleOdds: bestPossibleOdds,
      info: info,
    );
  }

  factory PredictionProbability.fromPercentageSpreadPrediction(
    PercentageSpreadPrediction percentageSpreadPrediction,
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
  {
    Random? random,
    double disasterChance = 0.01,
    double? houseEdge,
    double bestPossibleOdds = bestPossibleOddsDefault,
    double worstPossibleOdds = worstPossibleOddsDefault,
  }) {
    /// Calculate the probability that a shooter finishes within the specified place range
    // Use Monte Carlo simulation with the actual prediction data
    // mean = average expected score from 1000 Monte Carlo runs
    // oneSigma = standard deviation of those runs
    // ciOffset = trend shift (-0.9 to 0.9)

    var trials = 10000;
    var successes = 0;

    var actualRandom = random ?? Random();
    var favoriteRating = percentageSpreadPrediction.favorite.rating;
    var underdogRating = percentageSpreadPrediction.underdog.rating;
    var favoritePrediction = shootersToPredictions[percentageSpreadPrediction.favorite];
    var underdogPrediction = shootersToPredictions[percentageSpreadPrediction.underdog];
    if(favoritePrediction == null || underdogPrediction == null) {
      throw ArgumentError("Shooter prediction not found for ${percentageSpreadPrediction.favorite.name} or ${percentageSpreadPrediction.underdog.name}");
    }

    var spreadRatio = percentageSpreadPrediction.ratioSpread;

    var predictedGaps = <double>[];

    for (var i = 0; i < trials; i++) {
      // TODO: figure out how to simulate disasters

      // Generate a random expected score for both the favorite and the underdog

      var favoriteActualMean = favoritePrediction.mean + favoritePrediction.oneSigma * favoritePrediction.ciOffset;
      var z = _nextDistributedValue(actualRandom, favoritePrediction.ciOffset);
      var favoriteExpectedScore = favoriteActualMean + favoritePrediction.oneSigma * z;

      var underdogActualMean = underdogPrediction.mean + underdogPrediction.oneSigma * underdogPrediction.ciOffset;
      z = _nextDistributedValue(actualRandom, underdogPrediction.ciOffset);
      var underdogExpectedScore = underdogActualMean + underdogPrediction.oneSigma * z;

      // Generate random expected scores for all other shooters
      var otherExpectedScores = <double>[];
      var bestExpectedScore = max(favoriteExpectedScore, underdogExpectedScore);
      var minimumRatingScore = favoriteRating < underdogRating ? favoriteExpectedScore : underdogExpectedScore;
      var bestRating = max(favoriteRating, underdogRating);
      var worstRating = min(favoriteRating, underdogRating);

      for (var otherPred in shootersToPredictions.values) {
        if (otherPred == favoritePrediction || otherPred == underdogPrediction) continue;

        var otherMean = otherPred.mean + otherPred.oneSigma * otherPred.ciOffset;
        var z = _nextDistributedValue(actualRandom, otherPred.ciOffset);
        var otherExpectedScore = otherMean + otherPred.oneSigma * z;

        otherExpectedScores.add(otherExpectedScore);
        if(otherExpectedScore > bestExpectedScore) {
          bestExpectedScore = otherExpectedScore;
        }
        if(otherPred.shooter.rating > bestRating) {
          bestRating = otherPred.shooter.rating;
        }
        if(otherPred.shooter.rating < worstRating) {
          worstRating = otherPred.shooter.rating;
          minimumRatingScore = otherExpectedScore;
        }
      }

      // If the rating system outputs ratios, we need to renormalize so that the winner is 1.0
      double favoriteRatio;
      double underdogRatio;
      if(favoritePrediction.algorithm.predictionsOutputRatios) {
        favoriteExpectedScore = favoriteExpectedScore / bestExpectedScore;
        underdogExpectedScore = underdogExpectedScore / bestExpectedScore;
        bestExpectedScore = 1.0;
      }

      if(favoritePrediction.algorithm.supportsRatioFloor) {
        // Check if this shooter's expected score is better than the percentage prediction
        var ratingDelta = bestRating - worstRating;
        var ratioFloor = favoritePrediction.algorithm.estimateRatioFloor(ratingDelta, settings: favoritePrediction.settings);
        var ratioMultiplier = 1.0 - ratioFloor;
        favoriteRatio = ((favoriteExpectedScore - minimumRatingScore) / (bestExpectedScore - minimumRatingScore)) * ratioMultiplier + ratioFloor;
        underdogRatio = ((underdogExpectedScore - minimumRatingScore) / (bestExpectedScore - minimumRatingScore)) * ratioMultiplier + ratioFloor;
        favoriteExpectedScore = favoriteRatio;
        underdogExpectedScore = underdogRatio;
      }
      else if(favoritePrediction.algorithm.predictionsOutputRatios) {
        favoriteRatio = favoriteExpectedScore;
        underdogRatio = underdogExpectedScore;
      }
      else {
        throw UnsupportedError("Rating system ${favoritePrediction.algorithm} cannot generate ratio-scaled percentage spread predictions");
      }

      predictedGaps.add(favoriteRatio - underdogRatio);
      if(percentageSpreadPrediction.favoriteCovers) {
        if(favoriteRatio > underdogRatio + spreadRatio) {
          successes++;
        }
      }
      else {
        if(favoriteRatio < underdogRatio + spreadRatio) {
          successes++;
        }
      }
    }

    var minProbability = 1 / trials;
    var maxProbability = (trials - 1) / trials;
    var probability = (successes / trials).clamp(minProbability, maxProbability);

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
    );
  }

  static double _nextDistributedValue(Random random, double ciOffset) {
    // var sample = random.nextShiftedNormal(ciOffset: ciOffset);
    var sample = random.nextGaussian();
    return sample;
  }

  /// Log a histogram of the distribution of trials for debugging purposes.
  ///
  /// This function generates a specified number of samples using the same
  /// distribution logic as the Monte Carlo simulations and logs a histogram
  /// showing the distribution of values.
  static void logDistributionHistogram({
    required double ciOffset,
    int sampleCount = 10000,
    int bins = 20,
    String label = "Distribution",
    Random? random,
  }) {
    final actualRandom = random ?? Random();
    final samples = <double>[];

    // Generate samples using the same logic as the Monte Carlo simulations
    for (int i = 0; i < sampleCount; i++) {
      final z = _nextDistributedValue(actualRandom, ciOffset);
      samples.add(z);
    }

    if (samples.isEmpty) {
      print("$label: No samples generated");
      return;
    }

    // Calculate statistics
    final min = samples.reduce((a, b) => a < b ? a : b);
    final max = samples.reduce((a, b) => a > b ? a : b);
    final mean = samples.average;
    final stdDev = samples.stdDev();

    print("\n=== $label Histogram (ciOffset: $ciOffset) ===");
    print("Samples: $sampleCount, Mean: ${mean.toStringAsFixed(3)}, StdDev: ${stdDev.toStringAsFixed(3)}");
    print("Range: [${min.toStringAsFixed(3)}, ${max.toStringAsFixed(3)}]");

    // Create histogram bins
    final binWidth = (max - min) / bins;
    final binCounts = List<int>.filled(bins, 0);
    final binLabels = <String>[];

    // Count samples in each bin
    for (final sample in samples) {
      int binIndex = ((sample - min) / binWidth).floor();
      binIndex = binIndex.clamp(0, bins - 1);
      binCounts[binIndex]++;
    }

    // Create bin labels
    for (int i = 0; i < bins; i++) {
      final binStart = min + i * binWidth;
      final binEnd = min + (i + 1) * binWidth;
      binLabels.add("${binStart.toStringAsFixed(2)}-${binEnd.toStringAsFixed(2)}");
    }

    // Find maximum count for scaling
    final maxCount = binCounts.reduce((a, b) => a > b ? a : b);
    final maxBarLength = 100;

    // Print histogram
    print("\nHistogram:");
    for (int i = 0; i < bins; i++) {
      final count = binCounts[i];
      final barLength = (count / maxCount * maxBarLength).round();
      final bar = "█" * barLength;
      final percentage = (count / sampleCount * 100).toStringAsFixed(1);
      print("${binLabels[i].padLeft(12)} |${bar.padRight(maxBarLength)}| $count ($percentage%)");
    }
    print("");
  }

  /// Log a histogram of actual trial data from Monte Carlo simulations.
  ///
  /// This can be called during Monte Carlo simulations to visualize
  /// the distribution of the actual trial values being generated.
  static void logTrialHistogram({
    required List<double> trialData,
    required double ciOffset,
    String label = "Trial Data",
    int bins = 20,
  }) {
    if (trialData.isEmpty) {
      print("$label: No trial data provided");
      return;
    }

    // Calculate statistics
    final min = trialData.reduce((a, b) => a < b ? a : b);
    final max = trialData.reduce((a, b) => a > b ? a : b);
    final mean = trialData.average;
    final stdDev = trialData.stdDev();

    print("\n=== $label Histogram (ciOffset: $ciOffset) ===");
    print("Trials: ${trialData.length}, Mean: ${mean.toStringAsFixed(3)}, StdDev: ${stdDev.toStringAsFixed(3)}");
    print("Range: [${min.toStringAsFixed(3)}, ${max.toStringAsFixed(3)}]");

    // Create histogram bins
    final binWidth = (max - min) / bins;
    final binCounts = List<int>.filled(bins, 0);
    final binLabels = <String>[];

    // Count samples in each bin
    for (final sample in trialData) {
      int binIndex = ((sample - min) / binWidth).floor();
      binIndex = binIndex.clamp(0, bins - 1);
      binCounts[binIndex]++;
    }

    // Create bin labels
    for (int i = 0; i < bins; i++) {
      final binStart = min + i * binWidth;
      final binEnd = min + (i + 1) * binWidth;
      binLabels.add("${binStart.toStringAsFixed(2)}-${binEnd.toStringAsFixed(2)}");
    }

    // Find maximum count for scaling
    final maxCount = binCounts.reduce((a, b) => a > b ? a : b);
    final maxBarLength = 100;

    // Print histogram
    print("\nHistogram:");
    for (int i = 0; i < bins; i++) {
      final count = binCounts[i];
      final barLength = (count / maxCount * maxBarLength).round();
      final bar = "█" * barLength;
      final percentage = (count / trialData.length * 100).toStringAsFixed(1);
      print("${binLabels[i].padLeft(12)} |${bar.padRight(maxBarLength)}| $count ($percentage%)");
    }
    print("");
  }

  /// Get the raw probability.
  double get rawProbability => probability;

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
