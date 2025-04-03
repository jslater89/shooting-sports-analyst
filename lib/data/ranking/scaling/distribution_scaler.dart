/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:math';

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';

/// Scales ratings according to a continuous distribution, so that the percentile for each
/// entry in [percentiles] is close to the corresponding rating value in [percentileRatings].
///
/// Percentile is a value between 0 and 1, where 0 is the minimum rating and 1 is the maximum rating.
class DistributionScaler extends RatingScaler {
  final List<double> percentiles;
  final List<double> percentileRatings;
  final double scaleOffset;
  final double? scaleMin;
  final double? scaleMax;

  // Make these nullable to indicate they haven't been computed yet
  double? _scaleFactor;
  double? _offset;
  // Add a field to track which info was used for the cached parameters
  RatingScalerInfo? _lastInfo;

  DistributionScaler({
    required super.info,
    required this.percentiles,
    required this.percentileRatings,
    this.scaleOffset = 0,
    this.scaleMin,
    this.scaleMax,
  }) {
    assert(percentiles.length == percentileRatings.length,
      "Must provide equal number of percentiles and target ratings");
    assert(percentiles.isNotEmpty, "Must provide at least one percentile point");
  }

  void _computeScalingFactors() {
    if (_lastInfo == info && _scaleFactor != null && _offset != null) {
      return;
    }

    final n = percentiles.length;
    final originalRatings = percentiles
        .map((p) => info.ratingDistribution.inverseCumulativeProbability(p))
        .toList();

    if (n == 1) {
      _scaleFactor = percentileRatings[0] / originalRatings[0];
      _offset = scaleOffset;
      return;
    }

    // Use least squares regression to find the best fit line through all points
    double sumX = 0;
    double sumY = 0;
    double sumXY = 0;
    double sumXX = 0;

    for (int i = 0; i < n; i++) {
      sumX += originalRatings[i];
      sumY += percentileRatings[i];
      sumXY += originalRatings[i] * percentileRatings[i];
      sumXX += originalRatings[i] * originalRatings[i];
    }

    // Calculate slope (scale factor) and intercept (offset)
    _scaleFactor = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
    _offset = (sumY - _scaleFactor! * sumX) / n + scaleOffset;

    _lastInfo = info;
  }

  @override
  double scaleRating(double rating, {RatingGroup? group}) {
    _computeScalingFactors();

    var intermediate = rating * _scaleFactor! + _offset!;

    if (scaleMin != null) {
      intermediate = max(intermediate, scaleMin!);
    }
    if (scaleMax != null) {
      intermediate = min(intermediate, scaleMax!);
    }
    return intermediate;
  }

  @override
  double scaleNumber(double number, {required double originalRating, RatingGroup? group}) {
    _computeScalingFactors();
    return number * _scaleFactor!;
  }

  @override
  RatingScaler copy() {
    return DistributionScaler(
      info: info.copy(),
      percentiles: [...percentiles],
      percentileRatings: [...percentileRatings],
      scaleOffset: scaleOffset,
      scaleMin: scaleMin,
      scaleMax: scaleMax,
    );
  }
}
