/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// For 75th-percentile-or-better shooters in each single-division group,
/// find **match weeks** (Monday–Sunday) with two or more distinct rated
/// matches in that group, and test whether the later match is worse for
/// finish ratio / rating change than the earlier match and than their
/// isolated (single-match-week) appearances.
///
/// Typical pattern: early/staff match Mon–Thu at one major, then Fri–Sun
/// at the other. One pair per week = earliest vs latest by listed start date.
///
/// Launch: dart run bin/db_oneoffs.dart WKD [project] [percentile]
/// Example: WKD "L2s Main LLR" 75

import "dart:math";

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart";
import "package:shooting_sports_analyst/data/math/distribution_tools.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const double kDefaultPercentile = 75.0;
const int kMaxListedPairs = 20;
const List<String> kWeekdays = [
  "Mon",
  "Tue",
  "Wed",
  "Thu",
  "Fri",
  "Sat",
  "Sun",
];

class WeekendDoubleRatingsCommand extends DbOneoffCommand {
  WeekendDoubleRatingsCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "WKD";

  @override
  final String title = "Match Week Doubles";

  @override
  String? get description =>
      "Top-quartile shooters: two majors in the same Mon–Sun week — "
      "is the later match worse for finish ratio and rating change?";

  @override
  List<MenuArgument> get arguments => [
        StringMenuArgument(
          label: "Project name",
          required: false,
          defaultValue: kDefaultLlrProjectName,
          description: "Rating project (LLR recommended).",
        ),
        StringMenuArgument(
          label: "Percentile",
          required: false,
          defaultValue: kDefaultPercentile.toString(),
          description:
              "Keep shooters at or above this current-rating percentile "
              "(75 = top 25%).",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final projectName = arguments
            .firstWhereOrNull((a) => a.argument.label == "Project name")
            ?.getAs<String>()
            .trim() ??
        kDefaultLlrProjectName;
    final percentileRaw = arguments
            .firstWhereOrNull((a) => a.argument.label == "Percentile")
            ?.getAs<String>()
            .trim() ??
        "";
    final percentile = double.tryParse(percentileRaw.isEmpty ? "$kDefaultPercentile" : percentileRaw);
    if (percentile == null || percentile < 50 || percentile >= 100) {
      console.print("Percentile must be in [50, 100); got \"$percentileRaw\".");
      return;
    }

    await _run(
      db,
      console,
      projectName: projectName.isEmpty ? kDefaultLlrProjectName : projectName,
      percentile: percentile,
    );
  }
}

class _MatchAppearance {
  _MatchAppearance({
    required this.matchId,
    required this.date,
    required this.ratio,
    required this.ratingChange,
    required this.matchName,
  });

  final String matchId;
  final DateTime date;
  final double ratio;
  final double ratingChange;
  final String matchName;

  DateTime get day => DateTime(date.year, date.month, date.day);
}

class _Cluster {
  _Cluster(this.appearances);
  final List<_MatchAppearance> appearances;
  int get size => appearances.length;
  bool get isDouble => size == 2;
  bool get isMulti => size >= 2;
}

class _Pair {
  _Pair({
    required this.groupName,
    required this.memberNumber,
    required this.shooterName,
    required this.first,
    required this.second,
    this.isolatedRatioMean,
    this.isolatedRatingMean,
    required this.weekSize,
  });

  final String groupName;
  final String memberNumber;
  final String shooterName;
  final _MatchAppearance first;
  final _MatchAppearance second;
  final double? isolatedRatioMean;
  final double? isolatedRatingMean;
  final int weekSize;

  int get gapDays => second.day.difference(first.day).inDays;
  bool get sameDay => gapDays == 0;
  double get ratioDelta => second.ratio - first.ratio;
  double get ratingDelta => second.ratingChange - first.ratingChange;

  /// Early/staff (Mon–Thu) then main match (Fri–Sun).
  bool get isEarlyThenWeekend {
    final f = first.date.weekday;
    final s = second.date.weekday;
    return f >= DateTime.monday &&
        f <= DateTime.thursday &&
        s >= DateTime.friday &&
        s <= DateTime.sunday;
  }
}

class _GroupStats {
  _GroupStats(this.group);

