/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// For each rating group in a project, takes the top [kTopShootersPerGroup] shooters
/// by current rating and summarizes **within-shooter** variation of match finish
/// ratios over their recorded history (mean, sample SD, min/max, date span).
///
/// Finish ratios come from each match's stored [DbRatingEvent.matchScore] — one
/// value per distinct [matchId], preferring match-level events (`stageNumber == -1`)
/// when present.
///
/// ## Eligibility vs stats window
///
/// - [kMinTotalDistinctMatches]: shooter must have at least this many distinct
///   matches (full history length). Example: `11` with [kMostRecentForStats] `5`
///   means "more than 10 lifetime matches, but summarize spread on the latest 5"
///   (steady-state / recent stability).
/// - [kMostRecentForStats]: if `> 0`, mean/sd/min/max use only the **most recent**
///   N matches (chronologically). If `0`, use the full history (subject to minimums).

import "dart:io";
import "dart:math";

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart";

import "base.dart";

/// Edit if your LLR project uses a different display name in the DB.
const String kDefaultLlrProjectName = "L2s Main LLR";

const int kTopShootersPerGroup = 100;

/// Minimum distinct matches in **full history** required to include a shooter.
/// Example for "more than 10 lifetime matches": set to `11`.
const int kMinTotalDistinctMatches = 11;

/// Minimum distinct matches in the **statistics window** (after applying
/// [kMostRecentForStats]) required to report sample SD (must be >= 2).
const int kMinMatchesForSpread = 2;

/// If `> 0`, mean/sd/min/max (and printed date range) use only the most recent
/// N matches by date. If `0`, use entire qualified history.
/// Pair with [kMinTotalDistinctMatches] e.g. `11` and `5` for "stable recent 5".
const int kMostRecentForStats = 5;

class TopRatedFinishSpreadCommand extends DbOneoffCommand {
  TopRatedFinishSpreadCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "TRS";

  @override
  final String title = "Top-Rated Finish Ratio Spread (LLR)";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _run(db, console, projectName: kDefaultLlrProjectName);
  }
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }

  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final recentNote = kMostRecentForStats > 0
      ? "; stats window = most recent $kMostRecentForStats matches"
      : "; stats window = full history";
  final totalNote =
      kMinTotalDistinctMatches > kMinMatchesForSpread
          ? "; require ≥$kMinTotalDistinctMatches distinct matches total"
          : "";

  console.print(
    "Project: $projectName — top $kTopShootersPerGroup per group by rating; "
    "spread = sample SD of [matchScore.ratio]$recentNote$totalNote.",
  );
  console.print("");

  final buf = StringBuffer()
    ..writeln(
      "group,rank,member_number,name,rating,n_total,n_used,ratio_mean,ratio_sd,ratio_min,ratio_max,window_first_date,window_last_date",
    );

  final allSds = <double>[];
  var totalRows = 0;

  for (final group in project.groups) {
    final ratingsRes = await project.getRatings(group);
    if (ratingsRes.isErr()) {
      console.print("${group.name}: error loading ratings: ${ratingsRes.unwrapErr()}");
      continue;
    }

    final dbRatings = ratingsRes.unwrap()
      .sorted((a, b) => b.rating.compareTo(a.rating))
      .take(kTopShootersPerGroup)
      .toList();

    if (dbRatings.isEmpty) {
      console.print("${group.name}: no shooters.");
      continue;
    }

    console.print("=== ${group.name} (${dbRatings.length} shooters) ===");

    for (var i = 0; i < dbRatings.length; i++) {
      final r = dbRatings[i];
      final timeline = _matchFinishTimeline(r, db);
      if (timeline.length < kMinTotalDistinctMatches) {
        continue;
      }

      var window = timeline;
      if (kMostRecentForStats > 0 && timeline.length > kMostRecentForStats) {
        window = timeline.sublist(timeline.length - kMostRecentForStats);
      }

      final ratios = window.map((e) => e.ratio).where((r) => r >= 0.6).toList();
      if (ratios.length < kMinMatchesForSpread) {
        continue;
      }

      final desc = _describe(ratios);
      final dateLo = window.first.date.toIso8601String().split("T").first;
      final dateHi = window.last.date.toIso8601String().split("T").first;
      final dateRange = "$dateLo → $dateHi";
      final nTotal = timeline.length;
      final nUsed = ratios.length;

      totalRows++;
      if (desc.sampleSd.isFinite) {
        allSds.add(desc.sampleSd);
      }

      final rank = i + 1;
      final nameEsc = r.name.replaceAll(",", " ");
      final nLabel =
          (kMostRecentForStats > 0 && nUsed < nTotal) ? "$nUsed/$nTotal" : "$nUsed";
      console.print(
        "  #$rank  ${r.memberNumber.padRight(12)}  "
        "rating=${r.rating.toStringAsFixed(4)}  "
        "n=${nLabel.padRight(7)}  "
        "mean=${desc.mean.toStringAsFixed(5)}  "
        "sd=${desc.sampleSd.toStringAsFixed(5)}  "
        "min=${desc.min.toStringAsFixed(5)}  "
        "max=${desc.max.toStringAsFixed(5)}  "
        "$dateRange",
      );

      buf.writeln(
        "${group.name},$rank,${r.memberNumber},$nameEsc,${r.rating},$nTotal,$nUsed,"
        "${desc.mean},${desc.sampleSd},${desc.min},${desc.max},"
        "$dateLo,$dateHi",
      );
    }
    console.print("");
  }

  if (allSds.isNotEmpty) {
    final meanSd =
        allSds.fold<double>(0.0, (a, b) => a + b) / allSds.length;
    console.print(
      "Across reported shooters (unweighted): mean(sample SD) = ${meanSd.toStringAsFixed(5)} "
      "(${allSds.length} values).",
    );
  }
  console.print("Rows written: $totalRows");

  final out = File("/tmp/top_rated_finish_ratio_spreads.csv");
  out.writeAsStringSync(buf.toString());
  console.print("Wrote ${out.path}");
}

