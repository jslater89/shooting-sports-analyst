/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/util.dart';

/// Represents a prediction probability with various odds formats.
class PredictionProbability {

  /// The minimum possible odds.
  static const _worstPossibleOddsDefault = 1.0001;
  /// The maximum possible odds.
  static const _bestPossibleOddsDefault = 10000.0;


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
    this.worstPossibleOdds = _worstPossibleOddsDefault,
    this.bestPossibleOdds = _bestPossibleOddsDefault,
  }) {
    if (probability <= 0 || probability >= 1) {
      throw ArgumentError("Probability must be between 0 and 1");
    }
  }

  factory PredictionProbability.fromParlayPredictions({required List<UserPrediction> predictions, required Map<UserPrediction, PredictionProbability> predictionProbabilities, double? houseEdge}) {
    // For a parlay, we need the probability that ALL predictions are correct
    // This is the product of individual probabilities, assuming independence
    var parlayProbability = 1.0;

    for (var leg in predictions) {
      var predictionProb = predictionProbabilities[leg]!.rawProbability;
      parlayProbability *= predictionProb;
    }

    var fullness = Parlay.parlayFillProportion(predictions).clamp(0.0, 1.0);
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

    return PredictionProbability(parlayProbability, houseEdge: houseEdge ?? parlayHouseEdge);
  }

  factory PredictionProbability.fromParlayLegs(List<Wager> legs, {double? houseEdge}) {
    var predictionProbabilities = <UserPrediction, PredictionProbability>{};
    var predictions = <UserPrediction>[];
    for(var leg in legs) {
      predictions.add(leg.prediction);
      predictionProbabilities[leg.prediction] = leg.probability;
    }
    return PredictionProbability.fromParlayPredictions(predictions: predictions, predictionProbabilities: predictionProbabilities, houseEdge: houseEdge);
  }

  /// Calculate the probability that the competitor and place range in [userPrediction] will occur.
  /// [shootersToPredictions] is a map of shooter ratings to their predictions for
  /// all of [userPrediction]'s competitors, including the competitor in question.
  factory PredictionProbability.fromUserPrediction(
    UserPrediction userPrediction,
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
  {
    Random? random,
    double disasterChance = 0.01,
    double? houseEdge,
    double bestPossibleOdds = _bestPossibleOddsDefault,
    double worstPossibleOdds = _worstPossibleOddsDefault,
  }) {
    /// Calculate the probability that a shooter finishes within the specified place range
    // Use Monte Carlo simulation with the actual prediction data
    // mean = average expected score from 1000 Monte Carlo runs
    // oneSigma = standard deviation of those runs
    // ciOffset = trend shift (-0.9 to 0.9)

    var trials = 10000;
    var successes = 0;

    var actualRandom = random ?? Random();
    var shooterPrediction = shootersToPredictions[userPrediction.shooter];
    if(shooterPrediction == null) {
      throw ArgumentError("Shooter prediction not found for ${userPrediction.shooter.name}");
    }

    var bestPlace = userPrediction.bestPlace;
    var worstPlace = userPrediction.worstPlace;

    for (var i = 0; i < trials; i++) {
      if(actualRandom.nextDouble() < disasterChance) {
        continue;
      }

      // Generate a random expected score for this shooter using a normal distribution

      var actualMean = shooterPrediction.mean + shooterPrediction.shift;
      var z = actualRandom.nextGaussian();
      var shooterExpectedScore = actualMean + shooterPrediction.oneSigma * z;

      // Generate random expected scores for all other shooters
      var otherExpectedScores = <double>[];
      for (var otherPred in shootersToPredictions.values) {
        if (otherPred == shooterPrediction) continue;

        var otherMean = otherPred.mean + otherPred.shift;
        var z = actualRandom.nextGaussian();
        var otherExpectedScore = otherMean + otherPred.oneSigma * z;

        otherExpectedScores.add(otherExpectedScore);
      }

      // Count how many shooters have higher expected scores (higher score = better placement)
      var betterCount = otherExpectedScores.where((score) => score > shooterExpectedScore).length;
      var place = betterCount + 1;

      if (place >= bestPlace && place <= worstPlace) {
        successes++;
      }
    }

    var minProbability = 1 / trials;
    var maxProbability = (trials - 1) / trials;
    var probability = (successes / trials).clamp(minProbability, maxProbability);

    return PredictionProbability(
      probability,
      houseEdge: houseEdge ?? standardHouseEdge,
      worstPossibleOdds: worstPossibleOdds,
      bestPossibleOdds: bestPossibleOdds,
    );
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
}
