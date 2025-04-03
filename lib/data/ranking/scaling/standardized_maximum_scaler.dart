/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';

/// Scales ratings so that the maximum rating is [scaleMax] and the minimum rating is [scaleMin].
class StandardizedMaximumScaler extends RatingScaler {
  final double scaleMax;
  final double scaleMin;

  StandardizedMaximumScaler({
    required super.info,
    this.scaleMax = 2500,
    this.scaleMin = 0,
  });

  @override
  double scaleRating(double rating, {RatingGroup? group}) {
    // linearly scale ratings such that maxRating is scaled to scaleMax and minRating is scaled to scaleMin
    return scaleMin + ((rating - info.minRating) / (info.maxRating - info.minRating)) * (scaleMax - scaleMin);
  }

  @override
  double scaleNumber(double number, {required double originalRating, RatingGroup? group}) {
    return ((originalRating - info.minRating) / (info.maxRating - info.minRating)) * number;
  }

  @override
  RatingScaler copy() {
    return StandardizedMaximumScaler(
      info: info.copy(),
      scaleMax: scaleMax,
      scaleMin: scaleMin,
    );
  }
}
