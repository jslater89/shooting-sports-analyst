/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:data/data.dart' show ContinuousDistribution;
import 'package:more/src/printer/object/object.dart';

class LaplaceDistribution extends ContinuousDistribution {
  final double mu;
  final double b;

  LaplaceDistribution({required this.mu, required this.b});

  @override
  ObjectPrinter get toStringPrinter => super.toStringPrinter
    ..addValue(mu, name: 'mu')
    ..addValue(b, name: 'b');

  @override
  double cumulativeProbability(double x) {
    if (x < mu) {
      return 0.5 * exp((x - mu) / b);
    } else {
      return 1.0 - 0.5 * exp(-(x - mu) / b);
    }
  }

  @override
  double inverseCumulativeProbability(num p) {
    if (p <= 0) return double.negativeInfinity;
    if (p >= 1) return double.infinity;
    if (p == 0.5) return mu;

    if (p < 0.5) {
      return mu + b * log(2 * p);
    } else {
      return mu - b * log(2 * (1 - p));
    }
  }

  @override
  double inverseSurvival(num p) {
    if (p <= 0) return double.infinity;
    if (p >= 1) return double.negativeInfinity;

    return mu - b * log(2 * p);
  }

  @override
  double get kurtosisExcess => 6;

  @override
  double get lowerBound => -double.infinity;

  @override
  double get mean => mu;

  @override
  double get median => mu;

  @override
  double get mode => mu;

  @override
  double probability(double x) {
    return (1.0 / (2.0 * b)) * exp(-(x - mu).abs() / b);
  }

  @override
  double sample({Random? random}) {
    var actualRandom = random ?? Random();
    return mu - b * log(1 - actualRandom.nextDouble()) * (actualRandom.nextDouble() < 0.5 ? 1 : -1);
  }

  @override
  double get skewness => 0;

  @override
  double get standardDeviation => sqrt(2 * b * b);

  @override
  double survival(double x) {
    if (x < mu) {
      return 1.0 - 0.5 * exp((x - mu) / b);
    } else {
      return 0.5 * exp(-(x - mu) / b);
    }
  }

  @override
  double get upperBound => double.infinity;

  @override
  double get variance => 2 * b * b;
}
