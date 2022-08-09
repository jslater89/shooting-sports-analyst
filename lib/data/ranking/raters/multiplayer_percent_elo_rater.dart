import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/sorted_list.dart';

class MultiplayerPercentEloRater implements RatingSystem {
  @override
  double get defaultRating => 1000;

  static const defaultK = 60.0;
  static const defaultPercentWeight = 0.4;
  static const defaultPlaceWeight = 0.6;
  static const defaultScale = 800.0;

  @override
  RatingMode get mode => RatingMode.oneShot;

  /// K is the K parameter to the rating Elo algorithm
  final double K;
  final double percentWeight;
  final double placeWeight;
  final double scale;

  MultiplayerPercentEloRater({this.K = defaultK, this.scale = defaultScale, this.percentWeight = defaultPercentWeight}) : this.placeWeight = 1.0 - percentWeight;

  @override
  Map<ShooterRating, RatingChange> updateShooterRatings({required List<ShooterRating> shooters, required Map<ShooterRating, RelativeScore> scores, double matchStrengthMultiplier = 1.0, double connectednessMultiplier = 1.0, double eventWeightMultiplier = 1.0}) {
    if(shooters.length != 1) {
      throw StateError("Incorrect number of shooters passed to MultiplayerElo");
    }

    if(scores.length <= 1) {
      return {
        shooters[0]: RatingChange(change: 0),
      };
    }

    var aRating = shooters[0];
    var aScore = scores[aRating]!;

    double expectedScore = 0;

    var highOpponentScore = 0.0;
    var secondHighScore = 0.0;

    var highOpponentRating = aRating.rating;
    var allRatings = SortedList<double>.comparable();
    allRatings.add(aRating.rating);

    int zeroes = 0;
    int usedScores = 1; // our own score
    for(var bRating in scores.keys) {
      if (Rater.processMemberNumber(aRating.shooter.memberNumber) ==
          Rater.processMemberNumber(bRating.shooter.memberNumber)) continue;

      var opponentScore = scores[bRating]!;

      // Ignore opponents who didn't record a score for the stage
      if(opponentScore.score.hits == 0 && opponentScore.score.time <= 0.5) {
        continue;
      }

      if (opponentScore.relativePoints > highOpponentScore) {
        highOpponentScore = opponentScore.relativePoints;
      }
      else if (opponentScore.relativePoints > secondHighScore) {
        secondHighScore = opponentScore.relativePoints;
      }

      if(opponentScore.relativePoints < 0.1) {
        zeroes += 1;
      }

      var probability = _probability(bRating.rating, aRating.rating);
      if (probability.isNaN) {
        throw StateError("NaN");
      }

      if(bRating.rating > highOpponentRating) highOpponentRating = bRating.rating;
      allRatings.add(bRating.rating);

      expectedScore += probability;
      usedScores++;
    }

    if(usedScores == 1) {
      return {
        shooters[0]: RatingChange(change: 0),
      };
    }

    // Add an extra penalty for crazy pubstomps: if the high rating
    // is more than scale above the
    var medianRating = allRatings[allRatings.length ~/ 2];
    var averageRating = allRatings.average;
    var pubstomp = false;

    // TODO: figure out a better heuristic to turn this on per rating event
    // if(highOpponentRating - medianRating > scale && highOpponentRating - averageRating > scale && matchStrengthMultiplier < 1.0) {
    //   matchStrengthMultiplier *= 0.5;
    //   pubstomp = true;
    //   print("Pubstomp multiplier for ${highOpponentRating.round()} over ${medianRating.round()}/${averageRating.round()} on ${allRatings.length} ${aScore.stage?.name}");
    // }

    var divisor = (usedScores * (usedScores - 1)) / 2;

    // TODO: solve my expected-percent-above-100 issue
    // I might be able to solve this by distributing percent actual score more like it's distributed for placement:
    // pick a floor for percent points for last place, and adjust the intervals on the way up by relative finish.
    // This is, however, a good soft cap on pubstompers.
    expectedScore = (expectedScore) / divisor;

    var totalPercent = 0.0;
    for(var relativeScore in scores.values) {
      totalPercent += relativeScore.percent;
    }

    var actualPercent = aScore.percent;
    if(aScore.percent == 1.0 && highOpponentScore > 0.1) {
      actualPercent = aScore.relativePoints / highOpponentScore;
      totalPercent += (actualPercent - 1.0);
    }

    var percentComponent = totalPercent == 0 ? 0 : (actualPercent / totalPercent);
    var placeComponent = (usedScores - aScore.place) /  divisor;

    // The first N matches you shoot get bonuses for initial placement.
    var placementMultiplier = aRating.ratingEvents.length < RatingSystem.initialPlacementMultipliers.length ?
      RatingSystem.initialPlacementMultipliers[aRating.ratingEvents.length] : 1.0;

    // If lots of people zero a stage, we can't reason effectively about the relative
    // differences in performance of those people, compared to each other or compared
    // to the field that didn't zero it. If more than 10% of people zero a stage, start
    // scaling K down (to 0.34, when 30%+ of people zero a stage).
    var zeroMultiplier = (zeroes / usedScores) < 0.1 ? 1 : 1 - 0.66 * ((min(0.3, (zeroes / usedScores) - 0.1)) / 0.3);

    var actualScore = percentComponent * percentWeight + placeComponent * placeWeight;
    var effectiveK = K * placementMultiplier * matchStrengthMultiplier * zeroMultiplier * connectednessMultiplier * eventWeightMultiplier;

    var changeFromPercent = effectiveK * (usedScores - 1) * (percentComponent * percentWeight - (expectedScore * percentWeight));
    var changeFromPlace = effectiveK * (usedScores - 1) * (placeComponent * placeWeight - (expectedScore * placeWeight));

    var change = changeFromPlace + changeFromPercent;

    if(change.isNaN || change.isInfinite) {
      debugPrint("### ${aRating.shooter.lastName} stats: $actualPercent of $usedScores shooters for ${aScore.stage?.name}, SoS ${matchStrengthMultiplier.toStringAsFixed(3)}${pubstomp ? "p" : ""}, placement $placementMultiplier, zero $zeroMultiplier ($zeroes)");
      debugPrint("AS/ES: ${actualScore.toStringAsFixed(6)}/${expectedScore.toStringAsFixed(6)}");
      debugPrint("Actual/expected percent: ${(percentComponent * totalPercent * 100).toStringAsFixed(2)}/${(expectedScore * totalPercent * 100).toStringAsFixed(2)}");
      debugPrint("Actual/expected place: ${aScore.place}/${(usedScores - (expectedScore * divisor)).toStringAsFixed(4)}");
      debugPrint("Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)");
      debugPrint("###");
      throw StateError("NaN/Infinite");
    }

    var hf = aScore.score.getHitFactor(scoreDQ: aScore.score.stage != null);
    List<String> info = [
      "Actual/expected percent: ${(percentComponent * totalPercent * 100).toStringAsFixed(2)}/${(expectedScore * totalPercent * 100).toStringAsFixed(2)} on ${hf.toStringAsFixed(2)}HF",
      "Actual/expected place: ${aScore.place}/${(usedScores - (expectedScore * divisor)).toStringAsFixed(4)}",
      "Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)",
      "eff. K, multipliers: ${(effectiveK).toStringAsFixed(2)}, SoS ${matchStrengthMultiplier.toStringAsFixed(3)}${pubstomp ? "p" : ""}, IP ${placementMultiplier.toStringAsFixed(2)}, Zero ${zeroMultiplier.toStringAsFixed(2)}, Conn ${connectednessMultiplier.toStringAsFixed(2)}, EW ${eventWeightMultiplier.toStringAsFixed(2)}",
    ];

    return {
      aRating: RatingChange(change: change, info: info),
    };
  }

  double _probability(double lose, double win) {
    return 1.0 / (1.0 + (pow(10, (lose - win) / scale)));
  }
}