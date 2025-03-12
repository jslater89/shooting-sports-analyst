/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';

/// Convert ratings to z-scores, multiplying the result by [scaleFactor] and adding [scaleOffset].
/// The default puts +2SD at 2000 and -2SD at 0.
class ZScoreScaler extends RatingScaler {
  final double scaleFactor;
  final double scaleOffset;
  ZScoreScaler({required super.info, this.scaleFactor = 500, this.scaleOffset = 1000});

  @override
  double scaleRating(double rating) {
    return scaleOffset + ((rating - info.ratingMean) / info.ratingStdDev) * scaleFactor;
  }

  @override
  double scaleNumber(double number, {required double originalRating}) {
    var zScore = (originalRating - info.ratingMean) / info.ratingStdDev;
    var scaledRating = zScore * scaleFactor;
    var finalScaleFactor = scaledRating / originalRating;
    return finalScaleFactor * number;
  }

  @override
  RatingScaler copy() => ZScoreScaler(info: info.copy(), scaleFactor: scaleFactor, scaleOffset: scaleOffset);
}
