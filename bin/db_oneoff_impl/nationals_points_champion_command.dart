/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// How often the USPSA division national champion also shot the best
/// available points, in L2s Main LLR.
///
/// Match discovery follows Distinguished Grandmaster: the name matches
/// [kNationalsNamePattern] and does not match [kNationalsExcludePattern].
/// Word boundaries keep the "national" inside "international" from matching.
///
/// For each calendar year, a division's championship is the nationals match
/// where that division had the most complete finishers (at least
/// [kMinFinishers]). That keeps a real Limited field at Race Gun Nationals
/// and drops a handful of bump shooters at another division's nationals.
/// Combined groups are skipped.
///
/// Champion: best match place from getScoresFromFilters, among non-DQ,
/// complete finishers, respecting the group's reentry filter.
/// Best available points: highest total points / stage max points, penalties
/// included (the results-table Available Points sort).
///
/// Launch: dart run bin/db_oneoffs.dart NPC

import "dart:math";

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/util.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";

/// Whole-word Nationals, or "National Championship(s)".
final RegExp kNationalsNamePattern = RegExp(
  r"\bNationals\b|\bNational\s+Championships?\b",
  caseSensitive: false,
);

/// Same exclusions as Distinguished Grandmaster, plus multigun nationals.
final RegExp kNationalsExcludePattern = RegExp(
  r"\bIPSC\b|Shooting International|\bmultigun\b|\bmulti-gun\b|\b3-gun\b|\b3gun\b",
  caseSensitive: false,
);

const int kMinFinishers = 10;

bool _isUspsaNationalsName(String name) {
  return kNationalsNamePattern.hasMatch(name) && !kNationalsExcludePattern.hasMatch(name);
}

class NationalsPointsChampionCommand extends DbOneoffCommand {
  NationalsPointsChampionCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "NPC";

  @override
  final String title = "Nationals Points vs Champion";

  @override
  String? get description =>
      "How often the USPSA division national champion in L2s Main LLR also "
      "shot the best available points.";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _run(db, console, projectName: kDefaultLlrProjectName);
  }
}

class _Finish {
  _Finish({
    required this.entry,
    required this.score,
    required this.points,
  });

  final MatchEntry entry;
  final RelativeMatchScore score;
  final int points;

  String get label => "${entry.getName(suffixes: false)} (${entry.memberNumber})";
}

class _Championship {
  _Championship({
    required this.date,
    required this.matchName,
    required this.division,
    required this.finishers,
    required this.champions,
    required this.leaders,
    required this.maxPoints,
    required this.championHasBestPoints,
  });

  final DateTime? date;
  final String matchName;
  final String division;
  final int finishers;
  final List<_Finish> champions;
  final List<_Finish> leaders;
  final int maxPoints;
  final bool championHasBestPoints;

  int get year => date?.year ?? 0;

  String get dateLabel => date?.toIso8601String().split("T").first ?? "?";

  bool get tiedForBestPoints => leaderPoints == championPoints && leaders.length > 1;

  int get championPoints => champions.map((f) => f.points).reduce(min);

  int get leaderPoints => leaders.first.points;

  double get pointsGap => maxPoints == 0 ? 0 : (leaderPoints - championPoints) / maxPoints;

  int get leaderBestPlace => leaders.map((f) => f.score.place).reduce(min);
}

class _Tally {
  int total = 0;
  int yes = 0;
  int tied = 0;

  void add(_Championship row) {
    total++;
    if (row.championHasBestPoints) {
      yes++;
      if (row.tiedForBestPoints) {
        tied++;
      }
    }
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

  final groups = project.groups
      .where((g) => g.divisionNames.length == 1)
      .sorted((a, b) => a.sortOrder.compareTo(b.sortOrder))
      .toList();
  final pointers = project.matchPointers
      .where((p) => p.sportName.toLowerCase() == "uspsa")
      .where((p) => _isUspsaNationalsName(p.name))
      .toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  if (pointers.isEmpty) {
    console.print("No USPSA Nationals matches found in $projectName.");
    return;
  }

  final rows = <_Championship>[];
  final emptyMatches = <String>[];
  var loadErrors = 0;
  var hydrateErrors = 0;
  var skippedSmall = 0;
  var skippedNoMax = 0;

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    canHaveErrors: true,
    initialLabel: "Processing Nationals matches…",
  );

