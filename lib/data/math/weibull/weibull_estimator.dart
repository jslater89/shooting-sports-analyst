/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';
import 'package:data/data.dart';

/// Estimates Weibull distribution parameters from a dataset using Maximum Likelihood Estimation
class WeibullEstimator {
  /// Maximum number of iterations for the Newton-Raphson method
  static const int _maxIterations = 100;

  /// Convergence threshold for the Newton-Raphson method
  static const double _tolerance = 1e-6;

  /// Estimates Weibull distribution parameters from the given data points
  ///
  /// Returns a [WeibullDistribution] fitted to the provided data
  /// Throws [ArgumentError] if the data is empty or contains non-positive values
  WeibullDistribution estimate(List<double> data) {
    if (data.isEmpty) {
      throw ArgumentError("Data list cannot be empty");
    }
    if (data.any((x) => x <= 0)) {
      throw ArgumentError("All data points must be positive");
    }

    // Initial guess for shape parameter (k) using moment matching
    var shape = _initialShapeEstimate(data);

    // Newton-Raphson iteration to find the shape parameter
    for (var i = 0; i < _maxIterations; i++) {
      final (fValue, fPrime) = _shapeFunction(shape, data);
      final delta = fValue / fPrime;
      shape -= delta;

      if (shape <= 0) {
        shape = 0.01; // Prevent negative shape values
      }

      if (delta.abs() < _tolerance) {
        break;
      }
    }

    // Calculate scale parameter using MLE formula
    final scale = _calculateScale(shape, data);

    return WeibullDistribution(scale, shape);
  }

  /// Calculates initial shape parameter estimate using moment matching
  double _initialShapeEstimate(List<double> data) {
    final mean = data.reduce((a, b) => a + b) / data.length;
    final variance = data.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / data.length;
    final coeffVar = sqrt(variance) / mean;
    return pow(coeffVar, -1.086).toDouble(); // Approximation based on the coefficient of variation
  }

  /// Calculates the shape function and its derivative for Newton-Raphson method
  (double, double) _shapeFunction(double k, List<double> data) {
    final n = data.length;
    var sumLogX = 0.0;
    var sumXk = 0.0;
    var sumXkLnX = 0.0;
    var sumLnX = 0.0;

    for (final x in data) {
      final logX = log(x);
      sumLogX += logX;
      final xk = pow(x, k);
      sumXk += xk;
      sumXkLnX += xk * logX;
      sumLnX += logX;
    }

    final fValue = n / k + sumLogX - n * sumXkLnX / sumXk;
    final fPrime = -n / (k * k) - n * (sumXk * sumXkLnX * sumXkLnX - sumXk * sumXk * _sumXkLnXSquared(data, k)) / (sumXk * sumXk);

    return (fValue, fPrime);
  }

  /// Helper function to calculate sum of x^k * (ln x)^2
  double _sumXkLnXSquared(List<double> data, double k) {
    return data.map((x) => pow(x, k) * pow(log(x), 2)).reduce((a, b) => a + b).toDouble();
  }

  /// Calculates scale parameter using MLE formula
  double _calculateScale(double shape, List<double> data) {
    final n = data.length;
    final sumXk = data.map((x) => pow(x, shape)).reduce((a, b) => a + b);
    return pow(sumXk / n, 1 / shape).toDouble();
  }
}
