/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:data/data.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';

class GaussianEstimator extends ContinuousDistributionEstimator {
  @override
  NormalDistribution estimate(List<double> data) {
    if(data.isEmpty) {
      throw ArgumentError("Data list cannot be empty");
    }
    return NormalDistribution(
      data.average(),
      data.standardDeviation(),
    );
  }
}
