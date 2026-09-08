/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// How often a division podium (places 1–3) spans less than 1% of the winner
/// score in the L2s Main LLR major-match dataset.
///
/// A tight podium is 3rd-place [BareRelativeScore.ratio] >= threshold
/// (default 0.99). Single-division rating groups only.
///
/// Launch: dart run bin/db_oneoffs.dart TPS [threshold] [minCompetitors] [projectName]

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const double kDefaultThreshold = 0.99;
const int kDefaultMinCompetitors = 3;
const int kMaxListedCases = 40;

class TightPodiumSpanCommand extends DbOneoffCommand {
  TightPodiumSpanCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "TPS";

  @override
  final String title = "Tight Podium Span";

  @override
  String? get description =>
      "How often a division's top three finish within the ratio >= 0.99 "
      "region (podium spans less than 1%).";

  @override
  List<MenuArgument> get arguments => [
        StringMenuArgument(
          label: "Threshold",
          required: false,
          defaultValue: kDefaultThreshold.toString(),
          description:
              "Minimum 3rd-place ratio vs winner for a tight podium (default 0.99).",
        ),
        IntMenuArgument(
          label: "Min competitors",
          required: false,
          defaultValue: kDefaultMinCompetitors,
          description:
              "Minimum eligible (non-DQ) competitors in the division to count "
              "a podium (default 3).",
        ),
        StringMenuArgument(
          label: "Project name",
          required: false,
          defaultValue: kDefaultLlrProjectName,
          description: "Rating project whose match set is the major-match dataset.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final thresholdRaw = arguments
            .firstWhereOrNull((a) => a.argument.label == "Threshold")
            ?.getAs<String>()
            .trim() ??
        "";
    final minCompetitors = arguments
            .firstWhereOrNull((a) => a.argument.label == "Min competitors")
            ?.getAs<int>() ??
        kDefaultMinCompetitors;
    final projectName = arguments
            .firstWhereOrNull((a) => a.argument.label == "Project name")
            ?.getAs<String>()
            .trim() ??
        kDefaultLlrProjectName;

    final threshold = double.tryParse(
          thresholdRaw.isEmpty ? kDefaultThreshold.toString() : thresholdRaw,
        ) ??
        kDefaultThreshold;

    if (threshold <= 0 || threshold > 1.0) {
      console.print("Threshold should be in (0, 1], e.g. 0.99 (got: $threshold).");
      return;
    }
    if (minCompetitors < 3) {
      console.print("Min competitors must be at least 3 (got $minCompetitors).");
      return;
    }

    await _run(
      db,
      console,
      projectName: projectName.isEmpty ? kDefaultLlrProjectName : projectName,
      threshold: threshold,
      minCompetitors: minCompetitors,
    );
  }
}

class _Podium {
  _Podium({
    required this.matchName,
    required this.date,
    required this.groupLabel,
    required this.competitors,
    required this.first,
    required this.second,
    required this.third,
  });

  final String matchName;
  final DateTime date;
  final String groupLabel;
  final int competitors;
  final _Place first;
  final _Place second;
  final _Place third;

  double get thirdRatio => third.ratio;
  double get span => 1.0 - third.ratio;
  String get dateLabel => date.toIso8601String().split("T").first;
}

class _Place {
  _Place({required this.name, required this.ratio, required this.place});

  final String name;
  final double ratio;
  final int place;
}

class _Counter {
  int total = 0;
  int tight = 0;
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required double threshold,
  required int minCompetitors,
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
    console.print("No single-division rating groups in $projectName.");
    return;
  }

  final pointers = [...project.matchPointers]
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  if (pointers.isEmpty) {
    console.print("No matches in $projectName.");
    return;
  }

  final overall = _Counter();
  final byGroup = <String, _Counter>{
    for (final g in groups) g.uiLabel: _Counter(),
  };
  final byYear = <int, _Counter>{};
  final fieldBuckets = <String, _Counter>{
    "3-9": _Counter(),
    "10-24": _Counter(),
    "25-49": _Counter(),
    "50+": _Counter(),
  };
  final min10 = _Counter();
  final min25 = _Counter();
  final min50 = _Counter();
  final thirdRatios = <double>[];
  final tightCases = <_Podium>[];

  var loadErrors = 0;
  var hydrateErrors = 0;
  var matchesScored = 0;
  var shortFields = 0;

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    canHaveErrors: true,
    initialLabel: "Scoring division podiums…",
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
    matchesScored++;