  final RatingGroup group;
  int rated = 0;
  int elite = 0;
  int eliteWithDouble = 0;
  int isolatedMatches = 0;
  int doubleClusters = 0;
  int triplePlusClusters = 0;
  final List<_Pair> pairs = [];
  final List<double> isolatedRatios = [];
  final List<double> isolatedRatingChanges = [];
  final List<double> withinShooterIsolatedMinusDay2Ratio = [];
  final List<double> withinShooterIsolatedMinusDay2Rating = [];
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required double percentile,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }

  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final groups = project.groups
      .where((g) => g.divisionNames.length == 1)
      .sorted((a, b) => a.sortOrder.compareTo(b.sortOrder))
      .toList();
  if (groups.isEmpty) {
    console.print("No single-division groups in $projectName.");
    return;
  }

  final matchNameById = <String, String>{};
  for (final ptr in project.matchPointers) {
    for (final id in ptr.sourceIds) {
      matchNameById[id] = ptr.name;
    }
  }

  final buf = StringBuffer()
    ..writeln("=== Match Week Doubles ===")
    ..writeln("Project: $projectName")
    ..writeln("Algorithm: ${project.settings.algorithm.runtimeType}")
    ..writeln("Groups: single-division only")
    ..writeln(
      "Cohort: current rating >= ${percentile.toStringAsFixed(0)}th percentile "
      "of the group (top ${(100 - percentile).toStringAsFixed(0)}%)",
    )
    ..writeln(
      "Match week: Monday–Sunday. Two+ distinct same-group matches in that "
      "window = a double. Pair = earliest vs latest by listed start date "
      "(early/staff vs later major).",
    )
    ..writeln(
      "Identity: DbShooterRating rows within a group (no cross-division merge)",
    )
    ..writeln(
      "Finish: matchScore.ratio from match-level event (stageNumber == -1) when present",
    )
    ..writeln("Rating change: sum of event.ratingChange for that matchId")
    ..writeln(
      "Note: two guns at one major share a matchId and do not count here. "
      "Open at one match + Limited at the other is also excluded (different groups).",
    )
    ..writeln("");

  final groupStats = <_GroupStats>[];
  for (final group in groups) {
    final ratingsRes = project.getRatingsSync(group);
    if (ratingsRes.isErr()) {
      buf.writeln("${group.uiLabel}: failed to load ratings.");
      continue;
    }
    groupStats.add(_GroupStats(group)..rated = ratingsRes.unwrap().length);
  }

  final eliteByGroup = <RatingGroup, List<DbShooterRating>>{};
  var eliteTotal = 0;
  for (final stats in groupStats) {
    final ratingsRes = project.getRatingsSync(stats.group);
    final ratings = ratingsRes.unwrap();
    final elite = _eliteByPercentile(ratings, percentile);
    stats.elite = elite.length;
    eliteTotal += elite.length;
    eliteByGroup[stats.group] = elite;
  }

  if (eliteTotal == 0) {
    buf.writeln("No elite shooters found.");
    console.print(buf.toString());
    return;
  }

  final bar = LabeledProgressBar(
    maxValue: eliteTotal,
    initialLabel: "Match week doubles...",
  );

