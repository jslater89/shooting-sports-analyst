/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Longest placement and percentage finish streaks per rating group.
///
/// Placement thresholds are plain integers (finish place ≤ N). Percentage
/// thresholds end with `%` (finish percentage ≥ N). Streak windows: calendar
/// year 2025 (matches in 2025 only), currently active (trailing streak through
/// most recent counting match, and that match is in the current calendar year),
/// and all-time.
///
/// A division match counts only when it has at least [kMinDivisionCompetitors]
/// non-DQ entries; smaller matches are skipped (no break, no extend). Non-
/// qualifying finishes at counting matches break streaks.
///
/// Match-first online pass: per match and division, only shooters who qualify
/// or hold an active streak get rating lookups. Each shooter may contribute
/// multiple completed runs to top-K (not only their single longest).
///
/// Usage: `STR [topK]` from the menu, then enter thresholds when prompted
/// (place ints and/or percentages with `%`, space- or comma-separated),
/// e.g. `1 5 10 90% 95%`.
/// At the end, enter a streak id for details, `csv` to dump `/tmp/finish_streaks.csv`, or `q`.

import "dart:io";

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const String kDefaultThresholds = "5 90%";
const int kDefaultTopPerGroup = 10;
const int kStreakYear2025 = 2025;
const int kMinDivisionCompetitors = 5;
const String kDefaultCsvPath = "/tmp/finish_streaks.csv";

enum _StreakBound {
  in2025,
  active,
  allTime;

  String get label {
    switch (this) {
      case _StreakBound.in2025:
        return "In $kStreakYear2025";
      case _StreakBound.active:
        return "Currently Active";
      case _StreakBound.allTime:
        return "All Time";
    }
  }
}

enum _StreakKind {
  place,
  percent;

  String labelFor(num threshold) {
    switch (this) {
      case _StreakKind.place:
        return "Place ≤ ${threshold.toInt()}";
      case _StreakKind.percent:
        return "≥ ${threshold.toStringAsFixed(threshold == threshold.roundToDouble() ? 0 : 1)}%";
    }
  }
}

class _Threshold {
  _Threshold.place(this.value) : kind = _StreakKind.place;
  _Threshold.percent(this.value) : kind = _StreakKind.percent;

  final _StreakKind kind;
  final double value;

  String get label => kind.labelFor(value);

  bool qualifies(_Finish f) {
    switch (kind) {
      case _StreakKind.place:
        return f.place > 0 && f.place <= value.toInt();
      case _StreakKind.percent:
        return f.percentage >= value;
    }
  }
}

class _Finish {
  _Finish({
    required this.date,
    required this.matchName,
    required this.place,
    required this.percentage,
    required this.matchId,
  });

  final DateTime date;
  final String matchName;
  final int place;
  final double percentage;
  final String matchId;

  String get dateLabel => date.toIso8601String().split("T").first;
}

class _Streak {
  _Streak({
    required this.finishes,
    required this.groupName,
    required this.rating,
    required this.threshold,
    required this.bound,
  });

  final List<_Finish> finishes;
  final String groupName;
  final ShooterRating rating;
  final _Threshold threshold;
  final _StreakBound bound;

  String get shooterName => rating.getName();
  String get memberNumber => rating.memberNumber;

  int get length => finishes.length;
  DateTime get firstDate => finishes.first.date;
  DateTime get lastDate => finishes.last.date;
}

class _ShooterStreakState {
  _ShooterStreakState({required this.rating});

  final ShooterRating rating;
  final List<_Finish> currentRun = [];
  /// Completed runs (broken by a non-qualifying counting finish), plus the
  /// final open run after [finalize]. Multiple runs per shooter can make top-K.
  final List<List<_Finish>> completedRuns = [];
  _Finish? lastCountingFinish;

  void onQualifying(_Finish finish) {
    currentRun.add(finish);
    lastCountingFinish = finish;
  }

  void onNonQualifying(_Finish finish) {
    _commitCurrent();
    currentRun.clear();
    lastCountingFinish = finish;
  }

  void finalize() {
    _commitCurrent();
  }

  void _commitCurrent() {
    if (currentRun.isNotEmpty) {
      completedRuns.add([...currentRun]);
    }
  }

