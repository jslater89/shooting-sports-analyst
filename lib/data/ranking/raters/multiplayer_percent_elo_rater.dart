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
  Map<ShooterRating, double> updateShooterRatings({required List<ShooterRating> shooters, required Map<ShooterRating, RelativeScore> scores, double matchStrength = 1.0}) {
    if(shooters.length != 1) {
      throw StateError("Incorrect number of shooters passed to MultiplayerElo");
    }

    if(scores.length <= 1) {
      return {
        shooters[0]: 0,
      };
    }

    var aRating = shooters[0];
    var aScore = scores[aRating]!;
    var divisor = (scores.length * (scores.length - 1)) / 2;

    double expectedScore = 0;
    var highOpponentScore = 0.0;
    for(var bRating in scores.keys) {
      if (Rater.processMemberNumber(aRating.shooter.memberNumber) ==
          Rater.processMemberNumber(bRating.shooter.memberNumber)) continue;

      var probability = _probability(bRating.rating, aRating.rating);
      if (probability.isNaN) {
        throw StateError("NaN");
      }
      expectedScore += probability;

      var opponentScore = scores[bRating]!;
      if (opponentScore.relativePoints > highOpponentScore) {
        highOpponentScore = opponentScore.relativePoints;
      }

    }
    expectedScore = (expectedScore) / divisor;

    var totalPercent = scores.map((rating, score) => MapEntry(rating, score.percent)).values.reduce((value, element) => value + element);

    var actualPercent = aScore.percent;
    if(aScore.percent == 1.0 && highOpponentScore > 0.1) {
      actualPercent = aScore.relativePoints / highOpponentScore;
      totalPercent += (actualPercent - 1.0);
    }
    var percentComponent = totalPercent == 0 ? 0 : (actualPercent / totalPercent);
    var placeComponent = (scores.length - aScore.place) /  divisor;

    var actualScore = percentComponent * percentWeight + placeComponent * placeWeight;
    var change = K * matchStrength * (scores.length - 1) * (actualScore - expectedScore);

    var changeFromPercent = K * matchStrength * (scores.length - 1) * (percentComponent * percentWeight - (expectedScore * percentWeight));
    var changeFromPlace = K * matchStrength * (scores.length - 1) * (placeComponent * placeWeight - (expectedScore * placeWeight));
    if(Rater.processMemberNumber(aRating.shooter.memberNumber) == "94315") {
      debugPrint("### Amanda stats: $actualPercent of ${scores.length} shooters for ${aScore.stage?.name}, SoS ${matchStrength.toStringAsFixed(3)}");
      debugPrint("AS/ES: ${actualScore.toStringAsFixed(6)}/${expectedScore.toStringAsFixed(6)}");
      debugPrint("Actual/expected percent: ${(percentComponent * totalPercent * 100).toStringAsFixed(2)}/${(expectedScore * totalPercent * 100).toStringAsFixed(2)}");
      debugPrint("Actual/expected place: ${aScore.place}/${(scores.length - (expectedScore * divisor)).toStringAsFixed(4)}");
      debugPrint("Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)");
      debugPrint("###");
    }
    if(Rater.processMemberNumber(aRating.shooter.memberNumber) == "89315") {
      debugPrint("### Lee stats: $actualPercent of ${scores.length} shooters for ${aScore.stage?.name}, SoS ${matchStrength.toStringAsFixed(3)}");
      debugPrint("AS/ES: ${actualScore.toStringAsFixed(6)}/${expectedScore.toStringAsFixed(6)}");
      debugPrint("Actual/expected percent: ${(percentComponent * totalPercent * 100).toStringAsFixed(2)}/${(expectedScore * totalPercent * 100).toStringAsFixed(2)}");
      debugPrint("Actual/expected place: ${aScore.place}/${(scores.length - (expectedScore * divisor)).toStringAsFixed(4)}");
      debugPrint("Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)");
      debugPrint("###");
    }
    aRating.rating += change;

    if(change.isNaN || change.isInfinite) {
      throw StateError("NaN/Infinite");
    }

    return {
      aRating: change,
    };
  }

  double _probability(double lose, double win) {
    return 1.0 / (1.0 + (pow(10, (lose - win) / 400)));
  }
}