/// One finish ratio per distinct match (chronological), preferring match-level events.
List<({DateTime date, double ratio})> _matchFinishTimeline(
  DbShooterRating rating,
  AnalystDatabase db,
) {
  final events = db.getRatingEventsForSync(rating, order: Order.ascending);
  if (events.isEmpty) {
    return [];
  }

  final byMatch = <String, List<DbRatingEvent>>{};
  for (final e in events) {
    byMatch.putIfAbsent(e.matchId, () => []).add(e);
  }

  final rows = <({DateTime date, double ratio})>[];
  for (final e in byMatch.entries) {
    final rep = _pickMatchRepresentative(e.value);
    rows.add((date: rep.date, ratio: rep.matchScore.ratio));
  }
  rows.sort((a, b) => a.date.compareTo(b.date));
  return rows;
}

DbRatingEvent _pickMatchRepresentative(List<DbRatingEvent> sameMatch) {
  final matchLevel =
      sameMatch.firstWhereOrNull((e) => e.stageNumber == -1);
  if (matchLevel != null) {
    return matchLevel;
  }
  sameMatch.sort((a, b) => a.date.compareTo(b.date));
  return sameMatch.first;
}

class _Desc {
  _Desc({
    required this.n,
    required this.mean,
    required this.sampleSd,
    required this.min,
    required this.max,
  });

  final int n;
  final double mean;
  final double sampleSd;
  final double min;
  final double max;
}

_Desc _describe(List<double> xs) {
  final n = xs.length;
  if (n == 0) {
    return _Desc(
      n: 0,
      mean: double.nan,
      sampleSd: double.nan,
      min: double.nan,
      max: double.nan,
    );
  }

  var sum = 0.0;
  var minV = xs.first;
  var maxV = xs.first;
  for (final x in xs) {
    sum += x;
    if (x < minV) {
      minV = x;
    }
    if (x > maxV) {
      maxV = x;
    }
  }
  final mean = sum / n;

  if (n < 2) {
    return _Desc(n: n, mean: mean, sampleSd: double.nan, min: minV, max: maxV);
  }

  var sq = 0.0;
  for (final x in xs) {
    final d = x - mean;
    sq += d * d;
  }
  final sd = sqrt(sq / (n - 1));
  return _Desc(n: n, mean: mean, sampleSd: sd, min: minV, max: maxV);
}
