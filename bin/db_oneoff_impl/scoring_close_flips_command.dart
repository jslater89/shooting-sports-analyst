/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Close finish order flips: division scoring vs all-shooters combined.
///
/// For Carry Optics and Limited Optics matches in [L2s Main LLR] from a start
/// year through today, finds pairwise finishes that are close under *divisional*
/// scoring (within min(maxPoints, maxPct of winner points)), then checks whether
/// those two competitors reverse order when the same match is scored with all
/// shooters (combined stage winners).
///
/// Menu: SCF

import "dart:math" as math;

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/data/sport/shooter/filter_set.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const int kDefaultStartYear = 2023;
const double kDefaultMaxPointMargin = 10.0;
const double kDefaultMaxPctMargin = 0.5; // percentage points of winner finish
const int kExampleFlips = 15;
const int kMinDivisionCompetitors = 5;

final List<Division> kDefaultDivisions = [
  uspsaCarryOptics,
  uspsaLimitedOptics,
];

class ScoringCloseFlipsCommand extends DbOneoffCommand {
  ScoringCloseFlipsCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "SCF";

  @override
  final String title = "Scoring Close Flips (Div vs Combined)";

  @override
  String? get description =>
      "Among close CO/LO pairwise finishes (divisional scoring), how often "
      "order flips under all-shooters combined scoring.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Start year",
          required: false,
          defaultValue: kDefaultStartYear,
          description: "Include matches on or after Jan 1 of this year.",
        ),
        StringMenuArgument(
          label: "Max point margin",
          required: false,
          defaultValue: kDefaultMaxPointMargin.toString(),
          description: "Absolute match-point margin for a close pair (default 10).",
        ),
        StringMenuArgument(
          label: "Max pct margin",
          required: false,
          defaultValue: kDefaultMaxPctMargin.toString(),
          description:
              "Percentage-point margin of division winner points (default 0.5).",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final startYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "Start year")
            ?.getAs<int>() ??
        kDefaultStartYear;

    final maxPtsRaw = arguments
            .firstWhereOrNull((a) => a.argument.label == "Max point margin")
            ?.getAs<String>()
            .trim() ??
        "";
    final maxPctRaw = arguments
            .firstWhereOrNull((a) => a.argument.label == "Max pct margin")
            ?.getAs<String>()
            .trim() ??
        "";

    final maxPointMargin = double.tryParse(
          maxPtsRaw.isEmpty ? kDefaultMaxPointMargin.toString() : maxPtsRaw,
        ) ??
        kDefaultMaxPointMargin;
    final maxPctMargin = double.tryParse(
          maxPctRaw.isEmpty ? kDefaultMaxPctMargin.toString() : maxPctRaw,
        ) ??
        kDefaultMaxPctMargin;

    if (maxPointMargin <= 0 || maxPctMargin <= 0) {
      console.print("Margins must be positive.");
      return;
    }

    await _run(
      db,
      console,
      projectName: kDefaultLlrProjectName,
      startYear: startYear,
      maxPointMargin: maxPointMargin,
      maxPctMargin: maxPctMargin,
    );
  }
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required int startYear,
  required double maxPointMargin,
  required double maxPctMargin,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }

  final sport = project.sport;
  final startDate = DateTime(startYear, 1, 1);
  final pointers = project.matchPointers
      .where((p) => p.date != null && !p.date!.isBefore(startDate))
      .toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  if (pointers.isEmpty) {
    console.print("No matches in $projectName on/after $startYear.");
    return;
  }

  final byDivision = <String, _DivisionStats>{
    for (final d in kDefaultDivisions) d.name: _DivisionStats(d.name),
  };
  final flips = <_FlipExample>[];

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    initialLabel: "Scoring close flips...",
    canHaveErrors: true,
  );

  var matchesScored = 0;
  var hydrateErrors = 0;

  for (final ptr in pointers) {
    bar.tick(ptr.name);

    final res = await ptr.getDbMatch(db, downloadIfMissing: false);
    if (res.isErr()) {
      hydrateErrors++;
      continue;
    }
    final dbMatch = res.unwrap();
    if (dbMatch.shootersStoredSeparately) {
      await dbMatch.shooterLinks.load();
    }

    final hydrated = await dbMatch.hydrate();
    if (hydrated.isErr()) {
      hydrateErrors++;
      continue;
    }
    final match = hydrated.unwrap();
    matchesScored++;

    final combinedScores = match.getScores();

    for (final division in kDefaultDivisions) {
      final stats = byDivision[division.name]!;
      final divFilters = FilterSet(
        sport,
        divisions: [division],
        mode: FilterMode.or,
        empty: true,
      );
      final divScores = match.getScoresFromFilters(divFilters);

      final ranked = divScores.values
          .where((s) => !s.shooter.dq && s.hasResults)
          .toList()
        ..sort((a, b) {
          final byPoints = b.points.compareTo(a.points);
          if (byPoints != 0) {
            return byPoints;
          }
          return a.place.compareTo(b.place);
        });

      if (ranked.length < kMinDivisionCompetitors) {
        continue;
      }

      stats.matchesWithField++;
      stats.competitors += ranked.length;

      final winnerPoints = ranked.first.points;
      if (winnerPoints <= 0) {
        continue;
      }

      final pctAsPoints = (maxPctMargin / 100.0) * winnerPoints;
      final threshold = math.min(maxPointMargin, pctAsPoints);

      for (var i = 0; i < ranked.length; i++) {
        final higher = ranked[i];
        for (var j = i + 1; j < ranked.length; j++) {
          final lower = ranked[j];
          final margin = higher.points - lower.points;
          if (margin > threshold) {
            // Sorted descending; further j only farther.
            break;
          }
          if (margin <= 0) {
            // Tie or non-strict order under points — skip.
            continue;
          }

          stats.closePairs++;
          stats.closeMargins.add(margin);
          stats.closeMarginsPct.add(100.0 * margin / winnerPoints);

          final combinedHigher = combinedScores[higher.shooter];
          final combinedLower = combinedScores[lower.shooter];
          if (combinedHigher == null || combinedLower == null) {
            stats.missingCombined++;
            continue;
          }

          final combinedMargin =
              combinedHigher.points - combinedLower.points;
          // Flip: divisional higher is strictly behind under combined.
          if (combinedMargin < 0) {
            stats.flips++;
            stats.flipMargins.add(margin);
            stats.flipMarginsPct.add(100.0 * margin / winnerPoints);
            stats.combinedFlipMargins.add(-combinedMargin);

            flips.add(
              _FlipExample(
                matchName: match.name,
                matchDate: match.date,
                divisionName: division.name,
                winnerName: higher.shooter.getName(suffixes: false),
                loserName: lower.shooter.getName(suffixes: false),
                divWinnerPoints: higher.points,
                divLoserPoints: lower.points,
                divWinnerPlace: higher.place,
                divLoserPlace: lower.place,
                divWinnerPct: higher.percentage,
                divLoserPct: lower.percentage,
                combinedWinnerPoints: combinedHigher.points,
                combinedLoserPoints: combinedLower.points,
                combinedWinnerPlace: combinedHigher.place,
                combinedLoserPlace: combinedLower.place,
                combinedWinnerPct: combinedHigher.percentage,
                combinedLoserPct: combinedLower.percentage,
                winnerMatchPoints: winnerPoints,
                threshold: threshold,
              ),
            );
          }
        }
      }
    }
  }

  bar.tick("Done");

  flips.sort((a, b) => b.divMargin.compareTo(a.divMargin));

  final buf = StringBuffer()
    ..writeln("Project: $projectName")
    ..writeln("Matches: on/after $startYear (${pointers.length} pointers, $matchesScored scored, $hydrateErrors load/hydrate errors)")
    ..writeln(
      "Divisions: ${kDefaultDivisions.map((d) => d.name).join(", ")}",
    )
    ..writeln(
      "Close pair: abs(points) ≤ min($maxPointMargin pts, "
      "${maxPctMargin.toStringAsFixed(2)}% of division winner points)",
    )
    ..writeln(
      "Combined scoring: match.getScores() (all shooters / all divisions)",
    )
    ..writeln(
      "Identity: same MatchEntry keys; flip = strict divisional points order reverses under combined.",
    )
    ..writeln("Min division field: $kMinDivisionCompetitors non-DQ with results")
    ..writeln("");

  for (final division in kDefaultDivisions) {
    final stats = byDivision[division.name]!;
    buf.writeln("=== ${division.name} ===");
    buf.writeln("  Matches with field: ${stats.matchesWithField}");
    buf.writeln("  Competitor-starts: ${stats.competitors}");
    buf.writeln("  Close pairs: ${stats.closePairs}");
    buf.writeln(
      "  Flips: ${stats.flips} (${_pct(stats.flips, stats.closePairs)})",
    );
    if (stats.missingCombined > 0) {
      buf.writeln("  Missing in combined map: ${stats.missingCombined}");
    }
    if (stats.closeMargins.isNotEmpty) {
      buf.writeln(
        "  Close margins (div pts): ${_summary(stats.closeMargins)}",
      );
      buf.writeln(
        "  Close margins (div % of winner): ${_summary(stats.closeMarginsPct)}",
      );
    }
    if (stats.flipMargins.isNotEmpty) {
      buf.writeln(
        "  Flipped divisional margins (pts): ${_summary(stats.flipMargins)}",
      );
      buf.writeln(
        "  Flipped divisional margins (% of winner): ${_summary(stats.flipMarginsPct)}",
      );
      buf.writeln(
        "  Combined margin after flip (pts, absolute): ${_summary(stats.combinedFlipMargins)}",
      );
      buf.writeln("  Margin histogram (flipped divisional pts):");
      for (final line in _histogramLines(stats.flipMargins)) {
        buf.writeln("    $line");
      }
    }
    buf.writeln("");
  }

  final allClose = byDivision.values.fold<int>(0, (s, d) => s + d.closePairs);
  final allFlips = byDivision.values.fold<int>(0, (s, d) => s + d.flips);
  final allFlipMargins =
      byDivision.values.expand((d) => d.flipMargins).toList();

  buf.writeln("=== Overall (CO + LO) ===");
  buf.writeln("  Close pairs: $allClose");
  buf.writeln("  Flips: $allFlips (${_pct(allFlips, allClose)})");
  if (allFlipMargins.isNotEmpty) {
    buf.writeln(
      "  Largest flipped divisional margin: "
      "${allFlipMargins.reduce(math.max).toStringAsFixed(2)} pts",
    );
    buf.writeln(
      "  Flipped margin summary (pts): ${_summary(allFlipMargins)}",
    );
  }
  else {
    buf.writeln("  No flips found under these thresholds.");
  }
  buf.writeln("");

  if (flips.isNotEmpty) {
    buf.writeln("=== Largest flipped divisional margins (top $kExampleFlips) ===");
    for (final ex in flips.take(kExampleFlips)) {
      final dateStr = ex.matchDate.toIso8601String().split("T").first;
      buf.writeln(
        "  [${ex.divisionName}] ${ex.matchName} ($dateStr) "
        "threshold=${ex.threshold.toStringAsFixed(2)}",
      );
      buf.writeln(
        "    Div: #${ex.divWinnerPlace} ${ex.winnerName} "
        "${ex.divWinnerPoints.toStringAsFixed(1)} "
        "(${ex.divWinnerPct.toStringAsFixed(2)}%)  >  "
        "#${ex.divLoserPlace} ${ex.loserName} "
        "${ex.divLoserPoints.toStringAsFixed(1)} "
        "(${ex.divLoserPct.toStringAsFixed(2)}%)  "
        "Δ=${ex.divMargin.toStringAsFixed(2)} pts "
        "(${ex.divMarginPct.toStringAsFixed(3)}% of winner)",
      );
      buf.writeln(
        "    Combined: #${ex.combinedLoserPlace} ${ex.loserName} "
        "${ex.combinedLoserPoints.toStringAsFixed(1)} "
        "(${ex.combinedLoserPct.toStringAsFixed(2)}%)  >  "
        "#${ex.combinedWinnerPlace} ${ex.winnerName} "
        "${ex.combinedWinnerPoints.toStringAsFixed(1)} "
        "(${ex.combinedWinnerPct.toStringAsFixed(2)}%)  "
        "Δ=${(-ex.combinedMargin).toStringAsFixed(2)} pts the other way",
      );
    }
  }

  console.print(buf.toString());
}