  /// Candidate streak finish lists for [bound]. All-time / 2025 emit every
  /// completed run; active emits only the trailing open run when eligible.
  List<List<_Finish>> runsFor(
    _StreakBound bound,
    _Threshold threshold,
    int currentYear,
  ) {
    switch (bound) {
      case _StreakBound.allTime:
      case _StreakBound.in2025:
        return [
          for (final run in completedRuns)
            if (run.isNotEmpty) run,
        ];
      case _StreakBound.active:
        final last = lastCountingFinish;
        if (last == null) {
          return const [];
        }
        if (last.date.year != currentYear) {
          return const [];
        }
        if (!threshold.qualifies(last)) {
          return const [];
        }
        if (currentRun.isEmpty) {
          return const [];
        }
        return [
          [...currentRun],
        ];
    }
  }
}

class _GroupStreakTracker {
  _GroupStreakTracker({
    required this.groupName,
    required this.group,
    required this.thresholds,
    required this.currentYear,
  });

  final String groupName;
  final RatingGroup group;
  final List<_Threshold> thresholds;
  final int currentYear;

  late final List<Map<_StreakBound, Map<int, _ShooterStreakState>>> _states = [
    for (var i = 0; i < thresholds.length; i++)
      {for (final bound in _StreakBound.values) bound: <int, _ShooterStreakState>{}},
  ];

  void onMatch({
    required AnalystDatabase db,
    required DbRatingProject project,
    required DbShootingMatch dbMatch,
    required String matchId,
    required List<DbMatchEntry> divisionEntries,
    required void Function() onUnmapped,
  }) {
    if (divisionEntries.length < kMinDivisionCompetitors) {
      return;
    }

    final scored = <({DbMatchEntry entry, _Finish finish})>[];
    for (final entry in divisionEntries) {
      final score = entry.precalculatedScore;
      if (score == null || score.place <= 0) {
        continue;
      }
      scored.add((
        entry: entry,
        finish: _Finish(
          date: dbMatch.date,
          matchName: dbMatch.eventName,
          place: score.place,
          percentage: score.percentage,
          matchId: matchId,
        ),
      ));
    }

    for (var ti = 0; ti < thresholds.length; ti++) {
      final threshold = thresholds[ti];
      for (final bound in _StreakBound.values) {
        if (bound == _StreakBound.in2025 && dbMatch.date.year != kStreakYear2025) {
          continue;
        }

        final stateMap = _states[ti][bound]!;
        final toProcess = <({DbMatchEntry entry, _Finish finish})>[];
        final seenEntryIds = <int>{};

        for (final row in scored) {
          var include = threshold.qualifies(row.finish);
          if (!include) {
            for (final state in stateMap.values) {
              if (state.currentRun.isNotEmpty &&
                  _entryMayMatchRating(row.entry, state.rating)) {
                include = true;
                break;
              }
            }
          }
          if (include && seenEntryIds.add(row.entry.entryId)) {
            toProcess.add(row);
          }
        }

        for (final row in toProcess) {
          final dbRating = _lookupRating(db, project, group, row.entry);
          if (dbRating == null) {
            onUnmapped();
            continue;
          }
          final wrapped = project.wrapDbRatingSync(dbRating);
          final state = stateMap.putIfAbsent(
            dbRating.id,
            () => _ShooterStreakState(rating: wrapped),
          );

          if (threshold.qualifies(row.finish)) {
            state.onQualifying(row.finish);
          }
          else {
            state.onNonQualifying(row.finish);
          }
        }
      }
    }
  }

  void finalizeAll() {
    for (final byBound in _states) {
      for (final stateMap in byBound.values) {
        for (final state in stateMap.values) {
          state.finalize();
        }
      }
    }
  }

  List<_Streak> topStreaks({
    required _Threshold threshold,
    required int thresholdIndex,
    required _StreakBound bound,
    required int topK,
  }) {
    final stateMap = _states[thresholdIndex][bound]!;
    final streaks = <_Streak>[];
    for (final state in stateMap.values) {
      for (final finishes in state.runsFor(bound, threshold, currentYear)) {
        streaks.add(_Streak(
          finishes: finishes,
          groupName: groupName,
          rating: state.rating,
          threshold: threshold,
          bound: bound,
        ));
      }
    }
    streaks.sort((a, b) {
      final byLen = b.length.compareTo(a.length);
      if (byLen != 0) {
        return byLen;
      }
      return b.lastDate.compareTo(a.lastDate);
    });
    return streaks.take(topK).toList();
  }

