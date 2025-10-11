/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

/// A skew normal distribution implementation.
///
/// The skew normal distribution is a continuous probability distribution
/// that generalizes the normal distribution by adding a skewness parameter.
///
/// Parameters:
/// - mu: location parameter (mean when skew = 0)
/// - sigma: scale parameter (standard deviation when skew = 0)
/// - alpha: shape parameter (skewness, positive = right skew, negative = left skew)
class SkewNormal {
  final double mu;
  final double sigma;
  final double alpha;

  static Random random = Random();

  SkewNormal(this.mu, this.sigma, this.alpha) {
    if (sigma <= 0) {
      throw ArgumentError("Sigma must be positive");
    }
  }

  /// Generate n samples from the skew normal distribution
  static List<double> generate(int n, {double mu = 0, double sigma = 1, double alpha = 0}) {
    var samples = <double>[];
    while (samples.length < n) {
      samples.add(_sampleOne(mu, sigma, alpha));
    }
    return samples;
  }

  /// Generate a single sample from the skew normal distribution
  static double _sampleOne(double mu, double sigma, double alpha) {
    // Generate two independent standard normal variables
    var u1 = random.nextDouble();
    var u2 = random.nextDouble();

    // Box-Muller transform for first normal variable
    var z1 = sqrt(-2 * log(u1)) * cos(2 * pi * u2);

    // Second normal variable
    var u3 = random.nextDouble();
    var u4 = random.nextDouble();
    var z2 = sqrt(-2 * log(u3)) * cos(2 * pi * u4);

    // Apply skew normal transformation
    if (alpha == 0) {
      // Standard normal case
      return mu + sigma * z1;
    } else {
      // Skew normal case using the Azzalini method
      var delta = alpha / sqrt(1 + alpha * alpha);
      var z = delta * z1 + sqrt(1 - delta * delta) * z2;

      // Apply rejection sampling for the skew component
      var u = random.nextDouble();
      var acceptance = 2 * _normalCDF(alpha * z1);

      if (u < acceptance) {
        return mu + sigma * z;
      } else {
        // Reject and try again
        return _sampleOne(mu, sigma, alpha);
      }
    }
  }

  /// Generate a single sample from this distribution
  double sample({Random? random}) {
    var actualRandom = random ?? SkewNormal.random;
    var temp = SkewNormal.random;
    SkewNormal.random = actualRandom;
    var result = _sampleOne(mu, sigma, alpha);
    SkewNormal.random = temp;
    return result;
  }

  /// Approximate cumulative distribution function for standard normal
  static double _normalCDF(double x) {
    // Using the approximation: 0.5 * (1 + erf(x / sqrt(2)))
    var z = x / sqrt(2);
    return 0.5 * (1 + _erf(z));
  }

  /// Approximate error function using Abramowitz and Stegun approximation
  static double _erf(double x) {
    // Constants for the approximation
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    const p = 0.3275911;

    // Save the sign of x
    var sign = x < 0 ? -1 : 1;
    x = x.abs();

    // A&S formula 7.1.26
    var t = 1.0 / (1.0 + p * x);
    var y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-x * x);

    return sign * y;
  }

  /// Calculate the theoretical mean of the skew normal distribution
  double get theoreticalMean {
    if (alpha == 0) return mu;
    var delta = alpha / sqrt(1 + alpha * alpha);
    return mu + sigma * delta * sqrt(2 / pi);
  }

  /// Calculate the theoretical variance of the skew normal distribution
  double get theoreticalVariance {
    if (alpha == 0) return sigma * sigma;
    var delta = alpha / sqrt(1 + alpha * alpha);
    return sigma * sigma * (1 - 2 * delta * delta / pi);
  }

  /// Calculate the theoretical skewness of the skew normal distribution
  double get theoreticalSkewness {
    if (alpha == 0) return 0;
    var delta = alpha / sqrt(1 + alpha * alpha);
    var numerator = (4 - pi) / 2 * pow(delta, 3) * pow(2 / pi, 1.5);
    var denominator = pow(1 - 2 * delta * delta / pi, 1.5);
    return numerator / denominator;
  }

  @override
  String toString() {
    return "SkewNormal(mu: $mu, sigma: $sigma, alpha: $alpha)";
  }
}
