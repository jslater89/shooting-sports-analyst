import 'dart:math';

import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';

class MultiplayerEloRater implements RatingSystem {
  @override
  double get defaultRating => 1000;

  static const K = 30;

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
    var divisor = (scores.length * (scores.length - 1)) / 2;

    double expectedScore = 0;
    for(var bRating in scores.keys) {
      if(Rater.processMemberNumber(aRating.shooter.memberNumber) == Rater.processMemberNumber(bRating.shooter.memberNumber)) continue;
      var probability = _probability(bRating.rating, aRating.rating);
      if(probability.isNaN) {
        throw StateError("NaN");
      }
      expectedScore += probability;
    }
    expectedScore = (expectedScore) / divisor;

    var actualScore = (scores.length - aScore.place) /  divisor;
    var change = K * (scores.length - 1) * (actualScore - expectedScore);

    if(change.isNaN) {
      throw StateError("NaN");
    }

    return {
      aRating: RatingChange(change: change),
    };
  }

  double _probability(double lose, double win) {
    return 1.0 / (1.0 + (pow(10, (lose - win) / 400)));
  }
}