  for (final stats in groupStats) {
    final elite = eliteByGroup[stats.group] ?? const <DbShooterRating>[];
    for (final rating in elite) {
      bar.tick();
      final appearances = _matchAppearances(db, rating, matchNameById);
      if (appearances.isEmpty) {
        continue;
      }
      final clusters = _clusterByMatchWeek(appearances);
      final isolated = <_MatchAppearance>[];
      final multi = <_Cluster>[];
      for (final cluster in clusters) {
        if (!cluster.isMulti) {
          isolated.addAll(cluster.appearances);
        }
        else {
          multi.add(cluster);
        }
      }
      if (multi.isEmpty) {
        stats.isolatedMatches += isolated.length;
        for (final a in isolated) {
          stats.isolatedRatios.add(a.ratio);
          stats.isolatedRatingChanges.add(a.ratingChange);
        }
        continue;
      }

      stats.eliteWithDouble++;
      stats.isolatedMatches += isolated.length;
      for (final a in isolated) {
        stats.isolatedRatios.add(a.ratio);
        stats.isolatedRatingChanges.add(a.ratingChange);
      }

      final isoRatioMean = isolated.isEmpty ? null : isolated.map((a) => a.ratio).average;
      final isoRatingMean =
          isolated.isEmpty ? null : isolated.map((a) => a.ratingChange).average;

      for (final cluster in multi) {
        if (cluster.isDouble) {
          stats.doubleClusters++;
        }
        else {
          stats.triplePlusClusters++;
        }
        final ordered = cluster.appearances;
        final pair = _Pair(
          groupName: stats.group.uiLabel,
          memberNumber: rating.memberNumber,
          shooterName: rating.name,
          first: ordered.first,
          second: ordered.last,
          isolatedRatioMean: isoRatioMean,
          isolatedRatingMean: isoRatingMean,
          weekSize: ordered.length,
        );
        stats.pairs.add(pair);
        if (isoRatioMean != null) {
          stats.withinShooterIsolatedMinusDay2Ratio.add(isoRatioMean - pair.second.ratio);
          stats.withinShooterIsolatedMinusDay2Rating.add(isoRatingMean! - pair.second.ratingChange);
        }
      }
    }
  }
  bar.complete();

  final allPairs = groupStats.expand((s) => s.pairs).toList();
  final allIsoRatio = groupStats.expand((s) => s.isolatedRatios).toList();
  final allIsoRating = groupStats.expand((s) => s.isolatedRatingChanges).toList();
  final allWithinRatio = groupStats.expand((s) => s.withinShooterIsolatedMinusDay2Ratio).toList();
  final allWithinRating = groupStats.expand((s) => s.withinShooterIsolatedMinusDay2Rating).toList();

  buf.writeln("--- Sample ---");
  buf.writeln(
    "${"Division".padRight(18)}"
    "${"N".padLeft(6)}"
    "${"Elite".padLeft(7)}"
    "${"w/dbl".padLeft(7)}"
    "${"pairs".padLeft(7)}"
    "${"3+".padLeft(5)}"
    "${"isol.".padLeft(7)}",
  );
  buf.writeln("-" * 57);
  var sumRated = 0;
  var sumElite = 0;
  var sumWithDbl = 0;
  var sumPairs = 0;
  var sumTriple = 0;
  var sumIso = 0;
  for (final s in groupStats) {
    sumRated += s.rated;
    sumElite += s.elite;
    sumWithDbl += s.eliteWithDouble;
    sumPairs += s.pairs.length;
    sumTriple += s.triplePlusClusters;
    sumIso += s.isolatedMatches;
    buf.writeln(
      "${s.group.uiLabel.padRight(18)}"
      "${s.rated.toString().padLeft(6)}"
      "${s.elite.toString().padLeft(7)}"
      "${s.eliteWithDouble.toString().padLeft(7)}"
      "${s.pairs.length.toString().padLeft(7)}"
      "${s.triplePlusClusters.toString().padLeft(5)}"
      "${s.isolatedMatches.toString().padLeft(7)}",
    );
  }
  buf.writeln("-" * 57);
  buf.writeln(
    "${"All".padRight(18)}"
    "${sumRated.toString().padLeft(6)}"
    "${sumElite.toString().padLeft(7)}"
    "${sumWithDbl.toString().padLeft(7)}"
    "${sumPairs.toString().padLeft(7)}"
    "${sumTriple.toString().padLeft(5)}"
    "${sumIso.toString().padLeft(7)}",
  );
  buf.writeln("");
  buf.writeln(
    "Elite with ≥1 match-week double: ${_pct(sumWithDbl, sumElite)}",
  );
  buf.writeln("Match-week pairs (earliest vs latest in the week): $sumPairs");
  buf.writeln("Isolated (single-match-week) appearances among the elite cohort: $sumIso");
  buf.writeln("");

