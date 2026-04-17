// _BacktestMatch's named constructor parameters are unused while the
// _matches list below is empty; users of this command are expected to fill
// the list with real source IDs and/or exact names.
// ignore_for_file: unused_element_parameter

import "dart:math";

import "package:dart_console/dart_console.dart";
import "package:normal/normal.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/logger.dart";

import "base.dart";

final _log = SSALogger("BacktestRaters");

/// A match to backtest against. [sourceIds] is preferred; if empty,
/// [exactName] is used as a fallback.
class _BacktestMatch {
  final List<String> sourceIds;
  final String? exactName;

  const _BacktestMatch({this.sourceIds = const [], this.exactName});
}

/// Controls which subset of competitors is scored in a given pass.
///
/// - [all]: every shooter that matches the group filters (current behavior).
/// - [ratedOnly]: re-score the match using only the competitors who have a
///   prior rating in the project. Ratios and ranks are recomputed against
///   this smaller field, so rank predictions are less sensitive to
///   registration noise.
enum _Mode {
  all,
  ratedOnly;

  String get label => switch (this) {
    _Mode.all => "all",
    _Mode.ratedOnly => "rated-only",
  };
}

/// One observation pulled from a single (mode, project, group, match, shooter).
class _Sample {
  final _Mode mode;
  final String algorithm;
  final String projectName;
  final String groupName;
  final String matchName;
  final DateTime matchDate;

  /// The shooter's actual finish ratio (1.0 for the winner of the scored
  /// subset).
  final double actualRatio;

  /// The shooter's actual finish place (1 for the winner of the scored
  /// subset).
  final int actualPlace;

  /// Predicted center on the natural scale.
  /// - Normal raters: arithmetic mean ratio (`prediction.meanRatio`).
  /// - Log-normal raters: median ratio (`prediction.mean`).
  final double mean;

  /// Predicted spread on the natural scale.
  /// - Normal raters: standard deviation in ratio terms (`prediction.oneSigmaRatio`).
  /// - Log-normal raters: geometric standard deviation (`prediction.oneSigma`).
  final double oneSigma;

  /// Predicted median place (integer rank, 1-indexed).
  final int predictedPlace;

  /// True if the underlying distribution is log-normal.
  final bool isLogNormal;

  _Sample({
    required this.mode,
    required this.algorithm,
    required this.projectName,
    required this.groupName,
    required this.matchName,
    required this.matchDate,
    required this.actualRatio,
    required this.actualPlace,
    required this.mean,
    required this.oneSigma,
    required this.predictedPlace,
    required this.isLogNormal,
  });
}

class _Stats {
  int n = 0;
  double mapeSum = 0.0;
  /// Signed percentage error: (actual - predicted) / |actual|.
  /// Positive mean => systematic under-prediction; negative => over-prediction.
  ///
  /// "Predicted" here is the forecast's central estimate: arithmetic mean for
  /// normal raters, median for log-normal raters.
  double mpeSum = 0.0;
  /// Signed percentage error versus the forecast's arithmetic mean.
  /// For normal raters this is identical to [mpeSum]. For log-normal raters
  /// the center is lifted from the median to `median * exp(σ_log² / 2)`, which
  /// removes the structural median-vs-mean offset baked into MPE for LLR.
  double mpeArithSum = 0.0;
  double maeSum = 0.0;
  double crpsSum = 0.0;
  double rankMaeSum = 0.0;
  int within1Sigma = 0;
  int within2Sigma = 0;

  void add({
    required double mape,
    required double mpe,
    required double mpeArith,
    required double mae,
    required double crps,
    required double rankMae,
    required bool within1,
    required bool within2,
  }) {
    n++;
    mapeSum += mape;
    mpeSum += mpe;
    mpeArithSum += mpeArith;
    maeSum += mae;
    crpsSum += crps;
    rankMaeSum += rankMae;
    if (within1) {
      within1Sigma++;
    }
    if (within2) {
      within2Sigma++;
    }
  }

