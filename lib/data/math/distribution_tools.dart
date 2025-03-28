/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:data/data.dart';
import 'package:shooting_sports_analyst/data/math/gamma/gamma_estimator.dart';
import 'package:shooting_sports_analyst/data/math/gaussian/gaussian_estimator.dart';
import 'package:shooting_sports_analyst/data/math/lognormal/lognormal_estimator.dart';
import 'package:shooting_sports_analyst/data/math/weibull/weibull_estimator.dart';
import 'package:shooting_sports_analyst/util.dart';

abstract class ContinuousDistributionEstimator {
  ContinuousDistribution estimate(List<double> data);
}

enum AvailableEstimator {
  gamma,
  weibull,
  logNormal,
  normal;

  String get uiLabel => switch(this) {
    gamma => "Gamma",
    weibull => "Weibull",
    logNormal => "Log-normal",
    normal => "Normal",
  };

  ContinuousDistributionEstimator get estimator {
    switch (this) {
      case AvailableEstimator.gamma:
        return GammaEstimator();
      case AvailableEstimator.weibull:
        return WeibullEstimator();
      case AvailableEstimator.logNormal:
        return LogNormalEstimator();
      case AvailableEstimator.normal:
        return GaussianEstimator();
    }
  }

  static AvailableEstimator fromEstimator(ContinuousDistributionEstimator estimator) {
    switch (estimator.runtimeType) {
      case GammaEstimator:
        return AvailableEstimator.gamma;
      case WeibullEstimator:
        return AvailableEstimator.weibull;
      case LogNormalEstimator:
        return AvailableEstimator.logNormal;
      case GaussianEstimator:
        return AvailableEstimator.normal;
      default:
        throw ArgumentError("Unknown estimator: $estimator");
    }
  }
}

extension StatisticalTests on ContinuousDistribution {
  /// Calculates the log likelihood of the observed data given this distribution
  ///
  /// The log likelihood measures how well this distribution fits the provided data.
  /// Higher values indicate better fit.
  ///
  /// Returns the sum of the natural logarithms of the PDF evaluated at each data point.
  /// Returns [double.negativeInfinity] if any data point has zero probability density.
  double logLikelihood(List<double> data) {
    if (data.isEmpty) {
      return 0.0; // Log likelihood is 0 for empty datasets
    }

    double sum = 0.0;

    for (final value in data) {
      final density = probability(value);

      // If any point has zero density, the likelihood is zero and log likelihood is -∞
      if (density <= 0) {
        return double.negativeInfinity;
      }

      sum += log(density);
    }

    return sum;
  }

  /// Calculates the Kolmogorov-Smirnov test statistic for goodness of fit
  ///
  /// The Kolmogorov-Smirnov test (KS test) compares the cumulative distribution
  /// function (CDF) of the observed data with the CDF of the hypothesized distribution.
  ///
  /// Returns the maximum absolute difference between the empirical CDF and the theoretical CDF.
  double kolmogorovSmirnovTest(List<double> data) {
    if (data.isEmpty) {
      return 0.0;
    }

    // Sort the data
    final sortedData = List<double>.from(data)..sort();
    final n = sortedData.length;

    double maxDifference = 0.0;

    // Check differences at each data point
    for (int i = 0; i < n; i++) {
      final x = sortedData[i];

      // Theoretical CDF at this point
      final theoreticalCdf = cumulativeProbability(x);

      // Empirical CDF at this point (i+1)/n
      final empiricalCdf = (i + 1) / n;

      // Difference at this point
      final difference = (theoreticalCdf - empiricalCdf).abs();

      // Also check the difference at the previous step
      final previousEmpirical = i > 0 ? i / n : 0.0;
      final previousDifference = (theoreticalCdf - previousEmpirical).abs();

      // Update maximum difference
      maxDifference = max(maxDifference, max(difference, previousDifference));
    }

    return maxDifference;
  }

