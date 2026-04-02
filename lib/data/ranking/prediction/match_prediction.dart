/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/*
Spitballing some ideas:

1. Confidence intervals
Assume performances are normally distributed, with stddev smaller than scale implies.
(Tunable param?) Scale stddev based on error, adjust the center of the CI based on
trend. Display bar graphs per shooter, in a column where they're on the same scale.

See if rating percentage correlates with match finish percentage?

2. As above, but with probabilities.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';

/// An algorithmic prediction for a shooter's finish.
///
/// Users of this class are responsible for filling in [lowPlace] and [highPlace].
class AlgorithmPrediction {
  final RaterSettings settings;
  final RatingSystem algorithm;

  final ShooterRating shooter;

  /// An average performance value.
  final double mean;

  /// The standard deviation of the performance.
  final double oneSigma;

  /// Two standard deviations of the performance.
  final double twoSigma;

  /// An offset strength to apply to the performance based on trend,
  /// between -1 and 1.
  final double ciOffset;

  late int lowPlace;
  late int highPlace;
  late int medianPlace;

  /// The mean performance in ratio terms (i.e., 1.0 for the winner, [0.0, 1.0) for other competitors
  /// relative to the winner). Null if this algorithm cannot generate ratio predictions.
  double? meanRatio;

  /// The standard deviation of the performance in ratio terms. Null if this algorithm cannot generate ratio predictions.
  double? oneSigmaRatio;

  /// A shift to apply to the performance in ratio terms, corresponding to the ciOffset.
  double? shiftRatio;

  bool get hasRatioPredictions => meanRatio != null && oneSigmaRatio != null;

  /// Whether the performance is log-normally distributed, with the raw log-space
  /// mean and standard deviation stored in [logMean] and [logSigma].
  ///
  /// This also means that mean, oneSigma, and twoSigma are log units: the
  final bool isLogNormal;

  /// The raw log-space mean of the performance. Null if [isLogNormal] is false.
  double? logMean;

  /// The raw log-space standard deviation of the performance. Null if [isLogNormal] is false.
  double? logSigma;

  AlgorithmPrediction({
    required this.shooter,
    required this.mean,
    required double sigma,
    this.ciOffset = 0.0,
    required this.settings,
    required this.algorithm,
    required this.meanRatio,
    required this.oneSigmaRatio,
    this.shiftRatio,
    int? lowPlace,
    int? highPlace,
    int? medianPlace,
    this.isLogNormal = false,
    this.logMean,
    this.logSigma,
  }) :
      // In log-normal mode, oneSigma is the geometric standard deviation,
      // so 2 sigma is the geometric standard deviation squared rather than
      // twice the arithmetic standard deviation.
      this.oneSigma = sigma,
      this.twoSigma = isLogNormal ? sigma * sigma : sigma * 2 {
        if(lowPlace != null) {
          this.lowPlace = lowPlace;
        }
        if(highPlace != null) {
          this.highPlace = highPlace;
        }
        if(medianPlace != null) {
          this.medianPlace = medianPlace;
        }
      }

  /// A value suitble for ordinal sorting, based off of the 95%/-2 sigma
  /// expected value.
  double get ordinal => mean - twoSigma + shift;

  /// The shift in mean due to the ciOffset.
  double get shift => (oneSigma / 2) * (ciOffset);

  @override
  String toString() {
    return "${shooter.getName(suffixes: false)}: ${mean.toStringAsPrecision(4)} ± ${twoSigma.toStringAsPrecision(4)}";
  }

  double ciOffsetMultiplier({double strength = 0.05}) => 1 + (ciOffset * strength);

  double get center => mean;
  double get shiftedCenter => mean + shift;
  double get upperBox {
    if(isLogNormal) {
      return (mean * oneSigma) + shift;
    }
    else {
     return mean + oneSigma + shift;
    }
  }
  double get lowerBox {
    if(isLogNormal) {
      return (mean / oneSigma) + shift;
    }
    else {
      return mean - oneSigma + shift;
    }
  }
  double get upperWhisker {
    if(isLogNormal) {
      return (mean * twoSigma) + shift;
    }
    else {
      return mean + twoSigma + shift;
    }
  }
  double get lowerWhisker {
    if(isLogNormal) {
      return (mean / twoSigma) + shift;
    }
    else {
      return mean - twoSigma + shift;
    }
  }

  /// The lower bound of the 1-sigma confidence interval.
  double get lowPrediction {
    if (isLogNormal) {
      return (mean / oneSigma) + shift;
    }
    return mean - oneSigma + shift;
  }

  /// The lower bound of the 0.5-sigma confidence interval.
  double get halfLowPrediction {
    if (isLogNormal) {
      // A half-sigma step downward is division by the square root of the GSD
      return (mean / sqrt(oneSigma)) + (shift / 2);
    }
    return mean - oneSigma / 2 + shift / 2;
  }

  /// The upper bound of the 0.5-sigma confidence interval.
  double get halfHighPrediction {
    if (isLogNormal) {
      // A half-sigma step upward is multiplication by the square root of the GSD
      return (mean * sqrt(oneSigma)) + (shift / 2);
    }
    return mean + (oneSigma + shift) / 2;
  }

  /// The upper bound of the 1-sigma confidence interval.
  double get highPrediction {
    if (isLogNormal) {
      return (mean * oneSigma) + shift;
    }
    return mean + (oneSigma + shift);
  }

  double get upperBoxWhiskerMidpoint => (upperBox + upperWhisker) / 2;
  double get lowerBoxWhiskerMidpoint => (lowerBox + lowerWhisker) / 2;

  double? get ratioCenter => meanRatio;
  double? get shiftedRatioCenter {
    if(meanRatio != null && shiftRatio != null) {
      return meanRatio! + shiftRatio!;
    }
    else if(meanRatio != null) {
      return meanRatio!;
    }
    else {
      return null;
    }
  }
}
