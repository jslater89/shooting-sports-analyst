import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/ranker.dart';

class EloRanker implements RatingSystem {
  @override
  double get defaultRating => 1000;

  static const double K = 30;

  @override
  Map<ShooterRating, double> updateShooterRatings(Map<ShooterRating, RelativeScore> scores) {
    var ratings = scores.keys.toList();

    if(scores.length != 2) {
      debugPrint("???");
      for(var rating in scores.keys) {
        debugPrint("${rating.shooter.getName()}");
      }
    }

    var aRating = ratings[0];
    var bRating = ratings[1];

    var aScore = scores[aRating]!;
    var bScore = scores[bRating]!;

    var pB = _probability(aRating.rating, bRating.rating);
    var pA = _probability(bRating.rating, aRating.rating);

    var aDiff = 0.0;
    var bDiff = 0.0;

    var closeFactor = 1.0;
    var percentDiff = (aScore.percent - bScore.percent).abs();
    if(percentDiff < 10) {
      closeFactor -= (percentDiff / 10) * 0.5;
    }

    var eloDiffFactor = 1.0;
    var eloDiff = (aRating.rating - bRating.rating).abs();
    if(eloDiff > (5 * K)) {
      eloDiff -= 5 * K;
      eloDiffFactor -= min(1.0, eloDiff / (10 * K)) * 0.9;
    }

    var mod = eloDiffFactor * closeFactor;

    if(aScore.percent > bScore.percent) {
      aDiff = K * (1 - pA) * mod;
      bDiff = K * (0 - pB) * mod;
    }
    else {
      bDiff = K * (1 - pB) * mod;
      aDiff = K * (0 - pA) * mod;
    }

    aRating.rating += aDiff;
    bRating.rating += bDiff;

    return {
      aRating: aDiff,
      bRating: bDiff,
    };
  }

  /// Probability that win beats lose
  double _probability(double lose, double win) {
    return 1.0 * 1.0 / (1 + 1.0 * (pow(10, 1.0 * (lose - win) / 400)));
  }
}