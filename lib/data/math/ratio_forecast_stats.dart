/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Ratio-scale forecast diagnostics (MAE, MAPE, CRPS, σ coverage) shared by
/// backtests and UI debug tooling.

import "dart:math";

import "package:normal/normal.dart";
import "package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart";

/// Per-shooter metrics for one forecast versus one realized finish ratio (and rank).
class RatioForecastMetrics {
  final double mape;
  final double mpe;
  final double mpeArith;
  final double mae;
  final double crps;
  final double rankMae;
  final bool within1Sigma;
  final bool within2Sigma;

  const RatioForecastMetrics({
    required this.mape,
    required this.mpe,
    required this.mpeArith,
    required this.mae,
    required this.crps,
    required this.rankMae,
    required this.within1Sigma,
    required this.within2Sigma,
  });
}

/// Aggregates [RatioForecastMetrics] into means and coverage rates (same
/// definitions as [bin/db_oneoff_impl/backtest_raters_command.dart]).
class RatioForecastStatsAccumulator {
  int n = 0;
  double mapeSum = 0.0;
  double mpeSum = 0.0;
  double mpeArithSum = 0.0;
  double maeSum = 0.0;
  double crpsSum = 0.0;
  double rankMaeSum = 0.0;
  int _within1SigmaCount = 0;
  int _within2SigmaCount = 0;

  void add(RatioForecastMetrics m) {
    n++;
    mapeSum += m.mape;
    mpeSum += m.mpe;
    mpeArithSum += m.mpeArith;
    maeSum += m.mae;
    crpsSum += m.crps;
    rankMaeSum += m.rankMae;
    if (m.within1Sigma) {
      _within1SigmaCount++;
    }
    if (m.within2Sigma) {
      _within2SigmaCount++;
    }
  }

  /// Convenience: compute metrics from an [AlgorithmPrediction] and add if valid.
  void tryAddPrediction(
    AlgorithmPrediction prediction, {
    required double actualRatio,
    required int actualPlace,
  }) {
    final m = ratioForecastMetricsForPrediction(
      prediction,
      actualRatio: actualRatio,
      actualPlace: actualPlace,
    );
    if (m != null) {
      add(m);
    }
  }

  double get mape => n == 0 ? double.nan : mapeSum / n;
  double get mpe => n == 0 ? double.nan : mpeSum / n;
  double get mpeArith => n == 0 ? double.nan : mpeArithSum / n;
  double get mae => n == 0 ? double.nan : maeSum / n;
  double get crps => n == 0 ? double.nan : crpsSum / n;
  double get rankMae => n == 0 ? double.nan : rankMaeSum / n;
  double get coverage1Sigma => n == 0 ? double.nan : _within1SigmaCount / n;
  double get coverage2Sigma => n == 0 ? double.nan : _within2SigmaCount / n;

  /// Alias names matching the legacy backtest stats getters.
  double get coverage1 => coverage1Sigma;
  double get coverage2 => coverage2Sigma;

  /// One-line summary for logs (matches backtest overall row shape).
  String debugSummary({String prefix = ""}) {
    if (n == 0) {
      return "${prefix}n=0 (no valid ratio-forecast samples)";
    }
    return "${prefix}n=$n  "
        "MAPE=${(mape * 100).toStringAsFixed(2)}%  "
        "MPE=${_fmtSignedPct(mpe)}  "
        "MPE(arith)=${_fmtSignedPct(mpeArith)}  "
        "MAE=${mae.toStringAsFixed(4)}  "
        "CRPS=${crps.toStringAsFixed(4)}  "
        "RankMAE=${rankMae.toStringAsFixed(2)} places  "
        "1σ coverage=${(coverage1Sigma * 100).toStringAsFixed(1)}% (ideal ~68.3%)  "
        "2σ coverage=${(coverage2Sigma * 100).toStringAsFixed(1)}% (ideal ~95.4%)";
  }
}

/// Closed-form CRPS for a normal forecast on the ratio scale (Gneiting & Raftery 2007).
///
/// CRPS(N(μ,σ), x) = σ * [z*(2Φ(z) - 1) + 2φ(z) - 1/√π]
double ratioForecastCrpsNormal(double mu, double sigma, double x) {
  if (sigma <= 0) {
    return (x - mu).abs();
  }
  final z = (x - mu) / sigma;
  final phi = Normal.cdf(z);
  final pdf = Normal.pdf(z);
  return sigma * (z * (2 * phi - 1) + 2 * pdf - 1 / sqrt(pi));
}

