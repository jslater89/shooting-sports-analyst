/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Distinct Area 1–8 championship winners per single-division L2s Main LLR
/// group, from 2017 (LLR start) through the present.
///
/// Launch: dart run bin/db_oneoffs.dart DAC

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const int kStartYear = 2017;

/// User-specified filter for Area 1–8 match names.
final RegExp kAreaMatchPattern = RegExp(r"Area\s+[1-8]\b", caseSensitive: false);
final RegExp kAreaNumberPattern = RegExp(r"Area\s+([1-8])\b", caseSensitive: false);
final RegExp kSectionalPattern = RegExp(r"Sectional", caseSensitive: false);

class DistinctAreaChampionsCommand extends DbOneoffCommand {
  DistinctAreaChampionsCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "DAC";

  @override
  final String title = "Distinct Area Champions since 2017";

  @override
  String? get description =>
      "Counts distinct Area 1–8 championship winners per single-division "
      "L2s Main LLR group from $kStartYear onward.";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _run(db, console, projectName: kDefaultLlrProjectName);
  }
}

class _Win {
  _Win({
    required this.matchName,
    required this.date,
    required this.area,
    required this.competitors,
  });

  final String matchName;
  final DateTime date;
  final int? area;
  final int competitors;

  String get dateLabel => date.toIso8601String().split("T").first;
}

class _Champion {
  _Champion({required this.identity});

  final Shooter identity;
  final List<_Win> wins = [];

  String get memberNumber => identity.memberNumber;
  String get name => identity.getName(suffixes: false);
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
      .where((p) => p.date != null && p.date!.year >= kStartYear)
      .where((p) => kAreaMatchPattern.hasMatch(p.name))
      .where((p) => !kSectionalPattern.hasMatch(p.name))
      .toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  if (pointers.isEmpty) {
    console.print(
      "No Area 1–8 matches found in $projectName from $kStartYear onward.",
    );
    return;
  }

  final buf = StringBuffer()
    ..writeln("Project: $projectName")
    ..writeln("Window: match date year >= $kStartYear")
    ..writeln("Match name filter: ${kAreaMatchPattern.pattern} (excluding Sectional)")
    ..writeln("Groups: single-division only (${groups.map((g) => g.uiLabel).join(", ")})")
    ..writeln("Identity: rating lookup with resolveMemberNumberCorrection, then equalsShooter(allPossibleMemberNumbers: true)")
    ..writeln("Champion: place 1 after getScoresFromFilters (non-DQ, respect reentry filter)")
    ..writeln("")
    ..writeln("Area matches (${pointers.length}):");

  for (final ptr in pointers) {
    final dateStr = ptr.date?.toIso8601String().split("T").first ?? "?";
    final area = _areaNumber(ptr.name);
    final areaLabel = area != null ? "Area $area" : "Area ?";
    buf.writeln("  $dateStr  $areaLabel  ${ptr.name}");
  }
  buf.writeln("");

  console.print(buf.toString());

  final championsByGroup = {
    for (final g in groups) g.uiLabel: <_Champion>[],
  };
  final championshipsByGroup = {
    for (final g in groups) g.uiLabel: 0,
  };
  final emptyDivisionByGroup = {
    for (final g in groups) g.uiLabel: 0,
  };
  final unmappedWinsByGroup = {
    for (final g in groups) g.uiLabel: 0,
  };

  var loadErrors = 0;
  var hydrateErrors = 0;

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    canHaveErrors: true,
    initialLabel: "Processing Area matches…",
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
    final area = _areaNumber(ptr.name) ?? _areaNumber(shootingMatch.name);