  int get trackedShooterSlots {
    var count = 0;
    for (final byBound in _states) {
      for (final stateMap in byBound.values) {
        count += stateMap.length;
      }
    }
    return count;
  }
}

class FinishStreaksCommand extends DbOneoffCommand {
  FinishStreaksCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "STR";

  @override
  final String title = "Finish Streaks (Place / %)";

  @override
  String? get description =>
      "Longest place and percentage streaks in L2s Main LLR per division group "
      "(excludes multi-division groups like LO/CO). Thresholds: ints = place ≤ N; "
      "N% = percentage ≥ N. Bounds: 2025, currently active, all-time. "
      "Requires ≥$kMinDivisionCompetitors division entries for a match to count. "
      "Optional top-K arg; prompts for thresholds (space- or comma-separated).";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Top K",
          defaultValue: kDefaultTopPerGroup,
          description: "Top streaks per group × threshold × bound (default $kDefaultTopPerGroup).",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final topK = arguments
            .firstWhereOrNull((a) => a.argument.label == "Top K")
            ?.getAs<int>() ??
        kDefaultTopPerGroup;
    if (topK < 1) {
      console.print("Top K must be at least 1 (got: $topK).");
      return;
    }

    console.print(
      "Thresholds: place ints (≤ N) and percentages with % (≥ N). "
      "Space- or comma-separated. Default: $kDefaultThresholds",
    );
    console.print("Top $topK per group × threshold × bound.");
    console.write("Thresholds [$kDefaultThresholds]: ");
    final line = console.readLine(cancelOnBreak: true, cancelOnEOF: true);
    if (line == null) {
      return;
    }
    final raw = line.trim().isEmpty ? kDefaultThresholds : line.trim();
    final thresholds = _parseThresholds(raw);
    if (thresholds == null) {
      console.print("Could not parse thresholds from: $raw");
      console.print("Example: 1 5 10 90% 95%");
      return;
    }
    if (thresholds.isEmpty) {
      console.print("No thresholds provided.");
      return;
    }

    await _run(db, console, thresholds: thresholds, topPerGroup: topK);
  }
}

