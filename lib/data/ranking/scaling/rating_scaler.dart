/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:data/data.dart' show ContinuousDistribution, WeibullDistribution;

/// Rating scalers scale ratings, either clamping/stretching to a new range,
/// or scaling by a factor, or offsetting by a value.
abstract class RatingScaler {
  /// Information required to scale the rating. It must be provided before
  /// calling scaleRating.
  RatingScalerInfo info;
  RatingScaler({RatingScalerInfo? info}) : this.info = info ?? RatingScalerInfo.empty();

  /// Scale a rating.
  double scaleRating(double rating);

  /// Scale a rating-adjacent value, like error or match change.
  ///
  /// [originalRating] is the actual rating that the number is derived from,
  /// and is required for scalers that calculate significance in some way.
  double scaleNumber(double number, {required double originalRating});

  RatingScaler copy();
}

/// Contains information required for a RatingScaler to scale a rating.
class RatingScalerInfo {
  final double minRating;
  final double maxRating;
  final double top2PercentAverage;
  final ContinuousDistribution ratingDistribution;
  final double ratingMean;
  final double ratingStdDev;

  RatingScalerInfo({
    required this.minRating,
    required this.maxRating,
    required this.top2PercentAverage,
    required this.ratingDistribution,
    required this.ratingMean,
    required this.ratingStdDev,
  });

  RatingScalerInfo.empty() : this(
    minRating: 0,
    maxRating: 0,
    top2PercentAverage: 0,
    ratingDistribution: WeibullDistribution(1, 1),
    ratingMean: 0,
    ratingStdDev: 0,
  );

  RatingScalerInfo copy() {
    return RatingScalerInfo(
      minRating: minRating,
      maxRating: maxRating,
      top2PercentAverage: top2PercentAverage,
      ratingDistribution: ratingDistribution,
      ratingMean: ratingMean,
      ratingStdDev: ratingStdDev,
    );
  }
}
