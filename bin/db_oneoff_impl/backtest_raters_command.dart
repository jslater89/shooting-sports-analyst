// _BacktestMatch's named constructor parameters are unused while the
// _matches list below is empty; users of this command are expected to fill
// the list with real source IDs and/or exact names.
// ignore_for_file: unused_element_parameter

import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/math/ratio_forecast_stats.dart";
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

/// Quintile bucket computed from `place / fieldSize` within the scored field.
/// Applied to two different place axes:
///
/// - Actual finish place: diagnoses whether predictive bias concentrates in
///   a particular region of the realized field.
/// - Predicted finish place (driven by rating): diagnoses whether bias
///   concentrates in a particular region of the rating-ordered field. This
///   is closer to the "noise-heavy lower ratings" question and avoids the
///   conditional-on-outcome bias you get when bucketing by actual finish.
enum _Quintile {
  top20,
  q2,
  q3,
  q4,
  bottom20;

  String get label => switch (this) {
    _Quintile.top20 => "top 20%",
    _Quintile.q2 => "20-40%",
    _Quintile.q3 => "40-60%",
    _Quintile.q4 => "60-80%",
    _Quintile.bottom20 => "bottom 20%",
  };

  static _Quintile fromPlace(int place, int fieldSize) {
    if (fieldSize <= 0) {
      return _Quintile.top20;
    }
    final p = place / fieldSize;
    if (p <= 0.20) {
      return _Quintile.top20;
    }
    if (p <= 0.40) {
      return _Quintile.q2;
    }
    if (p <= 0.60) {
      return _Quintile.q3;
    }
    if (p <= 0.80) {
      return _Quintile.q4;
    }
    return _Quintile.bottom20;
  }
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

