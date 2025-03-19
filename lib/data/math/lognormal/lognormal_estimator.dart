/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:data/stats.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';

class LogNormalEstimator implements ContinuousDistributionEstimator {
  LogNormalEstimator();

  LogNormalDistribution estimate(List<double> values) {
    // Take the natural logarithm of all values
    final logValues = values.map((value) => value > 0 ? log(value) : 0.0);

    // Calculate the mean of the log values (mu)
    final mu = logValues.average();

    // Calculate the standard deviation of the log values (sigma)
    final sigma = logValues.standardDeviation();

    return LogNormalDistribution(mu, sigma);
  }
}
