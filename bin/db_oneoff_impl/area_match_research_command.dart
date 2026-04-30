/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Finds USPSA Area 1–8 matches for a year from the L2s Main LLR project.
/// Each match is hydrated to a [ShootingMatch]; for every [RatingGroup] on the
/// project, scores are computed with [ShootingMatch.getScoresFromFilters] using
/// that group's division filters. Rows meeting the minimum finish ratio (score
/// vs winner within that group's competitor pool) contribute distinct
/// [DbShooterRating.id] counts per group.
///
/// Ratio is score relative to the division winner (see [BareRelativeScore.ratio]).

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";

/// Names like "2024 Area 4 Championship" or "GLOCK Area 6 Championship".
final RegExp _areaNumberPattern = RegExp(r"Area\s+([1-8])\b", caseSensitive: false);

class AreaMatchResearchCommand extends DbOneoffCommand {
  AreaMatchResearchCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "AMR";

  @override
  final String title = "Area Match Research (LLR)";

  @override
  String? get description =>
      "Lists Area 1–8 matches from L2s Main LLR for a year and counts distinct "
      "rating ids per rating group using hydrated scores and group division filters.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Year",
          required: true,
          description: "Calendar year (match date must fall in this year).",
        ),
        StringMenuArgument(
          label: "Finish ratio",
          required: true,
          description: "Minimum match ratio vs division winner, e.g. 0.8 for 80%.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final yearVal = arguments.firstWhereOrNull((a) => a.argument.label == "Year")?.getAs<int>();
    final ratioArg = arguments.firstWhereOrNull((a) => a.argument.label == "Finish ratio");
    final ratioRaw = ratioArg?.getAs<String>().trim();
    if (yearVal == null) {
      console.print("Missing Year argument.");
      return;
    }
    if (ratioRaw == null || ratioRaw.isEmpty) {
      console.print("Missing Finish ratio argument.");
      return;
    }
    final finishRatio = double.tryParse(ratioRaw);
    if (finishRatio == null) {
      console.print("Finish ratio must be a decimal number (got: $ratioRaw).");
      return;
    }
    if (finishRatio <= 0 || finishRatio > 1.0) {
      console.print("Finish ratio should be in (0, 1], e.g. 0.85 for 85% (got: $finishRatio).");
      return;
    }

    await _run(
      db,
      console,
      projectName: kDefaultLlrProjectName,
      year: yearVal,
      finishRatio: finishRatio,
    );
  }
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required int year,
  required double finishRatio,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }

  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final ratingGroups = [...project.groups]..sort((a, b) {
      final o = a.sortOrder.compareTo(b.sortOrder);
      if (o != 0) {
        return o;
      }
      return a.name.compareTo(b.name);
    });

  final pointers = project.matchPointers
      .where((p) => p.date != null && p.date!.year == year)
      .where((p) => _areaNumberPattern.hasMatch(p.name))
      .toList();

  final byArea = <int, List<MatchPointer>>{};
  for (final p in pointers) {
    final m = _areaNumberPattern.firstMatch(p.name);
    if (m == null) {
      continue;
    }
    final area = int.parse(m.group(1)!);
    byArea.putIfAbsent(area, () => []).add(p);
  }

  if (byArea.isEmpty) {
    console.print("No Area 1–8 matches found in $projectName for year $year.");
    return;
  }

  for (final entry in byArea.entries) {
    entry.value.sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));
  }

  final buf = StringBuffer()
    ..writeln("Project: $projectName")
    ..writeln("Year: $year")
    ..writeln(
      "Minimum finish ratio (vs winner within each rating group): ${finishRatio} "
      "(${(finishRatio * 100).toStringAsFixed(1)}%)",
    )
    ..writeln("(Scores from hydrated match + getScoresFromFilters per group.)")
    ..writeln("");

  final distinctRatingIds = <int>{};
  var entriesMeetingRatio = 0;

  final entriesByGroup = <String, int>{};
  final distinctIdsByGroup = <String, Set<int>>{};

  final perArea = <int, _AreaAccumulator>{};

  for (final area in byArea.keys.sorted((a, b) => a.compareTo(b))) {
    final ptrs = byArea[area]!;
    if (ptrs.length > 1) {
      buf.writeln("Warning: Area $area has ${ptrs.length} pointers in project; using the first for this area.");
    }
    final ptr = ptrs.first;
    final res = await ptr.getDbMatch(db, downloadIfMissing: false);
    if (res.isErr()) {
      buf.writeln(
        "Area $area: could not load match (${ptr.name}): ${res.unwrapErr().message}",
      );
      continue;
    }
    final dbMatch = res.unwrap();
    if (dbMatch.shootersStoredSeparately) {
      await dbMatch.shooterLinks.load();
    }

    final hydrated = await dbMatch.hydrate();
    if (hydrated.isErr()) {
      buf.writeln(
        "Area $area: hydrate failed (${dbMatch.eventName}): ${hydrated.unwrapErr()}",
      );
      continue;
    }
    final shootingMatch = hydrated.unwrap();

    final dateStr = shootingMatch.date.toIso8601String().split("T").first;
    final areaHeader = "Area $area: ${shootingMatch.name} ($dateStr)";
    buf.writeln("$areaHeader — ${shootingMatch.shooters.length} roster entries");

    final areaAcc = perArea.putIfAbsent(
      area,
      () => _AreaAccumulator(areaHeader),
    );

    for (final rg in ratingGroups) {
      final scores = shootingMatch.getScoresFromFilters(rg.filters);
      for (final entry in scores.entries) {
        final matchEntry = entry.key;
        final rel = entry.value;
        if (matchEntry.dq) {
          continue;
        }
        if (!rg.filters.reentries && matchEntry.reentry) {
          continue;
        }
        if (rel.ratio < finishRatio) {
          continue;
        }
        entriesMeetingRatio++;
        final groupLabel = rg.uiLabel;
        entriesByGroup[groupLabel] = (entriesByGroup[groupLabel] ?? 0) + 1;

        final ratingId = _ratingIdForGroup(db, project, rg, matchEntry);
        if (ratingId != null) {
          distinctRatingIds.add(ratingId);
          distinctIdsByGroup.putIfAbsent(groupLabel, () => <int>{}).add(ratingId);
        }

        areaAcc.addEntry(groupLabel, ratingId);
      }
    }
  }

  buf.writeln("");

  buf.writeln("Per area match:");
  for (final area in perArea.keys.sorted((a, b) => a.compareTo(b))) {
    final acc = perArea[area]!;
    buf.writeln("  ${acc.headerLine}");
    buf.writeln("    Entries meeting ratio: ${acc.totalEntries}");
    buf.writeln("    Distinct DbShooterRating ids: ${acc.allDistinctIds.length}");
    buf.writeln("    By rating group:");
    for (final name in acc.sortedGroupNames()) {
      final ent = acc.entriesByGroup[name] ?? 0;
      final dist = acc.distinctIdsByGroup[name]?.length ?? 0;
      buf.writeln("      $name — entries: $ent; distinct ids: $dist");
    }
    buf.writeln("");
  }

  final groupNames = entriesByGroup.keys.sorted();

  buf.writeln("By rating group (all areas combined):");
  for (final name in groupNames) {
    final entries = entriesByGroup[name] ?? 0;
    final distinct = distinctIdsByGroup[name]?.length ?? 0;
    buf.writeln(
      "  $name — entries meeting ratio: $entries; distinct DbShooterRating ids: $distinct",
    );
  }

  buf
    ..writeln("")
    ..writeln("Totals (all areas)")
    ..writeln(
      "Entries meeting ratio (non-DQ, respect group reentry filter): $entriesMeetingRatio",
    )
    ..writeln("Distinct DbShooterRating ids (wrappedRating.id): ${distinctRatingIds.length}");

  if (byArea.length != 8) {
    buf.writeln("");
    buf.writeln(
      "Note: Found ${byArea.length} distinct area numbers (${byArea.keys.sorted((a, b) => a.compareTo(b)).join(", ")}), not 8.",
    );
  }

  final text = buf.toString();
  console.print(text);
}