List<_Threshold>? _parseThresholds(String raw) {
  final tokens = raw
      .split(RegExp(r"[\s,]+"))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  final out = <_Threshold>[];
  for (final token in tokens) {
    if (token.endsWith("%")) {
      final numStr = token.substring(0, token.length - 1).trim();
      final v = double.tryParse(numStr);
      if (v == null || v <= 0 || v > 100) {
        return null;
      }
      out.add(_Threshold.percent(v));
    }
    else {
      final v = int.tryParse(token);
      if (v == null || v < 1) {
        return null;
      }
      out.add(_Threshold.place(v.toDouble()));
    }
  }
  return out;
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required List<_Threshold> thresholds,
  required int topPerGroup,
}) async {
  final project = await db.getRatingProjectByName(kDefaultLlrProjectName);
  if (project == null) {
    console.print("Rating project not found: $kDefaultLlrProjectName");
    return;
  }
  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final groups = project.groups
      .where((g) => g.divisionNames.length == 1)
      .sorted((a, b) => a.sortOrder.compareTo(b.sortOrder))
      .toList();

  final currentYear = DateTime.now().year;
  final trackers = {
    for (final g in groups)
      g.name: _GroupStreakTracker(
        groupName: g.name,
        group: g,
        thresholds: thresholds,
        currentYear: currentYear,
      ),
  };

  console.print("Project: $kDefaultLlrProjectName");
  console.print(
    "Thresholds: ${thresholds.map((t) => t.label).join("; ")}",
  );
  console.print(
    "Groups: ${groups.map((g) => g.name).join(", ")} "
    "(single-division only; LO/CO combined excluded)",
  );
  console.print(
    "Counting match: ≥$kMinDivisionCompetitors non-DQ division entries; "
    "smaller matches skipped (no break).",
  );
  console.print(
    "Streak break: non-qualifying finish at a counting match. "
    "Active = trailing run through most recent counting match in $currentYear.",
  );
  console.print(
    "Scan: match-first online streak tracking "
    "(rating lookup only for qualifiers + active streak holders).",
  );
  console.print("Top $topPerGroup per group × threshold × bound.\n");

  final pointers = [...project.matchPointers]
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  var loadErrors = 0;
  var missingScores = 0;
  var unmappedEntries = 0;
  var divisionEntries = 0;
  var skippedSmallMatches = 0;

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    canHaveErrors: true,
    initialLabel: "Scanning project matches…",
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

    List<DbMatchEntry> entries;
    if (dbMatch.shootersStoredSeparately) {
      entries = dbMatch.shooterLinks.map((e) => e.intoDbMatchEntry()).toList();
    }
    else {
      entries = dbMatch.shooters;
    }

    final matchId = dbMatch.sourceIds.isNotEmpty ? dbMatch.sourceIds.first : ptr.sourceIds.first;

    for (final group in groups) {
      final divisionName = group.divisionNames.single;
      final groupEntries = entries.where((e) => !e.dq && e.divisionName == divisionName).toList();
      if (groupEntries.isEmpty) {
        continue;
      }

      divisionEntries += groupEntries.length;
      if (groupEntries.length < kMinDivisionCompetitors) {
        skippedSmallMatches++;
        continue;
      }

      for (final entry in groupEntries) {
        final score = entry.precalculatedScore;
        if (score == null || score.place <= 0) {
          missingScores++;
        }
      }

      trackers[group.name]!.onMatch(
        db: db,
        project: project,
        dbMatch: dbMatch,
        matchId: matchId,
        divisionEntries: groupEntries,
        onUnmapped: () => unmappedEntries++,
      );
    }
  }

  bar.complete();

  for (final tracker in trackers.values) {
    tracker.finalizeAll();
  }

  console.print(
    "Scanned ${pointers.length} matches ($loadErrors load errors). "
    "Division entries: $divisionEntries. "
    "Skipped <$kMinDivisionCompetitors entries: $skippedSmallMatches group-matches. "
    "Unmapped to project rating: $unmappedEntries. "
    "Missing precalculated score: $missingScores.\n",
  );

  final catalog = <int, _Streak>{};
  var nextId = 1;

  for (final group in groups) {
    final tracker = trackers[group.name]!;
    if (tracker.trackedShooterSlots == 0) {
      console.print("${group.name}: no streak state recorded.");
      continue;
    }

    console.print("\n========== ${group.name} ==========");

    for (var ti = 0; ti < thresholds.length; ti++) {
      final threshold = thresholds[ti];
      for (final bound in _StreakBound.values) {
        final top = tracker.topStreaks(
          threshold: threshold,
          thresholdIndex: ti,
          bound: bound,
          topK: topPerGroup,
        );
        if (top.isEmpty) {
          continue;
        }

        console.print("\n--- ${group.name} | ${threshold.label} | ${bound.label} ---");
        for (final streak in top) {
          final id = nextId++;
          catalog[id] = streak;
          final first = streak.finishes.first.dateLabel;
          final last = streak.finishes.last.dateLabel;
          console.print(
            "  [$id]  len=${streak.length.toString().padLeft(3)}  "
            "${_padName(streak.shooterName, 28)}  "
            "${streak.memberNumber.padRight(12)}  "
            "$first → $last",
          );
        }
      }
    }
  }

  if (catalog.isEmpty) {
    console.print("\nNo streaks found.");
    return;
  }

  console.print(
    "\n${catalog.length} streaks listed. Enter a number for match details, "
    "csv to dump $kDefaultCsvPath, or q to return.",
  );
  await _drillDownLoop(console, catalog);
}

bool _entryMayMatchRating(DbMatchEntry entry, ShooterRating rating) {
  final entryNumbers = _memberNumberCandidates(entry).toSet();
  if (entryNumbers.contains(rating.memberNumber)) {
    return true;
  }
  for (final n in rating.allPossibleMemberNumbers) {
    if (entryNumbers.contains(n)) {
      return true;
    }
  }
  return false;
}