  for (final ptr in pointers) {
    bar.tick(ptr.name);

    final loadRes = await ptr.getDbMatch(db, downloadIfMissing: false);
    if (loadRes.isErr()) {
      bar.error("Load failed: ${ptr.name}");
      loadErrors++;
      continue;
    }
    final dbMatch = loadRes.unwrap();
    if (dbMatch.shootersStoredSeparately) {
      await dbMatch.shooterLinks.load();
    }

    final hydrated = await dbMatch.hydrate();
    if (hydrated.isErr()) {
      bar.error("Hydrate failed: ${ptr.name}");
      hydrateErrors++;
      continue;
    }
    final shootingMatch = hydrated.unwrap();
    final rowsBeforeMatch = rows.length;

    for (final group in groups) {
      final scores = shootingMatch.getScoresFromFilters(group.filters);
      final eligible = <_Finish>[];
      for (final entry in scores.entries) {
        final matchEntry = entry.key;
        if (matchEntry.dq) {
          continue;
        }
        if (!group.filters.reentries && matchEntry.reentry) {
          continue;
        }
        if (!entry.value.isComplete) {
          continue;
        }
        final points = _totalPoints(entry.value);
        eligible.add(_Finish(entry: matchEntry, score: entry.value, points: points));
      }

      if (eligible.length < kMinFinishers) {
        if (eligible.isNotEmpty) {
          skippedSmall++;
        }
        continue;
      }

      final maxPoints = eligible.first.score.maxPoints();
      if (maxPoints <= 0) {
        skippedNoMax++;
        continue;
      }

      final bestPlace = eligible.map((f) => f.score.place).reduce(min);
      final bestPoints = eligible.map((f) => f.points).reduce(max);
      final champions = eligible.where((f) => f.score.place == bestPlace).toList();
      final leaders = eligible.where((f) => f.points == bestPoints).toList();
      final championHasBest = champions.every((c) => leaders.any((l) => identical(l.entry, c.entry)));

      rows.add(_Championship(
        date: shootingMatch.date,
        matchName: shootingMatch.name,
        division: group.uiLabel,
        finishers: eligible.length,
        champions: champions,
        leaders: leaders,
        maxPoints: maxPoints,
        championHasBestPoints: championHasBest,
      ));
    }

    if (rows.length == rowsBeforeMatch) {
      emptyMatches.add("${_dateLabel(ptr.date)}  ${ptr.name}");
    }
  }

  bar.complete();