/// Closed-form CRPS for a log-normal forecast on the ratio scale (Baran & Lerch 2015).
///
/// For Y ~ Lognormal(μ, σ²) and observation y > 0:
///   CRPS(LN(μ,σ²), y) =
///     y * (2Φ(ω) - 1)
///     - 2 * exp(μ + σ²/2) * [Φ(ω - σ) + Φ(σ/√2) - 1]
/// where ω = (ln y - μ) / σ.
double ratioForecastCrpsLogNormal(double muLog, double sigmaLog, double y) {
  if (sigmaLog <= 0 || y <= 0) {
    return double.nan;
  }
  final omega = (log(y) - muLog) / sigmaLog;
  final term1 = y * (2 * Normal.cdf(omega) - 1);
  final scale = exp(muLog + (sigmaLog * sigmaLog) / 2);
  final term2 = 2 *
      scale *
      (Normal.cdf(omega - sigmaLog) + Normal.cdf(sigmaLog / sqrt(2)) - 1);
  return term1 - term2;
}

/// Builds [RatioForecastMetrics] from a hydrated [AlgorithmPrediction], using the
/// same center / σ semantics as the raters backtest command.
RatioForecastMetrics? ratioForecastMetricsForPrediction(
  AlgorithmPrediction prediction, {
  required double actualRatio,
  required int actualPlace,
}) {
  double mean;
  double oneSigma;
  if (prediction.isLogNormal) {
    mean = prediction.displayCenter;
    oneSigma = prediction.oneSigma;
    if (mean <= 0 || oneSigma <= 1.0 || actualRatio <= 0) {
      return null;
    }
  }
  else {
    if (!prediction.hasRatioPredictions) {
      return null;
    }
    mean = prediction.expectedRatio!;
    oneSigma = prediction.oneSigmaRatio!;
    if (oneSigma <= 0) {
      return null;
    }
  }

  return ratioForecastMetrics(
    actualRatio: actualRatio,
    actualPlace: actualPlace,
    predictedPlace: prediction.medianPlace,
    isLogNormal: prediction.isLogNormal,
    mean: mean,
    oneSigma: oneSigma,
  );
}

/// Low-level metric computation when centers and spreads are already resolved.
RatioForecastMetrics ratioForecastMetrics({
  required double actualRatio,
  required int actualPlace,
  required int predictedPlace,
  required bool isLogNormal,
  required double mean,
  required double oneSigma,
}) {
  final signedError = actualRatio - mean;
  final mae = signedError.abs();
  final absActual = actualRatio.abs();
  final mape = absActual < 1e-9 ? mae : mae / absActual;
  final mpe = absActual < 1e-9 ? signedError : signedError / absActual;
  final rankMae = (actualPlace - predictedPlace).abs().toDouble();

  double crps;
  bool within1;
  bool within2;
  double arithCenter;
  if (isLogNormal) {
    final muLog = log(mean);
    final sigmaLog = log(oneSigma);
    crps = ratioForecastCrpsLogNormal(muLog, sigmaLog, actualRatio);
    final low1 = mean / oneSigma;
    final high1 = mean * oneSigma;
    final low2 = mean / (oneSigma * oneSigma);
    final high2 = mean * (oneSigma * oneSigma);
    within1 = actualRatio >= low1 && actualRatio <= high1;
    within2 = actualRatio >= low2 && actualRatio <= high2;
    arithCenter = mean * exp((sigmaLog * sigmaLog) / 2);
  }
  else {
    crps = ratioForecastCrpsNormal(mean, oneSigma, actualRatio);
    within1 = (actualRatio - mean).abs() <= oneSigma;
    within2 = (actualRatio - mean).abs() <= 2 * oneSigma;
    arithCenter = mean;
  }

  final signedErrorArith = actualRatio - arithCenter;
  final mpeArith =
      absActual < 1e-9 ? signedErrorArith : signedErrorArith / absActual;

  return RatioForecastMetrics(
    mape: mape,
    mpe: mpe,
    mpeArith: mpeArith,
    mae: mae,
    crps: crps,
    rankMae: rankMae,
    within1Sigma: within1,
    within2Sigma: within2,
  );
}

/// Formats a signed fractional error (e.g. 0.0123) as a percentage with sign.
String formatSignedForecastPercent(double v) => _fmtSignedPct(v);

String _fmtSignedPct(double v) {
  if (v.isNaN) {
    return "NaN";
  }
  final pct = v * 100;
  final sign = pct >= 0 ? "+" : "";
  return "$sign${pct.toStringAsFixed(2)}%";
}