String _pct(int numerator, int denominator) {
  if (denominator == 0) {
    return "n/a";
  }
  return "${(100.0 * numerator / denominator).toStringAsFixed(2)}% of $denominator";
}

String _summary(List<double> values) {
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
  return "n=$n mean=${mean.toStringAsFixed(2)} "
      "p50=${at(0.5).toStringAsFixed(2)} "
      "p90=${at(0.9).toStringAsFixed(2)} "
      "p99=${at(0.99).toStringAsFixed(2)} "
      "max=${sorted.last.toStringAsFixed(2)}";
}

List<String> _histogramLines(List<double> values) {
  if (values.isEmpty) {
    return ["(none)"];
  }
  // Buckets: [0,1), [1,2), ... [9,10), [10,+)
  final counts = List<int>.filled(11, 0);
  for (final v in values) {
    if (v >= 10) {
      counts[10]++;
    }
    else {
      final b = v.floor().clamp(0, 9);
      counts[b]++;
    }
  }
  final maxCount = counts.reduce(math.max);
  final lines = <String>[];
  for (var i = 0; i < 10; i++) {
    final bar = _barChars(counts[i], maxCount);
    lines.add(
      "${i.toString().padLeft(2)}–${i + 1}: ${counts[i].toString().padLeft(5)} $bar",
    );
  }
  final bar = _barChars(counts[10], maxCount);
  lines.add(" 10+: ${counts[10].toString().padLeft(5)} $bar");
  return lines;
}

