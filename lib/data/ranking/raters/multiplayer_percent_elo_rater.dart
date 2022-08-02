import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';

class MultiplayerPercentEloRater implements RatingSystem {
  @override
  double get defaultRating => 1000;

  static const K = 50;
  static const percentWeight = 0.75;
  static const placeWeight = 0.25;

  @override
  RatingMode get mode => RatingMode.oneShot;

  @override
  Map<ShooterRating, RatingChange> updateShooterRatings({required List<ShooterRating> shooters, required Map<ShooterRating, RelativeScore> scores, double matchStrength = 1.0}) {
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
    int usedScores = 1; // our own score
    for(var bRating in scores.keys) {
      if (Rater.processMemberNumber(aRating.shooter.memberNumber) ==
          Rater.processMemberNumber(bRating.shooter.memberNumber)) continue;

      var opponentScore = scores[bRating]!;

      // Ignore opponents who didn't record a score for the stage
      if(opponentScore.score.hits == 0 && opponentScore.score.time == 0) {
        continue;
      }

      if (opponentScore.relativePoints > highOpponentScore) {
        highOpponentScore = opponentScore.relativePoints;
      }

      var probability = _probability(bRating.rating, aRating.rating);
      if (probability.isNaN) {
        throw StateError("NaN");
      }

      expectedScore += probability;
      usedScores++;
    }
    var divisor = (usedScores * (usedScores - 1)) / 2;
    expectedScore = (expectedScore) / divisor;

    var totalPercent = scores.map((rating, score) => MapEntry(rating, score.percent)).values.reduce((value, element) => value + element);

    var actualPercent = aScore.percent;
    if(aScore.percent == 1.0 && highOpponentScore > 0.1) {
      actualPercent = aScore.relativePoints / highOpponentScore;
      totalPercent += (actualPercent - 1.0);
    }
    var percentComponent = totalPercent == 0 ? 0 : (actualPercent / totalPercent);
    var placeComponent = (scores.length - aScore.place) /  divisor;

    var placementMultiplier = aRating.ratingEvents.length < RatingSystem.initialPlacementMultipliers.length ?
      RatingSystem.initialPlacementMultipliers[aRating.ratingEvents.length] : 1.0;

    var actualScore = percentComponent * percentWeight + placeComponent * placeWeight;
    var change = K * placementMultiplier * matchStrength * (scores.length - 1) * (actualScore - expectedScore);

    var changeFromPercent = K * placementMultiplier * matchStrength * (scores.length - 1) * (percentComponent * percentWeight - (expectedScore * percentWeight));
    var changeFromPlace = K * placementMultiplier * matchStrength * (scores.length - 1) * (placeComponent * placeWeight - (expectedScore * placeWeight));
    // if(Rater.processMemberNumber(aRating.shooter.memberNumber) == "94315") {
    //   debugPrint("### Amanda stats: $actualPercent of ${scores.length} shooters for ${aScore.stage?.name}, SoS ${matchStrength.toStringAsFixed(3)}, placement $placementMultiplier");
    //   debugPrint("AS/ES: ${actualScore.toStringAsFixed(6)}/${expectedScore.toStringAsFixed(6)}");
    //   debugPrint("Actual/expected percent: ${(percentComponent * totalPercent * 100).toStringAsFixed(2)}/${(expectedScore * totalPercent * 100).toStringAsFixed(2)}");
    //   debugPrint("Actual/expected place: ${aScore.place}/${(scores.length - (expectedScore * divisor)).toStringAsFixed(4)}");
    //   debugPrint("Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)");
    //   debugPrint("###");
    // }

    if(change.isNaN || change.isInfinite) {
      throw StateError("NaN/Infinite");
    }

    List<String> info = [
      "Actual/expected percent: ${(percentComponent * totalPercent * 100).toStringAsFixed(2)}/${(expectedScore * totalPercent * 100).toStringAsFixed(2)}",
      "Actual/expected place: ${aScore.place}/${(scores.length - (expectedScore * divisor)).toStringAsFixed(4)}",
      "Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)",
    ];

    return {
      aRating: RatingChange(change: change, info: info),
    };
  }

  double _probability(double lose, double win) {
    return 1.0 / (1.0 + (pow(10, (lose - win) / 400)));
  }
}