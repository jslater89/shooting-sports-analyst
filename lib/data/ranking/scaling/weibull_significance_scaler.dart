/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';

/// Scales ratings to a z-score as calculated from a Weibull variance/stdDev.
class WeibullZScoreScaler extends RatingScaler {
  WeibullZScoreScaler({required super.info, this.scaleFactor = 500, this.scaleOffset = 1000});

  final double scaleFactor;
  final double scaleOffset;

  @override
  double scaleRating(double number) {
    var d = info.ratingDistribution;
    var zScore = (number - d.mean) / d.standardDeviation;
    var scaledRating = zScore * scaleFactor;
    return scaleOffset + scaledRating;
  }

  @override
  double scaleNumber(double number, {required double originalRating}) {
    var d = info.ratingDistribution;
    var zScore = (originalRating - d.mean) / d.standardDeviation;
    var scaledRating = zScore * scaleFactor;
    var finalScaleFactor = scaledRating / originalRating;
    return finalScaleFactor * number;
  }

  @override
  RatingScaler copy() {
    return WeibullZScoreScaler(info: info.copy(), scaleFactor: scaleFactor, scaleOffset: scaleOffset);
  }
}