  double get mape => n == 0 ? double.nan : mapeSum / n;
  double get mpe => n == 0 ? double.nan : mpeSum / n;
  double get mpeArith => n == 0 ? double.nan : mpeArithSum / n;
  double get mae => n == 0 ? double.nan : maeSum / n;
  double get crps => n == 0 ? double.nan : crpsSum / n;
  double get rankMae => n == 0 ? double.nan : rankMaeSum / n;
  double get coverage1 => n == 0 ? double.nan : within1Sigma / n;
  double get coverage2 => n == 0 ? double.nan : within2Sigma / n;
}

class BacktestRatersCommand extends DbOneoffCommand {
  BacktestRatersCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "BR";

  @override
  final String title = "Backtest Raters (Elo / Glicko / LLR)";

  /// Project name -> human label.
  static const Map<String, String> _projectsToTest = {
    "L2s Main Elo Backtesting": "Elo",
    "L2s Main Glicko Backtesting": "Glicko",
    "L2s Main LLR Backtesting": "LLR",
  };

  /// Matches to backtest against. Source IDs preferred; fall back to exact
  /// match name when source IDs are unavailable.
  static const List<_BacktestMatch> _matches = [
    _BacktestMatch(sourceIds: ["a36f1dc5-7954-4fc5-9488-0c81d37e8c1d"]), // Race Gun Nationals
    _BacktestMatch(sourceIds: ["1530fa4f-c371-433f-ae8a-c58f13f722a3"]), // Area 8
    _BacktestMatch(sourceIds: ["27529bb0-411b-4aac-911c-704ef41791b7"]), // Area 2
    _BacktestMatch(exactName: "The 2025 SIG Sauer Factory Gun Nationals presented by Vortex Optics"),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    if (_matches.isEmpty) {
      console.print(
        "No backtest matches configured. Edit the _matches list in "
        "backtest_raters_command.dart to add some.",
      );
      return;
    }

    // (mode, algorithm) -> aggregated stats across all (project, group, match)
    final Map<(_Mode, String), _Stats> overall = {};
    // (mode, algorithm, project, group) -> stats
    final Map<(_Mode, String), _Stats> perGroup = {};
    // Ordered key for printing.
    final List<(_Mode, String)> perGroupOrder = [];

    for (final entry in _projectsToTest.entries) {
      final projectName = entry.key;
      final algorithmLabel = entry.value;

      final project = await db.getRatingProjectByName(projectName);
      if (project == null) {
        console.print("Project not found: $projectName");
        continue;
      }

      if (!project.dbGroups.isLoaded) {
        await project.dbGroups.load();
      }
      final groups = project.groups;

      for (final group in groups) {
        for (final mode in _Mode.values) {
          final groupKey = "$algorithmLabel | $projectName | ${group.name}";
          perGroup.putIfAbsent((mode, groupKey), () {
            perGroupOrder.add((mode, groupKey));
            return _Stats();
          });
        }

        for (final btMatch in _matches) {
          final dbMatch = await _resolveMatch(btMatch);
          if (dbMatch == null) {
            console.print(
              "  [skip] match not found (sourceIds=${btMatch.sourceIds}, "
              "name=${btMatch.exactName}) for $algorithmLabel | $projectName | ${group.name}",
            );
            continue;
          }

          final hydrateRes = dbMatch.hydrateSync(useCache: true);
          if (hydrateRes.isErr()) {
            console.print(
              "  [skip] failed to hydrate ${dbMatch.eventName}: "
              "${hydrateRes.unwrapErr()}",
            );
            continue;
          }
          final ShootingMatch match = hydrateRes.unwrap();

          // Score the full field in this group first. We use it both for
          // mode=all and to identify which competitors have a rating (for
          // mode=ratedOnly).
          final fullScores = match.getScoresFromFilters(group.filters);
          if (fullScores.isEmpty) {
            continue;
          }

          // Look up a wrapped rating for each scored competitor, keyed by
          // MatchEntry.entryId so we can reuse it for the rated-only pass.
          final Map<int, ShooterRating> ratingByEntryId = {};
          for (final scoreEntry in fullScores.entries) {
            final entry = scoreEntry.key;
            final rating = _lookupRating(project, group, entry);
            if (rating == null) {
              continue;
            }
            // Same common-denominator filter as before: ratings with no
            // events don't belong in cross-algorithm comparisons.
            if (rating.length <= 0) {
              continue;
            }
            ratingByEntryId[entry.entryId] = rating;
          }

          // Mode: all competitors.
          _runPipeline(
            mode: _Mode.all,
            algorithmLabel: algorithmLabel,
            projectName: projectName,
            group: group,
            project: project,
            match: match,
            scores: fullScores,
            ratingByEntryId: ratingByEntryId,
            perGroup: perGroup,
            overall: overall,
          );

          // Mode: only competitors with a prior rating. Re-score so ratios
          // and ranks are relative to just this subset.
          if (ratingByEntryId.length >= 2) {
            final ratedOnlyScores = match.getScoresFromFilters(
              group.filters,
              shooterIds: ratingByEntryId.keys.toList(),
            );
            if (ratedOnlyScores.isNotEmpty) {
              _runPipeline(
                mode: _Mode.ratedOnly,
                algorithmLabel: algorithmLabel,
                projectName: projectName,
                group: group,
                project: project,
                match: match,
                scores: ratedOnlyScores,
                ratingByEntryId: ratingByEntryId,
                perGroup: perGroup,
                overall: overall,
              );
            }
          }
        }
      }
    }

    _printResults(console, perGroupOrder, perGroup, overall);
  }