    for (final group in groups) {
      final scores = shootingMatch.getScoresFromFilters(group.filters);
      final eligible = <RelativeMatchScore>[];
      for (final entry in scores.entries) {
        final matchEntry = entry.key;
        final rel = entry.value;
        if (matchEntry.dq) {
          continue;
        }
        if (!group.filters.reentries && matchEntry.reentry) {
          continue;
        }
        if (!rel.hasResults || rel.ratio <= 0) {
          continue;
        }
        eligible.add(rel);
      }

      if (eligible.length < minCompetitors) {
        shortFields++;
        continue;
      }

      eligible.sort((a, b) {
        final byRatio = b.ratio.compareTo(a.ratio);
        if (byRatio != 0) {
          return byRatio;
        }
        return a.place.compareTo(b.place);
      });

      final first = eligible[0];
      final second = eligible[1];
      final third = eligible[2];
      final thirdRatio = third.ratio;
      final isTight = thirdRatio >= threshold;

      overall.total++;
      if (isTight) {
        overall.tight++;
      }

      final groupStats = byGroup[group.uiLabel]!;
      groupStats.total++;
      if (isTight) {
        groupStats.tight++;
      }

      final year = shootingMatch.date.year;
      final yearStats = byYear.putIfAbsent(year, () => _Counter());
      yearStats.total++;
      if (isTight) {
        yearStats.tight++;
      }

      final n = eligible.length;
      final bucket = _fieldBucket(n);
      fieldBuckets[bucket]!.total++;
      if (isTight) {
        fieldBuckets[bucket]!.tight++;
      }
      if (n >= 10) {
        min10.total++;
        if (isTight) {
          min10.tight++;
        }
      }
      if (n >= 25) {
        min25.total++;
        if (isTight) {
          min25.tight++;
        }
      }
      if (n >= 50) {
        min50.total++;
        if (isTight) {
          min50.tight++;
        }
      }

      thirdRatios.add(thirdRatio);

      if (isTight) {
        tightCases.add(
          _Podium(
            matchName: shootingMatch.name,
            date: shootingMatch.date,
            groupLabel: group.uiLabel,
            competitors: n,
            first: _placeOf(first),
            second: _placeOf(second),
            third: _placeOf(third),
          ),
        );
      }
    }
  }

  bar.complete();

  tightCases.sort((a, b) {
    final byRatio = b.thirdRatio.compareTo(a.thirdRatio);
    if (byRatio != 0) {
      return byRatio;
    }
    return a.competitors.compareTo(b.competitors);
  });

  final buf = StringBuffer()
    ..writeln("Project: $projectName")
    ..writeln(
      "Matches: ${pointers.length} pointers, $matchesScored scored "
      "($loadErrors load errors, $hydrateErrors hydrate errors)",
    )
    ..writeln(
      "Groups: single-division only (${groups.map((g) => g.uiLabel).join(", ")})",
    )
    ..writeln(
      "Podium: places 1–3 after getScoresFromFilters (non-DQ, hasResults, "
      "respect reentry filter); ranked by ratio",
    )
    ..writeln(
      "Tight: 3rd-place ratio >= $threshold "
      "(${(threshold * 100).toStringAsFixed(1)}% of winner)  "
      "i.e. podium span < ${((1.0 - threshold) * 100).toStringAsFixed(1)}%",
    )
    ..writeln("Min competitors: $minCompetitors  (skipped $shortFields short fields)")
    ..writeln("")
    ..writeln("=== Overall ===")
    ..writeln("  Tight podiums: ${_rate(overall)}")
    ..writeln("  Field >= 10:   ${_rate(min10)}")
    ..writeln("  Field >= 25:   ${_rate(min25)}")
    ..writeln("  Field >= 50:   ${_rate(min50)}")
    ..writeln("")
    ..writeln("=== By division ===");

  for (final group in groups) {
    final stats = byGroup[group.uiLabel]!;
    buf.writeln("  ${_pad(group.uiLabel, 22)}  ${_rate(stats)}");
  }

  buf.writeln("");
  buf.writeln("=== By year ===");
  for (final year in byYear.keys.sorted((a, b) => a.compareTo(b))) {
    buf.writeln("  $year  ${_rate(byYear[year]!)}");
  }

  buf.writeln("");
  buf.writeln("=== By field size ===");
  for (final label in ["3-9", "10-24", "25-49", "50+"]) {
    buf.writeln("  ${_pad(label, 8)}  ${_rate(fieldBuckets[label]!)}");
  }

  buf.writeln("");
  buf.writeln("=== 3rd-place ratio distribution ===");
  buf.writeln("  ${_ratioSummary(thirdRatios)}");
  buf.writeln("");
  for (final line in _ratioHistogram(thirdRatios)) {
    buf.writeln("  $line");
  }

  buf.writeln("");
  final listed = tightCases.take(kMaxListedCases).toList();
  buf.writeln(
    "=== Tight podiums "
    "(${tightCases.length} total, showing ${listed.length}, tightest first) ===",
  );
  if (listed.isEmpty) {
    buf.writeln("  (none)");
  }
  else {
    for (final p in listed) {
      buf.writeln(
        "  ${p.dateLabel}  ${_pad(p.groupLabel, 18)}  n=${p.competitors.toString().padLeft(3)}  "
        "${_fmtRatio(p.first.ratio)} / ${_fmtRatio(p.second.ratio)} / ${_fmtRatio(p.third.ratio)}  "
        "${p.first.name} / ${p.second.name} / ${p.third.name}  "
        "${p.matchName}",
      );
    }
    if (tightCases.length > listed.length) {
      buf.writeln("  … ${tightCases.length - listed.length} more");
    }
  }

  console.print(buf.toString());
}

