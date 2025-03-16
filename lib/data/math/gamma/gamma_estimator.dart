/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:dart_numerics/dart_numerics.dart';
import 'package:data/data.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';

class GammaEstimator implements ContinuousDistributionEstimator {
  /// Maximum number of iterations for the Newton-Raphson method
  static const int _maxIterations = 100;

  /// Convergence threshold for the Newton-Raphson method
  static const double _tolerance = 1e-6;

  /// Estimates Gamma distribution parameters from the given data points
  ///
  /// Returns a [GammaDistribution] fitted to the provided data
  /// Throws [ArgumentError] if the data is empty or contains non-positive values
  GammaDistribution estimate(List<double> data) {
    if (data.isEmpty) {
      throw ArgumentError("Data list cannot be empty");
    }
    if (data.any((x) => x <= 0)) {
      throw ArgumentError("All data points must be positive");
    }

    // Calculate necessary statistics
    final n = data.length;
    final mean = data.average();
    final logMean = data.map(log).average();
    final s = log(mean) - logMean;

    // Initial guess for shape parameter (k)
    var shape = (3 - s + sqrt((s - 3) * (s - 3) + 24 * s)) / (12 * s);

    // Newton-Raphson iteration to find the shape parameter
    for (var i = 0; i < _maxIterations; i++) {
      final (fValue, fPrime) = _shapeFunction(shape, s);
      final delta = fValue / fPrime;
      shape -= delta;

      if (shape <= 0) {
        shape = 0.01; // Prevent negative shape values
      }

      if (delta.abs() < _tolerance) {
        break;
      }
    }

    // Calculate scale parameter
    final scale = mean / shape;

    return GammaDistribution(shape, scale);
  }

  /// Calculates the shape function and its derivative for Newton-Raphson method
  (double, double) _shapeFunction(double k, double s) {
    final fValue = log(k) - diGamma(k) - s;
    final fPrime = 1 / k - _approximateTrigamma(k);
    return (fValue, fPrime);
  }

  /// Approximates the trigamma function using numerical differentiation of digamma
  double _approximateTrigamma(double x) {
    const h = 1e-5; // Step size for numerical differentiation
    return (diGamma(x + h) - diGamma(x - h)) / (2 * h);
  }
}