  /// Run the prediction + accumulation pipeline for one (mode, group, match)
  /// cell. Shared between the full-field and rated-only passes.
  void _runPipeline({
    required _Mode mode,
    required String algorithmLabel,
    required String projectName,
    required RatingGroup group,
    required DbRatingProject project,
    required ShootingMatch match,
    required Map<MatchEntry, RelativeMatchScore> scores,
    required Map<int, ShooterRating> ratingByEntryId,
    required Map<(_Mode, String), _Stats> perGroup,
    required Map<(_Mode, String), _Stats> overall,
  }) {
    final groupKey = "$algorithmLabel | $projectName | ${group.name}";
    final groupStats = perGroup.putIfAbsent((mode, groupKey), () {
      return _Stats();
    });
    final overallStats = overall.putIfAbsent(
      (mode, algorithmLabel),
      () => _Stats(),
    );

    // Build rating list and record each rating's actual (ratio, place) in
    // the (possibly re-scored) field.
    final List<ShooterRating> ratings = [];
    final Map<ShooterRating, ({double ratio, int place})> actualByRating = {};
    for (final scoreEntry in scores.entries) {
      final entry = scoreEntry.key;
      final score = scoreEntry.value;
      final rating = ratingByEntryId[entry.entryId];
      if (rating == null) {
        continue;
      }
      ratings.add(rating);
      actualByRating[rating] = (ratio: score.ratio, place: score.place);
    }

    if (ratings.length < 2) {
      return;
    }

    final predictions = project.settings.algorithm
        .predict(ratings, matchDate: match.date);

    for (final prediction in predictions) {
      final actual = actualByRating[prediction.shooter];
      if (actual == null) {
        continue;
      }
      final sample = _sampleFromPrediction(
        mode: mode,
        algorithm: algorithmLabel,
        projectName: projectName,
        groupName: group.name,
        match: match,
        actualRatio: actual.ratio,
        actualPlace: actual.place,
        prediction: prediction,
      );
      if (sample == null) {
        continue;
      }
      _accumulate(sample, groupStats);
      _accumulate(sample, overallStats);
    }
  }

  /// Look up the wrapped [ShooterRating] for a given [MatchEntry], trying
  /// every member number known for the shooter.
  ShooterRating? _lookupRating(
    DbRatingProject project,
    RatingGroup group,
    MatchEntry shooter,
  ) {
    final memberNumbers = <String>{
      ...shooter.knownMemberNumbers,
      if (shooter.memberNumber.isNotEmpty) shooter.memberNumber,
      ...shooter.allPossibleMemberNumbers,
    };
    DbShooterRating? dbRating;
    for (final number in memberNumbers) {
      dbRating = project.lookupRatingSync(group, number);
      if (dbRating != null) {
        break;
      }
    }
    if (dbRating == null) {
      return null;
    }
    return project.wrapDbRatingSync(dbRating);
  }

