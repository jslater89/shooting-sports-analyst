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
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/util.dart';

/// Run a Monte Carlo simulation to generate a [MonteCarloSimulationResult] for a given target shooter within a
/// field specified by [shootersToPredictions].
///
/// [target] is the shooter for which the simulation is being run.
/// [shootersToPredictions] is a map of shooter ratings to their predictions for
/// all of [target]'s competitors, including the competitor in question.
/// [trials] is the number of trials to run for the simulation.
/// [random] is an optional random number generator to use for the simulation.
/// [disasterChance] is the chance that a simulation will be skipped due to a 'disaster'
/// (DQ, gun breaking, etc.).
///
/// Returns a [MonteCarloSimulationResult] containing the percentages and places of the target shooter in each trial.
MonteCarloSimulationResult runOddsSimulation({
  required ShooterRating target,
  required Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
  required int trials,
  Random? random,
  double disasterChance = 0.01,
}) {
  final actualRandom = random ?? Random();
  var shooterPrediction = shootersToPredictions[target];
  if(shooterPrediction == null) {
    // fall back to equalsShooter search
    final matchingKey = shootersToPredictions.keys.firstWhereOrNull((key) => key.equalsShooter(target));
    if(matchingKey != null) {
      shooterPrediction = shootersToPredictions[matchingKey];
    }
  }

  if(shooterPrediction == null) {
    throw ArgumentError("Shooter prediction not found for ${target.name}");
  }

  List<double> percentages = [];
  List<int> places = [];
  bool logNormalMode = shooterPrediction.isLogNormal;

  for(var i = 0; i < trials; i++) {
    // A multiplier for expected score to account for a disaster (DQ, gun breaking, squib stage, etc.).
    // Random number between 0 and 0.5, used to multiply the output expected score.
    var disasterMagnitude = 1.0;
    if(actualRandom.nextDouble() < disasterChance) {
      var coinFlip = actualRandom.nextDouble();
      // Half the time it's a DQ or match DNF.
      if(coinFlip < 0.5) {
        disasterMagnitude = 0.0;
      }
      else {
        disasterMagnitude = actualRandom.nextDouble() * 0.50;
      }
    }

    // Generate a random expected score for this shooter using a normal distribution

    // Adjust mean by up to 10% based on trend.
    double shooterExpectedScore;
    final placeSigmaMultiplier = shooterPrediction.algorithm.predictionSettings.placeSigmaMultiplier;
    if(logNormalMode) {
      final finalLogSigma = shooterPrediction.logSigma! * placeSigmaMultiplier;
      final finalLogMean = shooterPrediction.logMean! + finalLogSigma * shooterPrediction.ciOffset;
      shooterExpectedScore = _logNormalDraw(random: actualRandom, logMean: finalLogMean, logSigma: finalLogSigma) * disasterMagnitude;
    }
    else {
      final finalSigma = shooterPrediction.oneSigma * placeSigmaMultiplier;
      final actualMean = shooterPrediction.displayCenter + finalSigma * shooterPrediction.ciOffset;
      shooterExpectedScore = _normalDraw(random: actualRandom, mean: actualMean, sigma: finalSigma) * disasterMagnitude;
    }

    // Generate random expected scores for all other shooters
    var otherExpectedScores = <double>[];
    var bestExpectedScore = shooterExpectedScore;
    var minimumRatingScore = shooterExpectedScore;
    var bestRating = double.negativeInfinity;
    var worstRating = double.infinity;

    for (var otherPred in shootersToPredictions.values) {
      if (otherPred == shooterPrediction) continue;

      var otherDisasterMagnitude = 1.0;
      if(actualRandom.nextDouble() < disasterChance) {
        var coinFlip = actualRandom.nextDouble();
        // Half the time it's a DQ or match DNF.
        if(coinFlip < 0.5) {
          otherDisasterMagnitude = 0.0;
        }
        else {
          otherDisasterMagnitude = actualRandom.nextDouble() * 0.50;
        }
      }

      double otherExpectedScore;
      if(logNormalMode) {
        final otherFinalLogSigma = otherPred.logSigma! * placeSigmaMultiplier;
        final otherFinalLogMean = otherPred.logMean! + otherFinalLogSigma * otherPred.ciOffset;
        otherExpectedScore = _logNormalDraw(random: actualRandom, logMean: otherFinalLogMean, logSigma: otherFinalLogSigma) * otherDisasterMagnitude;
      }
      else {
        final otherFinalSigma = otherPred.oneSigma * placeSigmaMultiplier;
        final otherMean = otherPred.displayCenter + otherFinalSigma * otherPred.ciOffset;
        otherExpectedScore = _normalDraw(random: actualRandom, mean: otherMean, sigma: otherFinalSigma) * otherDisasterMagnitude;
      }

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
    double shooterRatio;

    // Keep the un-normalized shooter score for later use.
    final rawShooterScore = shooterExpectedScore;

    // If the rating system outputs ratios, we need to renormalize so that the winner is 1.0;
    // multiple people may have expected scores above 1.0 based on their rating ranges.
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
    percentages.add(shooterRatio);

    // Count how many shooters have higher expected scores (higher score = better placement)
    var betterCount = otherExpectedScores.where((score) => score > rawShooterScore).length;
    var place = betterCount + 1;

    places.add(place);
  }

  return MonteCarloSimulationResult(percentages: percentages, places: places);
}

double _nextDistributedValue(Random random) {
  var sample = random.nextGaussian();
  return sample;
}

/// Log a histogram of the distribution of trials for debugging purposes.
///
/// This function generates a specified number of samples using the same
/// distribution logic as the Monte Carlo simulations and logs a histogram
/// showing the distribution of values.
void logDistributionHistogram({
  int sampleCount = 10000,
  int bins = 20,
  String label = "Distribution",
  Random? random,
}) {
  final actualRandom = random ?? Random();
  final samples = <double>[];

  // Generate samples using the same logic as the Monte Carlo simulations
  for (int i = 0; i < sampleCount; i++) {
    final z = _nextDistributedValue(actualRandom);
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

  print("\n=== $label Histogram ===");
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

double _normalDraw({
  required Random random,
  required double mean,
  required double sigma,
}) {
  return _nextDistributedValue(random) * sigma + mean;
}

double _logNormalDraw({
  required Random random,
  required double logMean,
  required double logSigma,
}) {
  var logDraw = _normalDraw(random: random, mean: logMean, sigma: logSigma);
  return exp(logDraw);
}

/// Log a histogram of actual trial data from Monte Carlo simulations.
///
/// This can be called during Monte Carlo simulations to visualize
/// the distribution of the actual trial values being generated.
// ignore: unused_element
void _logTrialHistogram({
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