  buf.writeln("--- Pair calendar ---");
  if (allPairs.isEmpty) {
    buf.writeln("No match-week pairs.");
  }
  else {
    final gapCounts = <int, int>{};
    final dowCounts = <String, int>{};
    var sameDay = 0;
    var earlyThenWeekend = 0;
    var weekSize3 = 0;
    for (final p in allPairs) {
      gapCounts[p.gapDays] = (gapCounts[p.gapDays] ?? 0) + 1;
      if (p.sameDay) {
        sameDay++;
      }
      if (p.isEarlyThenWeekend) {
        earlyThenWeekend++;
      }
      if (p.weekSize >= 3) {
        weekSize3++;
      }
      final key =
          "${kWeekdays[p.first.date.weekday - 1]}→${kWeekdays[p.second.date.weekday - 1]}";
      dowCounts[key] = (dowCounts[key] ?? 0) + 1;
    }
    buf.writeln("Same-day pairs: ${_pct(sameDay, allPairs.length)}");
    buf.writeln(
      "Early/staff (Mon–Thu) then weekend (Fri–Sun): "
      "${_pct(earlyThenWeekend, allPairs.length)}",
    );
    buf.writeln("Weeks with 3+ matches (pair is first vs last): ${_pct(weekSize3, allPairs.length)}");
    buf.writeln("Gap days (listed start dates):");
    final gaps = gapCounts.keys.toList()..sort();
    for (final g in gaps) {
      buf.writeln("  $g day(s): ${_pct(gapCounts[g]!, allPairs.length)}");
    }
    buf.writeln("Weekday pattern (earliest → latest):");
    final dowKeys = dowCounts.keys.toList()
      ..sort((a, b) => dowCounts[b]!.compareTo(dowCounts[a]!));
    for (final k in dowKeys) {
      buf.writeln("  $k: ${_pct(dowCounts[k]!, allPairs.length)}");
    }
  }
  buf.writeln("");

  _writeEffectBlock(buf, title: "All Mon–Sun week doubles", pairs: allPairs);

  final earlyWeekendPairs = allPairs.where((p) => p.isEarlyThenWeekend).toList();
  _writeEffectBlock(
    buf,
    title: "Early/staff (Mon–Thu) then weekend (Fri–Sun)",
    pairs: earlyWeekendPairs,
  );

  buf.writeln("--- Later match vs isolated single-match weeks (unpaired, elite cohort) ---");
  final day2Ratios = allPairs.map((p) => p.second.ratio).toList();
  final day2Ratings = allPairs.map((p) => p.second.ratingChange).toList();
  final day1Ratios = allPairs.map((p) => p.first.ratio).toList();
  final day1Ratings = allPairs.map((p) => p.first.ratingChange).toList();
  _writeUnpairedSection(
    buf,
    label: "Finish ratio: isolated vs later match",
    a: allIsoRatio,
    b: day2Ratios,
    aName: "isolated",
    bName: "later",
    digits: 4,
  );
  _writeUnpairedSection(
    buf,
    label: "Finish ratio: isolated vs earlier match",
    a: allIsoRatio,
    b: day1Ratios,
    aName: "isolated",
    bName: "earlier",
    digits: 4,
  );
  _writeUnpairedSection(
    buf,
    label: "Rating change: isolated vs later match",
    a: allIsoRating,
    b: day2Ratings,
    aName: "isolated",
    bName: "later",
    digits: 5,
  );
  _writeUnpairedSection(
    buf,
    label: "Rating change: isolated vs earlier match",
    a: allIsoRating,
    b: day1Ratings,
    aName: "isolated",
    bName: "earlier",
    digits: 5,
  );
  buf.writeln("");

  buf.writeln(
    "--- Within-shooter: isolated mean minus that shooter's later match "
    "(positive = later match worse than their own single-match weeks) ---",
  );
  _writeOneSample(
    buf,
    label: "Finish ratio (all doubles)",
    values: allWithinRatio,
    digits: 4,
  );
  _writeOneSample(
    buf,
    label: "Rating change (all doubles)",
    values: allWithinRating,
    digits: 5,
  );
  _writeOneSample(
    buf,
    label: "Finish ratio (early→weekend subset)",
    values: earlyWeekendPairs
        .where((p) => p.isolatedRatioMean != null)
        .map((p) => p.isolatedRatioMean! - p.second.ratio)
        .toList(),
    digits: 4,
  );
  _writeOneSample(
    buf,
    label: "Rating change (early→weekend subset)",
    values: earlyWeekendPairs
        .where((p) => p.isolatedRatingMean != null)
        .map((p) => p.isolatedRatingMean! - p.second.ratingChange)
        .toList(),
    digits: 5,
  );
  buf.writeln("");