String _barChars(int count, int maxCount) {
  if (maxCount <= 0 || count <= 0) {
    return "";
  }
  final width = ((40.0 * count) / maxCount).round().clamp(1, 40);
  return "#" * width;
}

final class _DivisionStats {
  _DivisionStats(this.name);

  final String name;
  int matchesWithField = 0;
  int competitors = 0;
  int closePairs = 0;
  int flips = 0;
  int missingCombined = 0;
  final List<double> closeMargins = [];
  final List<double> closeMarginsPct = [];
  final List<double> flipMargins = [];
  final List<double> flipMarginsPct = [];
  final List<double> combinedFlipMargins = [];
}

final class _FlipExample {
  _FlipExample({
    required this.matchName,
    required this.matchDate,
    required this.divisionName,
    required this.winnerName,
    required this.loserName,
    required this.divWinnerPoints,
    required this.divLoserPoints,
    required this.divWinnerPlace,
    required this.divLoserPlace,
    required this.divWinnerPct,
    required this.divLoserPct,
    required this.combinedWinnerPoints,
    required this.combinedLoserPoints,
    required this.combinedWinnerPlace,
    required this.combinedLoserPlace,
    required this.combinedWinnerPct,
    required this.combinedLoserPct,
    required this.winnerMatchPoints,
    required this.threshold,
  });

  final String matchName;
  final DateTime matchDate;
  final String divisionName;
  final String winnerName;
  final String loserName;
  final double divWinnerPoints;
  final double divLoserPoints;
  final int divWinnerPlace;
  final int divLoserPlace;
  final double divWinnerPct;
  final double divLoserPct;
  final double combinedWinnerPoints;
  final double combinedLoserPoints;
  final int combinedWinnerPlace;
  final int combinedLoserPlace;
  final double combinedWinnerPct;
  final double combinedLoserPct;
  final double winnerMatchPoints;
  final double threshold;

  double get divMargin => divWinnerPoints - divLoserPoints;
  double get divMarginPct => 100.0 * divMargin / winnerMatchPoints;
  double get combinedMargin => combinedWinnerPoints - combinedLoserPoints;
}
