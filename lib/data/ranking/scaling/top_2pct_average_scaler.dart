/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';

/// Scales ratings so that the average of the top 2% of ratings is equal to [scaleMax].
class Top2PercentAverageScaler extends RatingScaler {
  final double scaleMax;
  final double scaleMin;

  Top2PercentAverageScaler({
    required super.info,
    this.scaleMax = 2250,
    this.scaleMin = 0,
  });

  @override
  double scaleRating(double rating, {RatingGroup? group}) {
    // linearly scale ratings such that the average rating of the top 2% is scaled to scaleMax and minRating is scaled to scaleMin
    // rating can be greater than top2PercentAverage, in which case it is scaled to a value greater than scaleMax.

    double scaleFactor = scaleMax / info.top2PercentAverage;
    return scaleMin + (rating * scaleFactor);
  }

  @override
  double scaleNumber(double number, {required double originalRating, RatingGroup? group}) {
    double scaleFactor = scaleMax / info.top2PercentAverage;
    return (number * scaleFactor);
  }

  @override
  RatingScaler copy() {
    return Top2PercentAverageScaler(
      info: info.copy(),
    );
  }
}