  rows.sort((a, b) {
    final byDate = (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970));
    if (byDate != 0) {
      return byDate;
    }
    return a.division.compareTo(b.division);
  });

  final maxByKey = <String, int>{};
  for (final row in rows) {
    final key = "${row.year}|${row.division}";
    final current = maxByKey[key] ?? 0;
    if (row.finishers > current) {
      maxByKey[key] = row.finishers;
    }
  }
  final championships = <_Championship>[];
  final droppedSmaller = <_Championship>[];
  for (final row in rows) {
    final maxFinishers = maxByKey["${row.year}|${row.division}"]!;
    if (row.finishers == maxFinishers) {
      championships.add(row);
    }
    else {
      droppedSmaller.add(row);
    }
  }

  final overall = _Tally();
  final byDivision = <String, _Tally>{};
  final byYear = <int, _Tally>{};
  for (final row in championships) {
    overall.add(row);
    (byDivision[row.division] ??= _Tally()).add(row);
    (byYear[row.year] ??= _Tally()).add(row);
  }

  final mismatches = championships.where((r) => !r.championHasBestPoints).toList()
    ..sort((a, b) => b.pointsGap.compareTo(a.pointsGap));
  final gaps = mismatches.map((r) => r.pointsGap).toList();
  final leaderPlaces = mismatches.map((r) => r.leaderBestPlace).toList()..sort();

  final buf = StringBuffer()
    ..writeln("Project: $projectName")
    ..writeln("Sport: USPSA")
    ..writeln("Matches: ${kNationalsNamePattern.pattern}")
    ..writeln("Excludes: ${kNationalsExcludePattern.pattern}")
    ..writeln("Groups: single-division only (${groups.map((g) => g.uiLabel).join(", ")})")
    ..writeln(
      "Championship: for each year and division, the nationals match with the "
      "most complete finishers, at least $kMinFinishers. "
      "Smaller same-year fields are not a second championship.",
    )
    ..writeln(
      "Eligible: non-DQ, complete match, reentries follow the group filter. "
      "Minimum finishers: $kMinFinishers.",
    )
    ..writeln(
      "Champion: best match place in that pool. "
      "Best available points: highest points / stage max, penalties included.",
    )
    ..writeln("Yes: every champion is among the available-points leaders (ties count as yes).")
    ..writeln("")
    ..writeln("Nationals matches: ${pointers.length}  (load errors $loadErrors, hydrate errors $hydrateErrors)")
    ..writeln("Division fields at nationals: ${rows.length}")
    ..writeln("Championships counted (largest field that year): ${championships.length}")
    ..writeln("Smaller same-year fields dropped: ${droppedSmaller.length}")
    ..writeln("Division fields under $kMinFinishers finishers: $skippedSmall")
    ..writeln("Skipped, zero available points: $skippedNoMax")
    ..writeln("")
    ..writeln(
      "Division national champion also shot the best available points: ${_pct(overall.yes, overall.total)}",
    )
    ..writeln("  Unique champion and unique points leader: ${overall.yes - overall.tied}")
    ..writeln("  Champion tied for best available points: ${overall.tied}")
    ..writeln("  Someone else shot more available points: ${overall.total - overall.yes}");

  if (mismatches.isNotEmpty) {
    final onPodium = mismatches.where((r) => r.leaderBestPlace <= 3).length;
    buf
      ..writeln("")
      ..writeln("When they differ (${mismatches.length}):")
      ..writeln("  Median available-points gap: ${_gapPct(_median(gaps))}")
      ..writeln("  Mean available-points gap: ${_gapPct(gaps.average)}")
      ..writeln("  Median match place of the points leader: ${_medianInt(leaderPlaces)}")
      ..writeln("  Points leader still on the podium: ${_pct(onPodium, mismatches.length)}");
  }

  buf
    ..writeln("")
    ..writeln("By division:");
  final divisionNames = [...byDivision.keys]..sort((a, b) {
    final aOrder = groups.firstWhereOrNull((g) => g.uiLabel == a)?.sortOrder ?? 99;
    final bOrder = groups.firstWhereOrNull((g) => g.uiLabel == b)?.sortOrder ?? 99;
    return aOrder.compareTo(bOrder);
  });
  for (final name in divisionNames) {
    final tally = byDivision[name]!;
    buf.writeln("  ${name.padRight(16)} ${_pct(tally.yes, tally.total)}");
  }

  buf
    ..writeln("")
    ..writeln("By year:");
  final years = [...byYear.keys]..sort();
  for (final year in years) {
    final tally = byYear[year]!;
    buf.writeln("  $year  ${_pct(tally.yes, tally.total)}");
  }

  buf
    ..writeln("")
    ..writeln("Championships where someone else shot more available points:");
  if (mismatches.isEmpty) {
    buf.writeln("  (none)");
  }
  else {
    for (final row in mismatches) {
      final champ = row.champions.map(_finishSummary).join("; ");
      final leader = row.leaders.map(_finishSummary).join("; ");
      buf.writeln(
        "  ${row.dateLabel}  ${row.division.padRight(8)}  "
        "gap ${_gapPct(row.pointsGap)}  n=${row.finishers}  ${row.matchName}",
      );
      buf.writeln("      champion: $champ");
      buf.writeln("      points:   $leader");
    }
  }

  if (droppedSmaller.isNotEmpty) {
    buf
      ..writeln("")
      ..writeln("Smaller same-year fields (not counted):");
    for (final row in droppedSmaller) {
      final kept = maxByKey["${row.year}|${row.division}"];
      buf.writeln(
        "  ${row.dateLabel}  ${row.division.padRight(8)}  n=${row.finishers}  "
        "(championship field n=$kept)  ${row.matchName}",
      );
    }
  }

  buf
    ..writeln("")
    ..writeln("Championship inventory:");
  final inventory = <String, List<_Championship>>{};
  final inventoryOrder = <String>[];
  for (final row in championships) {
    final key = "${row.dateLabel}|${row.matchName}";
    if (!inventory.containsKey(key)) {
      inventoryOrder.add(key);
      inventory[key] = [];
    }
    inventory[key]!.add(row);
  }
  for (final key in inventoryOrder) {
    final matchRows = inventory[key]!;
    matchRows.sort((a, b) {
      final aOrder = groups.firstWhereOrNull((g) => g.uiLabel == a.division)?.sortOrder ?? 99;
      final bOrder = groups.firstWhereOrNull((g) => g.uiLabel == b.division)?.sortOrder ?? 99;
      return aOrder.compareTo(bOrder);
    });
    buf.writeln("  ${matchRows.first.dateLabel}  ${matchRows.first.matchName}");
    for (final row in matchRows) {
      _appendChampionshipLines(buf, row);
    }
  }
  if (emptyMatches.isNotEmpty) {
    buf
      ..writeln("")
      ..writeln("Nationals with no division at the field minimum:");
    for (final line in emptyMatches) {
      buf.writeln("  $line");
    }
  }

  console.print(buf.toString());
}