  buf.writeln("--- Frequent match pairs ---");
  if (allPairs.isEmpty) {
    buf.writeln("(none)");
  }
  else {
    final pairCounts = <String, int>{};
    for (final p in allPairs) {
      final a = p.first.matchName;
      final b = p.second.matchName;
      final key = a.compareTo(b) <= 0 ? "$a  +  $b" : "$b  +  $a";
      pairCounts[key] = (pairCounts[key] ?? 0) + 1;
    }
    final ranked = pairCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in ranked.take(kMaxListedPairs)) {
      buf.writeln("  ${e.value.toString().padLeft(4)}  ${e.key}");
    }
  }
  buf.writeln("");

  buf.writeln("--- Sufficiency ---");
  buf.writeln("All Mon–Sun week doubles:");
  buf.writeln(_sufficiencyVerdict(
    nPairs: allPairs.length,
    nEliteWithDouble: sumWithDbl,
    nElite: sumElite,
    ratioDeltas: allPairs.map((p) => p.ratioDelta).toList(),
    ratingDeltas: allPairs.map((p) => p.ratingDelta).toList(),
  ));
  buf.writeln("");
  buf.writeln("Early/staff then weekend subset:");
  buf.writeln(_sufficiencyVerdict(
    nPairs: earlyWeekendPairs.length,
    nEliteWithDouble: earlyWeekendPairs.map((p) => "${p.groupName}|${p.memberNumber}").toSet().length,
    nElite: sumElite,
    ratioDeltas: earlyWeekendPairs.map((p) => p.ratioDelta).toList(),
    ratingDeltas: earlyWeekendPairs.map((p) => p.ratingDelta).toList(),
  ));

  console.print(buf.toString());
}

List<DbShooterRating> _eliteByPercentile(
  List<DbShooterRating> ratings,
  double percentile,
) {
  if (ratings.isEmpty) {
    return [];
  }
  final sorted = [...ratings]..sort((a, b) => a.rating.compareTo(b.rating));
  final idx = ((sorted.length - 1) * (percentile / 100.0)).floor().clamp(0, sorted.length - 1);
  final threshold = sorted[idx].rating;
  return ratings.where((r) => r.rating >= threshold).toList();
}

List<_MatchAppearance> _matchAppearances(
  AnalystDatabase db,
  DbShooterRating rating,
  Map<String, String> matchNameById,
) {
  final events = db.getRatingEventsForSync(rating, order: Order.ascending);
  if (events.isEmpty) {
    return [];
  }
  final byMatch = <String, List<DbRatingEvent>>{};
  for (final e in events) {
    byMatch.putIfAbsent(e.matchId, () => []).add(e);
  }
  final rows = <_MatchAppearance>[];
  for (final entry in byMatch.entries) {
    final eventsForMatch = entry.value;
    final rep = _pickMatchRepresentative(eventsForMatch);
    var change = 0.0;
    for (final e in eventsForMatch) {
      change += e.ratingChange;
    }
    rows.add(_MatchAppearance(
      matchId: entry.key,
      date: rep.date,
      ratio: rep.matchScore.ratio,
      ratingChange: change,
      matchName: matchNameById[entry.key] ?? entry.key,
    ));
  }
  rows.sort((a, b) {
    final d = a.date.compareTo(b.date);
    if (d != 0) {
      return d;
    }
    return a.matchName.compareTo(b.matchName);
  });
  return rows;
}

DbRatingEvent _pickMatchRepresentative(List<DbRatingEvent> sameMatch) {
  final matchLevel = sameMatch.firstWhereOrNull((e) => e.stageNumber == -1);
  if (matchLevel != null) {
    return matchLevel;
  }
  sameMatch.sort((a, b) => a.date.compareTo(b.date));
  return sameMatch.first;
}