_Place _placeOf(RelativeMatchScore score) {
  return _Place(
    name: score.shooter.getName(suffixes: false),
    ratio: score.ratio,
    place: score.place,
  );
}

String _fieldBucket(int n) {
  if (n >= 50) {
    return "50+";
  }
  if (n >= 25) {
    return "25-49";
  }
  if (n >= 10) {
    return "10-24";
  }
  return "3-9";
}

String _rate(_Counter c) {
  if (c.total == 0) {
    return "0 / 0  (n/a)";
  }
  return "${c.tight} / ${c.total}  (${_pct(c.tight, c.total)})";
}

String _pct(int numerator, int denominator) {
  if (denominator == 0) {
    return "n/a";
  }
  return "${(100.0 * numerator / denominator).toStringAsFixed(2)}%";
}

String _fmtRatio(double ratio) => ratio.toStringAsFixed(4);

String _pad(String value, int width) {
  if (value.length > width) {
    return value.substring(0, width);
  }
  return value.padRight(width);
}

String _ratioSummary(List<double> values) {
  if (values.isEmpty) {
    return "n/a";
  }
  final sorted = [...values]..sort();
  final n = sorted.length;
  double at(double q) {
    final idx = ((n - 1) * q).round().clamp(0, n - 1);
    return sorted[idx];
  }
  final mean = sorted.fold<double>(0.0, (a, b) => a + b) / n;
  return "n=$n  mean=${_fmtRatio(mean)}  "
      "p10=${_fmtRatio(at(0.10))}  p25=${_fmtRatio(at(0.25))}  "
      "p50=${_fmtRatio(at(0.50))}  p75=${_fmtRatio(at(0.75))}  "
      "p90=${_fmtRatio(at(0.90))}  p95=${_fmtRatio(at(0.95))}  "
      "max=${_fmtRatio(sorted.last)}  "
      "typical span=${((1.0 - at(0.50)) * 100).toStringAsFixed(2)}%";
}

List<String> _ratioHistogram(List<double> values) {
  if (values.isEmpty) {
    return ["(none)"];
  }
  final labels = [
    "<0.90",
    "0.90–0.92",
    "0.92–0.94",
    "0.94–0.95",
    "0.95–0.96",
    "0.96–0.97",
    "0.97–0.98",
    "0.98–0.99",
    "0.99–0.995",
    "0.995–1.00",
    "1.00",
  ];
  final counts = List<int>.filled(labels.length, 0);
  for (final v in values) {
    if (v >= 1.0) {
      counts[10]++;
    }
    else if (v >= 0.995) {
      counts[9]++;
    }
    else if (v >= 0.99) {
      counts[8]++;
    }
    else if (v >= 0.98) {
      counts[7]++;
    }
    else if (v >= 0.97) {
      counts[6]++;
    }
    else if (v >= 0.96) {
      counts[5]++;
    }
    else if (v >= 0.95) {
      counts[4]++;
    }
    else if (v >= 0.94) {
      counts[3]++;
    }
    else if (v >= 0.92) {
      counts[2]++;
    }
    else if (v >= 0.90) {
      counts[1]++;
    }
    else {
      counts[0]++;
    }
  }
  final maxCount = counts.reduce((a, b) => a > b ? a : b);
  final barWidth = 24;
  final lines = <String>[];
  for (var i = 0; i < labels.length; i++) {
    final n = counts[i];
    final filled = maxCount == 0 ? 0 : ((n / maxCount) * barWidth).round();
    final bar = "#" * filled;
    lines.add(
      "${_pad(labels[i], 12)}  ${n.toString().padLeft(5)}  ${_pct(n, values.length).padLeft(7)}  $bar",
    );
  }
  return lines;
}
