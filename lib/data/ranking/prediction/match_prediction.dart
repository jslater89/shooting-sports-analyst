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

import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';

/// An algorithmic prediction for a shooter's finish.
///
/// Users of this class are responsible for filling in [lowPlace] and [highPlace].
class AlgorithmPrediction {
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

  AlgorithmPrediction({
    required this.shooter, required this.mean, required double sigma, this.ciOffset = 0.0,
  }) :
      this.oneSigma = sigma,
      this.twoSigma = sigma * 2;

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
  double get upperBox => mean + oneSigma + shift;
  double get lowerBox => mean - oneSigma + shift;
  double get upperWhisker => mean + twoSigma + shift;
  double get lowerWhisker => mean - twoSigma + shift;

  double get lowPrediction => mean - oneSigma + shift;
  double get halfLowPrediction => mean - oneSigma / 2 + shift / 2;
  double get halfHighPrediction => mean + (oneSigma + shift) / 2;
  double get highPrediction => mean + (oneSigma + shift);

  double get upperBoxWhiskerMidpoint => (upperBox + upperWhisker) / 2;
  double get lowerBoxWhiskerMidpoint => (lowerBox + lowerWhisker) / 2;
}