void _appendChampionshipLines(StringBuffer buf, _Championship row) {
  final same = row.championHasBestPoints;
  final tag = same
      ? (row.tiedForBestPoints ? "same (tied on points)" : "same")
      : "different  gap ${_gapPct(row.pointsGap)}";
  buf.writeln("    ${row.division.padRight(8)}  $tag  n=${row.finishers}");
  if (same) {
    buf.writeln("      winner: ${row.champions.map(_finishSummary).join("; ")}");
    if (row.tiedForBestPoints) {
      final others = row.leaders.where(
        (leader) => row.champions.none((champion) => identical(champion.entry, leader.entry)),
      );
      if (others.isNotEmpty) {
        buf.writeln("      tied:   ${others.map(_finishSummary).join("; ")}");
      }
    }
  }
  else {
    buf.writeln("      champion: ${row.champions.map(_finishSummary).join("; ")}");
    buf.writeln("      points:   ${row.leaders.map(_finishSummary).join("; ")}");
  }
}

int _totalPoints(RelativeMatchScore score) {
  var sum = 0;
  for (final stageScore in score.stageScores.values) {
    sum += stageScore.score.getTotalPoints(countPenalties: true);
  }
  return sum;
}

String _finishSummary(_Finish finish) {
  final maxPoints = finish.score.maxPoints();
  final pointsPct = maxPoints == 0
      ? "?"
      : (finish.points / maxPoints).asPercentage(decimals: 1, includePercent: true);
  final matchPct = finish.score.ratio.asPercentage(decimals: 1, includePercent: true);
  return "${finish.label}  $pointsPct available, place ${finish.score.place}, $matchPct match";
}

String _pct(int numerator, int denominator) {
  if (denominator == 0) {
    return "0/0";
  }
  final pct = (numerator / denominator).asPercentage(decimals: 1, includePercent: true);
  return "$numerator/$denominator ($pct)";
}

String _gapPct(double ratio) {
  return "${(ratio * 100).toStringAsFixed(1)} pp";
}

String _dateLabel(DateTime? date) {
  return date?.toIso8601String().split("T").first ?? "?";
}

double _median(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

int _medianInt(List<int> sorted) {
  if (sorted.isEmpty) {
    return 0;
  }
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}