    for (final group in groups) {
      final scores = shootingMatch.getScoresFromFilters(group.filters);
      final eligible = <MapEntry<MatchEntry, RelativeMatchScore>>[];
      for (final entry in scores.entries) {
        final matchEntry = entry.key;
        if (matchEntry.dq) {
          continue;
        }
        if (!group.filters.reentries && matchEntry.reentry) {
          continue;
        }
        eligible.add(entry);
      }

      if (eligible.isEmpty) {
        emptyDivisionByGroup[group.uiLabel] = emptyDivisionByGroup[group.uiLabel]! + 1;
        continue;
      }

      final winners = eligible.where((e) => e.value.place == 1).toList();
      if (winners.isEmpty) {
        eligible.sort((a, b) => a.value.place.compareTo(b.value.place));
        winners.add(eligible.first);
      }

      championshipsByGroup[group.uiLabel] = championshipsByGroup[group.uiLabel]! + 1;
      final champions = championsByGroup[group.uiLabel]!;
      final win = _Win(
        matchName: shootingMatch.name,
        date: shootingMatch.date,
        area: area,
        competitors: eligible.length,
      );

      for (final winner in winners) {
        final dbRating = _lookupRating(db, project, group, winner.key);
        final Shooter identity;
        if (dbRating != null) {
          identity = project.wrapDbRatingSync(dbRating);
        }
        else {
          unmappedWinsByGroup[group.uiLabel] = unmappedWinsByGroup[group.uiLabel]! + 1;
          identity = winner.key;
        }
        _addWin(champions, identity, win);
      }
    }
  }

  bar.complete();

  final report = StringBuffer();
  report.writeln("=== Summary: distinct Area champions by division ===");
  for (final group in groups) {
    final label = group.uiLabel;
    final distinct = championsByGroup[label]!.length;
    final titles = championshipsByGroup[label]!;
    final empty = emptyDivisionByGroup[label]!;
    final unmapped = unmappedWinsByGroup[label]!;
    report.write("  ${label.padRight(22)}  $distinct distinct  ($titles titles");
    if (empty > 0) {
      report.write(", $empty empty");
    }
    if (unmapped > 0) {
      report.write(", $unmapped unmapped");
    }
    report.writeln(")");
  }
  report.writeln("");

  for (final group in groups) {
    final label = group.uiLabel;
    final champions = [...championsByGroup[label]!]
      ..sort((a, b) {
        final byWins = b.wins.length.compareTo(a.wins.length);
        if (byWins != 0) {
          return byWins;
        }
        return a.name.compareTo(b.name);
      });

    report.writeln(
      "=== $label (${champions.length} distinct, "
      "${championshipsByGroup[label]} titles) ===",
    );
    if (champions.isEmpty) {
      report.writeln("  (none)");
      report.writeln("");
      continue;
    }

    for (final champion in champions) {
      champion.wins.sort((a, b) => a.date.compareTo(b.date));
      final winSummary = champion.wins.map((w) {
        final area = w.area != null ? "A${w.area}" : "?";
        return "${w.date.year} $area";
      }).join(", ");
      report.writeln(
        "  ${_pad(champion.memberNumber, 12)}  "
        "${_pad(champion.name, 28)}  "
        "${champion.wins.length.toString().padLeft(2)} wins  "
        "$winSummary",
      );
    }
    report.writeln("");
  }

  report.writeln(
    "Processed ${pointers.length} matches "
    "($loadErrors load errors, $hydrateErrors hydrate errors).",
  );

  console.print(report.toString());
}

void _addWin(List<_Champion> champions, Shooter identity, _Win win) {
  final existing = champions.firstWhereOrNull(
    (c) => c.identity.equalsShooter(identity, allPossibleMemberNumbers: true),
  );
  if (existing != null) {
    existing.wins.add(win);
    if (existing.identity is! ShooterRating && identity is ShooterRating) {
      champions[champions.indexOf(existing)] = _Champion(identity: identity)
        ..wins.addAll(existing.wins);
    }
  }
  else {
    champions.add(_Champion(identity: identity)..wins.add(win));
  }
}

int? _areaNumber(String name) {
  final m = kAreaNumberPattern.firstMatch(name);
  if (m == null) {
    return null;
  }
  return int.tryParse(m.group(1)!);
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

DbShooterRating? _lookupRating(
  AnalystDatabase db,
  DbRatingProject project,
  RatingGroup group,
  MatchEntry entry,
) {
  final processNumber = project.sport.shooterDeduplicator?.processNumber
      ?? Shooter.normalizeNumber;
  final lookupNumbers = <String>{};
  for (final mn in _memberNumberCandidates(entry)) {
    lookupNumbers.add(mn);
    final processed = processNumber(mn);
    if (processed.isNotEmpty) {
      lookupNumbers.add(processed);
      final corrected = project.settings.resolveMemberNumberCorrection(
        entry.name,
        processed,
      );
      if (corrected != null && corrected.isNotEmpty) {
        lookupNumbers.add(corrected);
      }
    }
  }

  for (final mn in lookupNumbers) {
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

String _pad(String value, int width) {
  if (value.length > width) {
    return value.substring(0, width);
  }
  return value.padRight(width);
}