  /// Total number of scored competitors in the reference field for this
  /// sample. Used to compute finish percentiles for bucketing.
  final int fieldSize;

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
    required this.fieldSize,
    required this.mean,
    required this.oneSigma,
    required this.predictedPlace,
    required this.isLogNormal,
  });
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
    _BacktestMatch(exactName: "2025 Go Fast Don't Suck Maryland State USPSA Championship"),
    _BacktestMatch(exactName: "2025 GLOCK Area 6 Championship"),
    _BacktestMatch(exactName: "2025 Gatorz Missouri Fall Classic"),
    _BacktestMatch(exactName: "The 2025 CZ Free State Championship Presented by Vortex"),
    _BacktestMatch(exactName: "2025 Cheely Custom Gunworks Michigan Sectional Presented By S3 Range Carts"),
    _BacktestMatch(exactName: "2025 USPSA Arkansas Section Championship"),
    _BacktestMatch(exactName: "2025 Vortex Optics Illinois Sectional"),
    _BacktestMatch(exactName: "2025 GP Arms USPSA TN Section Championship"),
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
    final Map<(_Mode, String), RatioForecastStatsAccumulator> overall = {};
    // (mode, algorithm, project, group) -> stats
    final Map<(_Mode, String), RatioForecastStatsAccumulator> perGroup = {};
    // Ordered key for printing.
    final List<(_Mode, String)> perGroupOrder = [];
    // (mode, algorithm, actual finish quintile) -> stats. Answers "is the
    // bias concentrated in a particular region of the realized field?"
    final Map<(_Mode, String, _Quintile), RatioForecastStatsAccumulator> overallByFinishQuintile = {};
    // (mode, algorithm, predicted finish quintile) -> stats. Answers "is the
    // bias concentrated in a particular region of the rating-ordered field?"
    // Predicted place is driven primarily by rating, so this is effectively
    // a rating-percentile bucketing that avoids the conditional-on-outcome
    // bias you get from bucketing by actual finish.
    final Map<(_Mode, String, _Quintile), RatioForecastStatsAccumulator> overallByRatingQuintile = {};

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
            return RatioForecastStatsAccumulator();
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
            overallByFinishQuintile: overallByFinishQuintile,
            overallByRatingQuintile: overallByRatingQuintile,
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
                overallByFinishQuintile: overallByFinishQuintile,
                overallByRatingQuintile: overallByRatingQuintile,
              );
            }
          }
        }
      }
    }

    _printResults(
      console,
      perGroupOrder,
      perGroup,
      overall,
      overallByFinishQuintile,
      overallByRatingQuintile,
    );
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
    required Map<(_Mode, String), RatioForecastStatsAccumulator> perGroup,
    required Map<(_Mode, String), RatioForecastStatsAccumulator> overall,
    required Map<(_Mode, String, _Quintile), RatioForecastStatsAccumulator> overallByFinishQuintile,
    required Map<(_Mode, String, _Quintile), RatioForecastStatsAccumulator> overallByRatingQuintile,
  }) {
    final groupKey = "$algorithmLabel | $projectName | ${group.name}";
    final groupStats = perGroup.putIfAbsent((mode, groupKey), () {
      return RatioForecastStatsAccumulator();
    });
    final overallStats = overall.putIfAbsent(
      (mode, algorithmLabel),
      () => RatioForecastStatsAccumulator(),
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

    // Field size for bucketing is the number of scored competitors in this
    // pipeline run (full field for mode=all, rated subset for mode=ratedOnly).
    final fieldSize = scores.length;

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
        fieldSize: fieldSize,
        prediction: prediction,
      );
      if (sample == null) {
        continue;
      }
      _accumulate(sample, groupStats);
      _accumulate(sample, overallStats);
      final finishBucket = _Quintile.fromPlace(
        sample.actualPlace,
        sample.fieldSize,
      );
      final finishBucketStats = overallByFinishQuintile.putIfAbsent(
        (mode, algorithmLabel, finishBucket),
        () => RatioForecastStatsAccumulator(),
      );
      _accumulate(sample, finishBucketStats);
      final ratingBucket = _Quintile.fromPlace(
        sample.predictedPlace,
        sample.fieldSize,
      );
      final ratingBucketStats = overallByRatingQuintile.putIfAbsent(
        (mode, algorithmLabel, ratingBucket),
        () => RatioForecastStatsAccumulator(),
      );
      _accumulate(sample, ratingBucketStats);
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
    required int fieldSize,
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
      fieldSize: fieldSize,
      mean: mean,
      oneSigma: oneSigma,
      predictedPlace: prediction.medianPlace,
      isLogNormal: prediction.isLogNormal,
    );
  }

  void _accumulate(_Sample s, RatioForecastStatsAccumulator stats) {
    stats.add(
      ratioForecastMetrics(
        actualRatio: s.actualRatio,
        actualPlace: s.actualPlace,
        predictedPlace: s.predictedPlace,
        isLogNormal: s.isLogNormal,
        mean: s.mean,
        oneSigma: s.oneSigma,
      ),
    );
  }

  void _printResults(
    Console console,
    List<(_Mode, String)> perGroupOrder,
    Map<(_Mode, String), RatioForecastStatsAccumulator> perGroup,
    Map<(_Mode, String), RatioForecastStatsAccumulator> overall,
    Map<(_Mode, String, _Quintile), RatioForecastStatsAccumulator> overallByFinishQuintile,
    Map<(_Mode, String, _Quintile), RatioForecastStatsAccumulator> overallByRatingQuintile,
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
          "MPE=${formatSignedForecastPercent(s.mpe)}  "
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
          "MPE=${formatSignedForecastPercent(s.mpe)}  "
          "MPE(arith)=${formatSignedForecastPercent(s.mpeArith)}  "
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

    // Bucketed by actual finish percentile: shows where error/bias lands in
    // the realized field. Note that bucketing by an outcome variable (finish
    // ratio) induces a conditional-on-outcome bias slope even for a perfectly
    // calibrated predictor, so this view should be read alongside the
    // rating-bucketed view below.
    _printBucketedSection(
      console: console,
      overallByBucket: overallByFinishQuintile,
      sectionTitle: "bucketed by actual finish",
      algoOrder: algoOrder,
    );

    // Bucketed by predicted finish percentile (driven by rating): shows
    // where error/bias lands in the rating-ordered field. Bucketing by an
    // input rather than an outcome removes the conditional-on-outcome bias,
    // so large remaining slope here is more likely to be true miscalibration
    // (e.g. noise-heavy lower ratings).
    _printBucketedSection(
      console: console,
      overallByBucket: overallByRatingQuintile,
      sectionTitle: "bucketed by predicted rank (rating)",
      algoOrder: algoOrder,
    );

    _log.i("Backtest complete");
  }

  /// Shared printer for the two bucketed sections (by actual finish and by
  /// predicted rank). Prints one block per [_Mode].
  void _printBucketedSection({
    required Console console,
    required Map<(_Mode, String, _Quintile), RatioForecastStatsAccumulator> overallByBucket,
    required String sectionTitle,
    required List<String> algoOrder,
  }) {
    for (final mode in _Mode.values) {
      console.print("");
      console.print(
        "=== Per algorithm, $sectionTitle — mode=${mode.label} ===",
      );
      for (final algo in algoOrder) {
        final anyPresent = _Quintile.values.any(
          (b) => (overallByBucket[(mode, algo, b)]?.n ?? 0) > 0,
        );
        if (!anyPresent) {
          console.print("$algo: no samples");
          continue;
        }
        console.print("$algo:");
        for (final bucket in _Quintile.values) {
          final s = overallByBucket[(mode, algo, bucket)];
          if (s == null || s.n == 0) {
            console.print("  ${bucket.label.padRight(11)}  n=0");
            continue;
          }
          console.print(
            "  ${bucket.label.padRight(11)}  "
            "n=${s.n.toString().padLeft(5)}  "
            "MPE=${formatSignedForecastPercent(s.mpe).padLeft(8)}  "
            "MPE(arith)=${formatSignedForecastPercent(s.mpeArith).padLeft(8)}  "
            "MAPE=${(s.mape * 100).toStringAsFixed(2).padLeft(6)}%  "
            "MAE=${s.mae.toStringAsFixed(4)}  "
            "CRPS=${s.crps.toStringAsFixed(4)}  "
            "RankMAE=${s.rankMae.toStringAsFixed(2).padLeft(5)}  "
            "1σ=${(s.coverage1 * 100).toStringAsFixed(1).padLeft(5)}%  "
            "2σ=${(s.coverage2 * 100).toStringAsFixed(1).padLeft(5)}%",
          );
        }
      }
    }
  }
}