List<_Cluster> _clusterByMatchWeek(List<_MatchAppearance> appearances) {
  if (appearances.isEmpty) {
    return [];
  }
  final byWeek = <DateTime, List<_MatchAppearance>>{};
  for (final a in appearances) {
    final monday = _weekMonday(a.date);
    byWeek.putIfAbsent(monday, () => []).add(a);
  }
  final mondays = byWeek.keys.toList()..sort();
  return [
    for (final monday in mondays)
      _Cluster(
        (byWeek[monday]!
          ..sort((a, b) {
            final d = a.date.compareTo(b.date);
            if (d != 0) {
              return d;
            }
            return a.matchName.compareTo(b.matchName);
          })),
      ),
  ];
}

DateTime _weekMonday(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

void _writeEffectBlock(
  StringBuffer buf, {
  required String title,
  required List<_Pair> pairs,
}) {
  buf.writeln("--- Earliest vs latest in the week: $title ---");
  _writePairedSection(
    buf,
    label: "Finish ratio (later − earlier); negative = worse later match",
    deltas: pairs.map((p) => p.ratioDelta).toList(),
    first: pairs.map((p) => p.first.ratio).toList(),
    second: pairs.map((p) => p.second.ratio).toList(),
    digits: 4,
  );
  _writePairedSection(
    buf,
    label: "Rating change (later − earlier); negative = later match worse for rating",
    deltas: pairs.map((p) => p.ratingDelta).toList(),
    first: pairs.map((p) => p.first.ratingChange).toList(),
    second: pairs.map((p) => p.second.ratingChange).toList(),
    digits: 5,
  );
  buf.writeln("");
}

void _writePairedSection(
  StringBuffer buf, {
  required String label,
  required List<double> deltas,
  required List<double> first,
  required List<double> second,
  required int digits,
}) {
  buf.writeln(label);
  if (deltas.isEmpty) {
    buf.writeln("  (no pairs)");
    return;
  }
  final nWorse = deltas.where((d) => d < 0).length;
  final nBetter = deltas.where((d) => d > 0).length;
  buf.writeln("  Earlier: ${_describe(first, digits)}");
  buf.writeln("  Later:   ${_describe(second, digits)}");
  buf.writeln("  Delta:   ${_describe(deltas, digits)}");
  buf.writeln(
    "  Later worse: ${_pct(nWorse, deltas.length)}; "
    "better: ${_pct(nBetter, deltas.length)}",
  );
  final t = _oneSampleT(deltas);
  buf.writeln("  ${t.line}");
}

void _writeUnpairedSection(
  StringBuffer buf, {
  required String label,
  required List<double> a,
  required List<double> b,
  required String aName,
  required String bName,
  required int digits,
}) {
  buf.writeln(label);
  if (a.isEmpty || b.isEmpty) {
    buf.writeln("  (insufficient: $aName n=${a.length}, $bName n=${b.length})");
    return;
  }
  buf.writeln("  $aName: ${_describe(a, digits)}");
  buf.writeln("  $bName: ${_describe(b, digits)}");
  final w = _welchT(a, b);
  buf.writeln("  ${w.line}  (positive t => $aName > $bName)");
}

void _writeOneSample(
  StringBuffer buf, {
  required String label,
  required List<double> values,
  required int digits,
}) {
  buf.writeln(label);
  if (values.isEmpty) {
    buf.writeln("  (no shooters with both isolated match-weeks and a double)");
    return;
  }
  buf.writeln("  ${_describe(values, digits)}");
  buf.writeln("  ${_oneSampleT(values).line}");
}

String _describe(List<double> xs, int digits) {
  if (xs.isEmpty) {
    return "n=0";
  }
  final sorted = [...xs]..sort();
  final n = sorted.length;
  final mean = sorted.average;
  final sd = n >= 2 ? sorted.stdDev() : double.nan;
  final p50 = sorted[(n - 1) ~/ 2];
  final sdStr = sd.isFinite ? sd.toStringAsFixed(digits) : "n/a";
  return "n=$n mean=${mean.toStringAsFixed(digits)} "
      "sd=$sdStr median=${p50.toStringAsFixed(digits)}";
}

({double t, double p, String line}) _oneSampleT(List<double> values) {
  final n = values.length;
  if (n < 3) {
    return (t: double.nan, p: double.nan, line: "Paired/one-sample t: n<$n too small");
  }
  final mean = values.average;
  final sd = values.stdDev();
  if (sd == 0 || !sd.isFinite) {
    return (t: double.nan, p: double.nan, line: "Paired/one-sample t: sd=0");
  }
  final t = mean / (sd / sqrt(n));
  final p = _twoTailedNormalP(t);
  return (
    t: t,
    p: p,
    line:
        "One-sample t vs 0: t=${t.toStringAsFixed(3)}  "
        "p≈${_pStr(p)} (normal approx, n=$n)",
  );
}

({double t, double p, String line}) _welchT(List<double> a, List<double> b) {
  final n1 = a.length;
  final n2 = b.length;
  if (n1 < 3 || n2 < 3) {
    return (t: double.nan, p: double.nan, line: "Welch t: sample too small");
  }
  final m1 = a.average;
  final m2 = b.average;
  final v1 = a.stdDev() * a.stdDev();
  final v2 = b.stdDev() * b.stdDev();
  final se = sqrt(v1 / n1 + v2 / n2);
  if (se == 0 || !se.isFinite) {
    return (t: double.nan, p: double.nan, line: "Welch t: se=0");
  }
  final t = (m1 - m2) / se;
  final p = _twoTailedNormalP(t);
  return (
    t: t,
    p: p,
    line:
        "Welch t: t=${t.toStringAsFixed(3)}  p≈${_pStr(p)} "
        "(normal approx; n1=$n1 n2=$n2)",
  );
}

double _twoTailedNormalP(double t) {
  final absT = t.abs();
  final cdf = stdNormal.cdf(absT).toDouble();
  final p = 2 * (1.0 - cdf);
  if (p < 0) {
    return 0.0;
  }
  if (p > 1) {
    return 1.0;
  }
  return p;
}

String _pStr(double p) {
  if (!p.isFinite) {
    return "n/a";
  }
  if (p < 0.001) {
    return p.toStringAsExponential(2);
  }
  return p.toStringAsFixed(4);
}

String _pct(int numerator, int denominator) {
  if (denominator == 0) {
    return "n/a";
  }
  return "$numerator (${(100.0 * numerator / denominator).toStringAsFixed(1)}% of $denominator)";
}

String _sufficiencyVerdict({
  required int nPairs,
  required int nEliteWithDouble,
  required int nElite,
  required List<double> ratioDeltas,
  required List<double> ratingDeltas,
}) {
  if (nPairs < 20) {
    return "Not enough: $nPairs match-week pairs among $nEliteWithDouble / $nElite "
        "elite shooters. Need roughly 30+ pairs for a directional claim, 80+ "
        "for a stable one.";
  }

  final ratioT = _oneSampleT(ratioDeltas);
  final ratingT = _oneSampleT(ratingDeltas);
  final ratioMean = ratioDeltas.isEmpty ? 0.0 : ratioDeltas.average;
  final ratingMean = ratingDeltas.isEmpty ? 0.0 : ratingDeltas.average;

  final sampleNote = nPairs < 80
      ? "Sample is usable but modest ($nPairs pairs; $nEliteWithDouble elite shooters)."
      : "Sample is large enough for a directional claim ($nPairs pairs; $nEliteWithDouble elite shooters).";

  String effect(String name, double mean, ({double t, double p, String line}) test) {
    if (!test.p.isFinite) {
      return "$name: no test.";
    }
    if (test.p >= 0.10) {
      return "$name: no clear paired earlier→later shift (mean ${mean.toStringAsFixed(4)}, p≈${_pStr(test.p)}).";
    }
    final direction = mean < 0 ? "worse" : "better";
    return "$name: later match looks $direction (mean ${mean.toStringAsFixed(4)}, p≈${_pStr(test.p)}).";
  }

  return "$sampleNote "
      "${effect("Finish ratio", ratioMean, ratioT)} "
      "${effect("Rating change", ratingMean, ratingT)} "
      "Unpaired isolated-vs-later and within-shooter lines above are the "
      "better check for 'is the second match bad,' because the earlier match "
      "can differ from a typical match too.";
}