Iterable<String> _memberNumberCandidates(DbMatchEntry entry) sync* {
  final seen = <String>{};
  for (final candidate in [
    entry.memberNumber,
    entry.originalMemberNumber,
    ...entry.knownMemberNumbers,
  ]) {
    final t = candidate.trim();
    if (t.isEmpty || t == "(invalid)") {
      continue;
    }
    if (seen.add(t)) {
      yield t;
    }
  }
}

DbShooterRating? _lookupRating(
  AnalystDatabase db,
  DbRatingProject project,
  RatingGroup group,
  DbMatchEntry entry,
) {
  for (final mn in _memberNumberCandidates(entry)) {
    final dbRating = db.maybeKnownShooterSync(
      project: project,
      group: group,
      memberNumber: mn,
      usePossibleMemberNumbers: true,
    );
    if (dbRating != null) {
      return dbRating;
    }
  }
  return null;
}

Future<void> _drillDownLoop(Console console, Map<int, _Streak> catalog) async {
  while (true) {
    console.write("> ");
    final line = console.readLine(cancelOnBreak: true, cancelOnEOF: true);
    if (line == null) {
      return;
    }
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (trimmed.toLowerCase() == "q") {
      return;
    }
    if (trimmed.toLowerCase() == "csv") {
      final path = _writeStreaksCsv(catalog);
      console.print("Wrote ${catalog.length} streaks to $path");
      continue;
    }
    final id = int.tryParse(trimmed);
    if (id == null || !catalog.containsKey(id)) {
      console.print("Enter a listed streak number, csv, or q to return.");
      continue;
    }
    _printStreakDetail(console, id, catalog[id]!);
  }
}

String _padName(String name, int width) {
  if (name.length > width) {
    return name.substring(0, width);
  }
  return name.padRight(width);
}

void _printStreakDetail(Console console, int id, _Streak streak) {
  console.print(
    "\n[$id] ${streak.groupName} | ${streak.threshold.label} | ${streak.bound.label}",
  );
  console.print(
    "  ${streak.shooterName} (${streak.memberNumber}) — ${streak.length} matches",
  );
  console.print("  #  date        place   pct    event");
  for (var i = 0; i < streak.finishes.length; i++) {
    final f = streak.finishes[i];
    console.print(
      "  ${(i + 1).toString().padLeft(2)} ${f.dateLabel}  "
      "${f.place.toString().padLeft(5)}  "
      "${f.percentage.toStringAsFixed(1).padLeft(5)}%  "
      "${f.matchName}",
    );
  }
  console.print("");
}

String _writeStreaksCsv(Map<int, _Streak> catalog) {
  final buf = StringBuffer()
    ..writeln(
      "streak_id,group,threshold_kind,threshold,bound,streak_length,"
      "rating_id,member_number,name,first_date,last_date,"
      "match_seq,match_date,place,percentage,event,match_id",
    );

  final ids = catalog.keys.toList()..sort();
  for (final id in ids) {
    final streak = catalog[id]!;
    final thresholdKind = streak.threshold.kind == _StreakKind.place ? "place" : "percent";
    final thresholdValue = streak.threshold.kind == _StreakKind.place
        ? streak.threshold.value.toInt().toString()
        : streak.threshold.value.toString();
    final firstDate = streak.finishes.first.dateLabel;
    final lastDate = streak.finishes.last.dateLabel;
    for (var i = 0; i < streak.finishes.length; i++) {
      final f = streak.finishes[i];
      buf.writeln(
        "$id,"
        "${_csvCell(streak.groupName)},"
        "$thresholdKind,"
        "$thresholdValue,"
        "${_csvCell(streak.bound.label)},"
        "${streak.length},"
        "${streak.rating.wrappedRating.id},"
        "${_csvCell(streak.memberNumber)},"
        "${_csvCell(streak.shooterName)},"
        "$firstDate,"
        "$lastDate,"
        "${i + 1},"
        "${f.dateLabel},"
        "${f.place},"
        "${f.percentage},"
        "${_csvCell(f.matchName)},"
        "${_csvCell(f.matchId)}",
      );
    }
  }

  final file = File(kDefaultCsvPath);
  file.writeAsStringSync(buf.toString());
  return file.path;
}

String _csvCell(String value) {
  return value.replaceAll(",", " ").replaceAll("\n", " ").replaceAll("\r", "");
}
