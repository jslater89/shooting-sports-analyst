/*
Spitballing some ideas:

1. Confidence intervals
Assume performances are normally distributed, with stddev smaller than scale implies.
(Tunable param?) Scale stddev based on error, adjust the center of the CI based on
trend. Display bar graphs per shooter, in a column where they're on the same scale.

See if rating percentage correlates with match finish percentage?

2. As above, but with probabilities.
 */

import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';

class ShooterPrediction {
  final ShooterRating shooter;

  final double mean;
  final double oneSigma;
  final double twoSigma;
  final double ciOffset;

  ShooterPrediction({required this.shooter, required this.mean, required double sigma, this.ciOffset = 0.5}) :
      this.oneSigma = sigma,
      this.twoSigma = sigma * 2;

  double get ordinal => mean - twoSigma + shift;

  double get shift => (oneSigma / 2) * (ciOffset);

  @override
  String toString() {
    return "${shooter.shooter.getName(suffixes: false)}: ${mean.toStringAsPrecision(4)} ± ${twoSigma.toStringAsPrecision(4)}";
  }
}