/// Rolls up counts for one area championship match.
final class _AreaAccumulator {
  _AreaAccumulator(this.headerLine);

  final String headerLine;

  final Map<String, int> entriesByGroup = {};
  final Map<String, Set<int>> distinctIdsByGroup = {};

  void addEntry(String groupLabel, int? ratingId) {
    entriesByGroup[groupLabel] = (entriesByGroup[groupLabel] ?? 0) + 1;
    if (ratingId != null) {
      distinctIdsByGroup.putIfAbsent(groupLabel, () => <int>{}).add(ratingId);
    }
  }

  int get totalEntries =>
      entriesByGroup.values.fold<int>(0, (sum, n) => sum + n);

  Set<int> get allDistinctIds =>
      distinctIdsByGroup.values.expand((s) => s).toSet();

  List<String> sortedGroupNames() => [...entriesByGroup.keys]..sort();
}

Iterable<String> _memberNumberCandidates(MatchEntry entry) sync* {
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

int? _ratingIdForGroup(
  AnalystDatabase db,
  DbRatingProject project,
  RatingGroup group,
  MatchEntry entry,
) {
  for (final mn in _memberNumberCandidates(entry)) {
    final dbRating = db.maybeKnownShooterSync(
      project: project,
      group: group,
      memberNumber: mn,
      usePossibleMemberNumbers: true,
    );
    if (dbRating != null) {
      return dbRating.id;
    }
  }
  return null;
}