  Future<DbShootingMatch?> _resolveMatch(_BacktestMatch m) async {
    if (m.sourceIds.isNotEmpty) {
      final byId = await db.getMatchByAnySourceId(m.sourceIds);
      if (byId != null) {
        return byId;
      }
    }
    if (m.exactName != null && m.exactName!.isNotEmpty) {
      final byName = await db.getMatchesByExactNames([m.exactName!]);
      if (byName.isNotEmpty) {
        return byName.first;
      }
    }
    return null;
  }

  _Sample? _sampleFromPrediction({
    required _Mode mode,
    required String algorithm,
    required String projectName,
    required String groupName,
    required ShootingMatch match,
    required double actualRatio,
    required int actualPlace,
    required AlgorithmPrediction prediction,
  }) {
    double mean;
    double oneSigma;
    if (prediction.isLogNormal) {
      // mean is the median ratio; oneSigma is the geometric SD.
      mean = prediction.displayCenter;
      oneSigma = prediction.oneSigma;
      if (mean <= 0 || oneSigma <= 1.0 || actualRatio <= 0) {
        // Degenerate / invalid — log-normal needs σ_log = ln(GSD) > 0
        // and a strictly positive observation.
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

    return _Sample(
      mode: mode,
      algorithm: algorithm,
      projectName: projectName,
      groupName: groupName,
      matchName: match.name,
      matchDate: match.date,
      actualRatio: actualRatio,
      actualPlace: actualPlace,
      mean: mean,
      oneSigma: oneSigma,
      predictedPlace: prediction.medianPlace,
      isLogNormal: prediction.isLogNormal,
    );
  }

  void _accumulate(_Sample s, _Stats stats) {
    final signedError = s.actualRatio - s.mean;
    final mae = signedError.abs();
    final absActual = s.actualRatio.abs();
    final mape = absActual < 1e-9 ? mae : mae / absActual;
    final mpe = absActual < 1e-9 ? signedError : signedError / absActual;
    final rankMae = (s.actualPlace - s.predictedPlace).abs().toDouble();

    double crps;
    bool within1;
    bool within2;
    // For the arithmetic-mean-centered MPE, the forecast center is the
    // expected value of the predictive distribution. For a log-normal that's
    // `median * exp(σ_log² / 2)`; for a normal it's just the mean.
    double arithCenter;
    if (s.isLogNormal) {
      final muLog = log(s.mean);
      final sigmaLog = log(s.oneSigma);
      crps = _logNormalCrps(muLog, sigmaLog, s.actualRatio);
      // 1σ band: [median / GSD, median * GSD]; 2σ: [median / GSD², median * GSD²]
      final low1 = s.mean / s.oneSigma;
      final high1 = s.mean * s.oneSigma;
      final low2 = s.mean / (s.oneSigma * s.oneSigma);
      final high2 = s.mean * (s.oneSigma * s.oneSigma);
      within1 = s.actualRatio >= low1 && s.actualRatio <= high1;
      within2 = s.actualRatio >= low2 && s.actualRatio <= high2;
      arithCenter = s.mean * exp((sigmaLog * sigmaLog) / 2);
    }
    else {
      crps = _normalCrps(s.mean, s.oneSigma, s.actualRatio);
      within1 = (s.actualRatio - s.mean).abs() <= s.oneSigma;
      within2 = (s.actualRatio - s.mean).abs() <= 2 * s.oneSigma;
      arithCenter = s.mean;
    }

    final signedErrorArith = s.actualRatio - arithCenter;
    final mpeArith = absActual < 1e-9
        ? signedErrorArith
        : signedErrorArith / absActual;

    stats.add(
      mape: mape,
      mpe: mpe,
      mpeArith: mpeArith,
      mae: mae,
      crps: crps,
      rankMae: rankMae,
      within1: within1,
      within2: within2,
    );
  }

  /// Closed-form CRPS for a normal forecast (Gneiting & Raftery 2007).
  ///
  /// CRPS(N(μ,σ), x) = σ * [z*(2Φ(z) - 1) + 2φ(z) - 1/√π]
  double _normalCrps(double mu, double sigma, double x) {
    if (sigma <= 0) {
      return (x - mu).abs();
    }
    final z = (x - mu) / sigma;
    final phi = Normal.cdf(z);
    final pdf = Normal.pdf(z);
    return sigma * (z * (2 * phi - 1) + 2 * pdf - 1 / sqrt(pi));
  }

  /// Closed-form CRPS for a log-normal forecast (Baran & Lerch 2015).
  ///
  /// For Y ~ Lognormal(μ, σ²) and observation y > 0:
  ///   CRPS(LN(μ,σ²), y) =
  ///     y * (2Φ(ω) - 1)
  ///     - 2 * exp(μ + σ²/2) * [Φ(ω - σ) + Φ(σ/√2) - 1]
  /// where ω = (ln y - μ) / σ.
  double _logNormalCrps(double muLog, double sigmaLog, double y) {
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

  void _printResults(
    Console console,
    List<(_Mode, String)> perGroupOrder,
    Map<(_Mode, String), _Stats> perGroup,
    Map<(_Mode, String), _Stats> overall,
  ) {
    for (final mode in _Mode.values) {
      console.print("");
      console.print("=== Per (algorithm, project, group) — mode=${mode.label} ===");
      for (final key in perGroupOrder) {
        if (key.$1 != mode) {
          continue;
        }
        final s = perGroup[key]!;
        if (s.n == 0) {
          console.print("${key.$2}: no samples");
          continue;
        }
        console.print(
          "${key.$2}  n=${s.n}  "
          "MAPE=${(s.mape * 100).toStringAsFixed(2)}%  "
          "MPE=${_fmtSignedPct(s.mpe)}  "
          "MAE=${s.mae.toStringAsFixed(4)}  "
          "CRPS=${s.crps.toStringAsFixed(4)}  "
          "RankMAE=${s.rankMae.toStringAsFixed(2)}  "
          "1σ=${(s.coverage1 * 100).toStringAsFixed(1)}%  "
          "2σ=${(s.coverage2 * 100).toStringAsFixed(1)}%",
        );
      }
    }

    final algoOrder = _projectsToTest.values.toList();
    for (final mode in _Mode.values) {
      console.print("");
      console.print("=== Per algorithm (overall) — mode=${mode.label} ===");
      for (final algo in algoOrder) {
        final s = overall[(mode, algo)];
        if (s == null || s.n == 0) {
          console.print("$algo: no samples");
          continue;
        }
        console.print(
          "$algo  n=${s.n}  "
          "MAPE=${(s.mape * 100).toStringAsFixed(2)}%  "
          "MPE=${_fmtSignedPct(s.mpe)}  "
          "MPE(arith)=${_fmtSignedPct(s.mpeArith)}  "
          "MAE=${s.mae.toStringAsFixed(4)}  "
          "CRPS=${s.crps.toStringAsFixed(4)}  "
          "RankMAE=${s.rankMae.toStringAsFixed(2)} places  "
          "1σ coverage=${(s.coverage1 * 100).toStringAsFixed(1)}% "
          "(ideal ~68.3%)  "
          "2σ coverage=${(s.coverage2 * 100).toStringAsFixed(1)}% "
          "(ideal ~95.4%)",
        );
      }
    }

    _log.i("Backtest complete");
  }

  /// Formats a signed fractional error (e.g. 0.0123) as a percentage with
  /// explicit sign, e.g. "+1.23%" or "-0.47%".
  String _fmtSignedPct(double v) {
    if (v.isNaN) {
      return "NaN";
    }
    final pct = v * 100;
    final sign = pct >= 0 ? "+" : "";
    return "$sign${pct.toStringAsFixed(2)}%";
  }
}