  /// Calculates the chi-square test statistic for goodness of fit
  ///
  /// The chi-square test (χ² test) compares observed frequencies in bins
  /// with the frequencies expected under this distribution.
  ///
  /// Parameters:
  ///   data - The observed data points
  ///   bins - Number of equal-probability bins to use (default: 10)
  ///
  /// Returns the chi-square test statistic.
  double chiSquareTest(List<double> data, {int bins = 10}) {
    if (data.isEmpty || bins < 2) {
      return 0.0;
    }

    // Sort the data
    final sortedData = List<double>.from(data)..sort();
    final n = sortedData.length;

    // Expected count in each bin
    final expectedCount = n / bins;

    // Create equal-probability bins
    final binBoundaries = <double>[];
    for (int i = 1; i < bins; i++) {
      binBoundaries.add(inverseCumulativeProbability(i / bins));
    }

    // Count observations in each bin
    final observedCounts = List<int>.filled(bins, 0);
    int currentBin = 0;

    for (final value in sortedData) {
      while (currentBin < bins - 1 && value >= binBoundaries[currentBin]) {
        currentBin++;
      }
      observedCounts[currentBin]++;
    }

    // Calculate chi-square statistic
    double chiSquare = 0.0;
    for (final observed in observedCounts) {
      final diff = observed - expectedCount;
      chiSquare += (diff * diff) / expectedCount;
    }

    return chiSquare;
  }

  /// Calculates the Anderson-Darling test statistic for goodness of fit
  ///
  /// The Anderson-Darling test is particularly sensitive to deviations in the tails
  /// of the distribution. It applies weights to the squared difference between the
  /// empirical and theoretical CDFs, with larger weights in the tails.
  ///
  /// Lower A² values indicate better fit. Unlike KS test, this test is more sensitive
  /// to discrepancies in the tails of the distribution.
  ///
  /// Returns the Anderson-Darling test statistic (A²).
  double andersonDarlingTest(List<double> data) {
    if (data.isEmpty) {
      return 0.0;
    }

    // Sort the data
    final sortedData = List<double>.from(data)..sort();
    final n = sortedData.length;

    // Calculate the test statistic
    double sum = 0.0;

    for (int i = 0; i < n; i++) {
      // Get the current data point
      final x = sortedData[i];

      // Calculate the theoretical CDF at this point
      final F = cumulativeProbability(x);

      // Calculate indices for the sum
      final i1 = i + 1;

      // Calculate the weighted term for this data point
      // The weighting function gives more importance to the tails
      final term = (2 * i1 - 1) * (log(F) + log(1 - cumulativeProbability(sortedData[n - i1])));

      sum += term;
    }

    // Calculate the final statistic
    final aSquared = -n - (sum / n);

    return aSquared;
  }
}

extension GetEstimator on ContinuousDistribution {
  ContinuousDistributionEstimator get estimator {
    return switch(this) {
      GammaDistribution() => GammaEstimator(),
      WeibullDistribution() => WeibullEstimator(),
      LogNormalDistribution() => LogNormalEstimator(),
      NormalDistribution() => GaussianEstimator(),
      _ => throw ArgumentError("No estimator for distribution: $runtimeType"),
    };
  }
}

extension ParameterString on ContinuousDistribution {
  String get parameterString {
    return switch(this) {
      GammaDistribution(:final shape, :final scale) => "Shape: ${shape.toStringWithSignificantDigits(5)}, Scale: ${scale.toStringWithSignificantDigits(5)}",
      WeibullDistribution(:final shape, :final scale) => "Shape: ${shape.toStringWithSignificantDigits(5)}, Scale: ${scale.toStringWithSignificantDigits(5)}",
      LogNormalDistribution(:final mu, :final sigma) => "Mu: ${mu.toStringWithSignificantDigits(5)}, Sigma: ${sigma.toStringWithSignificantDigits(5)}",
      NormalDistribution(:final mu, :final sigma) => "Mu: ${mu.toStringWithSignificantDigits(5)}, Sigma: ${sigma.toStringWithSignificantDigits(5)}",
      _ => throw ArgumentError("No parameter string for distribution: $runtimeType"),
    };
  }
}
