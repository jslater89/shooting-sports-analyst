/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Shooters with ≥95% at any L2s Main LLR Nationals match (name contains
/// "National", excludes "IPSC" and "Shooting International"), per single-division rating group.

import "dart:io";
import "dart:math";

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
const double kMinFinishPercentage = 95.0;
const String kDefaultCsvPath = "/tmp/dgm_nationals_95pct.csv";
const String kOpenGroupUuid = "uspsa-open";

/// Name markers for Open Nationals (excludes bump-to-Open at other division nationals).
const List<String> kOpenNationalNameMarkers = [
  "open",
  "hi-cap",
  "hicap",
  "racegun",
  "race gun",
];

bool _isNationalPointer(MatchPointer pointer) {
  final nameLower = pointer.name.toLowerCase();
  return nameLower.contains("national")
      && !nameLower.contains("ipsc")
      && !nameLower.contains("shooting international");
}

bool _isOpenNationalPointer(MatchPointer pointer) {
  if (!_isNationalPointer(pointer)) {
    return false;
  }
  final nameLower = pointer.name.toLowerCase();
  return kOpenNationalNameMarkers.any(nameLower.contains);
}

bool _groupCountsMatch(RatingGroup group, MatchPointer pointer) {
  if (group.uuid == kOpenGroupUuid) {
    return _isOpenNationalPointer(pointer);
  }
  return _isNationalPointer(pointer);
}

class _QualifyingFinish {
  _QualifyingFinish({
    required this.matchName,
    required this.date,
    required this.percentage,
    required this.place,
  });

  final String matchName;
  final DateTime date;
  final double percentage;
  final int place;

  String get dateLabel => date.toIso8601String().split("T").first;
}

class _ShooterQualification {
  _ShooterQualification({required this.rating});

  final ShooterRating rating;
  final List<_QualifyingFinish> finishes = [];

  String get memberNumber => rating.memberNumber;
  String get name => rating.getName();

  double get bestPercentage =>
      finishes.isEmpty ? 0 : finishes.map((f) => f.percentage).reduce(max);
}

class DistinguishedGrandmasterCommand extends DbOneoffCommand {
  DistinguishedGrandmasterCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "DGM";

  @override
  final String title = "Distinguished Grandmaster (Nationals 95%)";

  @override
  String? get description =>
      "Lists shooters with ≥${kMinFinishPercentage.toStringAsFixed(0)}% at any "
      "L2s Main LLR match whose name contains National (excluding IPSC and "
      "Shooting International), per single-division group (LO/CO combined excluded). "
      "Open uses only Nationals whose name contains Open, HI-Cap/Hicap, or Race Gun. "
      "Deduplication via ShooterRating.equalsShooter(allPossibleMemberNumbers: true).";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _run(db, console);
  }
}

Future<void> _run(AnalystDatabase db, Console console) async {
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

  final pointers = project.matchPointers
      .where(_isNationalPointer)
      .toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  if (pointers.isEmpty) {
    console.print("No Nationals matches found in $kDefaultLlrProjectName.");
    return;
  }

  console.print("Project: $kDefaultLlrProjectName");
  console.print(
    "Matches: name contains National, excludes IPSC and Shooting International "
    "(${pointers.length} in project)",
  );
  console.print("Minimum finish: ≥${kMinFinishPercentage.toStringAsFixed(0)}% (precalculated division score)");
  console.print(
    "Identity: ShooterRating.equalsShooter(allPossibleMemberNumbers: true)",
  );
  console.print("Groups: ${groups.map((g) => g.name).join(", ")}\n");

  console.print("Nationals matches (all divisions except Open filter):");
  for (final ptr in pointers) {
    final dateStr = ptr.date?.toIso8601String().split("T").first ?? "?";
    console.print("  $dateStr  ${ptr.name}");
  }
  console.print("");

  final openNationals = pointers.where(_isOpenNationalPointer).toList();
  console.print(
    "Open Nationals matches (Open division only; "
    "name contains ${kOpenNationalNameMarkers.join(", ")}):",
  );
  if (openNationals.isEmpty) {
    console.print("  (none)");
  }
  else {
    for (final ptr in openNationals) {
      final dateStr = ptr.date?.toIso8601String().split("T").first ?? "?";
      console.print("  $dateStr  ${ptr.name}");
    }
  }
  console.print("");

  final qualifiersByGroup = {
    for (final g in groups) g.name: <_ShooterQualification>[],
  };

  var loadErrors = 0;
  var missingScores = 0;
  var qualifyingEntries = 0;
  var unmappedEntries = 0;

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

    List<DbMatchEntry> entries;
    if (dbMatch.shootersStoredSeparately) {
      entries = dbMatch.shooterLinks.map((e) => e.intoDbMatchEntry()).toList();
    }
    else {
      entries = dbMatch.shooters;
    }

    for (final group in groups) {
      if (!_groupCountsMatch(group, ptr)) {
        continue;
      }
      final divisionName = group.divisionNames.single;
      final qualifiers = qualifiersByGroup[group.name]!;

      for (final entry in entries) {
        if (entry.dq) {
          continue;
        }
        if (entry.divisionName != divisionName) {
          continue;
        }
        final score = entry.precalculatedScore;
        if (score == null || score.place <= 0) {
          missingScores++;
          continue;
        }
        if (score.percentage < kMinFinishPercentage) {
          continue;
        }

        final dbRating = _lookupRating(db, project, group, entry);
        if (dbRating == null) {
          unmappedEntries++;
          continue;
        }

        qualifyingEntries++;
        final wrapped = project.wrapDbRatingSync(dbRating);
        final finish = _QualifyingFinish(
          matchName: dbMatch.eventName,
          date: dbMatch.date,
          percentage: score.percentage,
          place: score.place,
        );
        _addQualifier(qualifiers, wrapped, finish);
      }
    }
  }

  bar.complete();

  final csv = StringBuffer()
    ..writeln(
      "group,rating_id,member_number,name,best_percentage,qualifying_matches,"
      "match_date,match_name,place,percentage",
    );

  for (final group in groups) {
    final shooters = [...qualifiersByGroup[group.name]!]
      ..sort((a, b) {
        final byPct = b.bestPercentage.compareTo(a.bestPercentage);
        if (byPct != 0) {
          return byPct;
        }
        return a.name.compareTo(b.name);
      });

    console.print("=== ${group.name} (${shooters.length} shooters) ===");
    if (shooters.isEmpty) {
      console.print("  (none)\n");
      continue;
    }

    for (final shooter in shooters) {
      shooter.finishes.sort((a, b) => a.date.compareTo(b.date));
      final matchSummary = shooter.finishes
          .map((f) => "${f.dateLabel} ${f.matchName} (${f.percentage.toStringAsFixed(1)}%)")
          .join("; ");
      console.print(
        "  ${shooter.memberNumber.padRight(12)}  "
        "${_padName(shooter.name, 28)}  "
        "best=${shooter.bestPercentage.toStringAsFixed(1)}%  "
        "$matchSummary",
      );

      for (final finish in shooter.finishes) {
        csv.writeln(
          "${_csvCell(group.name)},"
          "${shooter.rating.wrappedRating.id},"
          "${_csvCell(shooter.memberNumber)},"
          "${_csvCell(shooter.name)},"
          "${shooter.bestPercentage},"
          "${shooter.finishes.length},"
          "${finish.dateLabel},"
          "${_csvCell(finish.matchName)},"
          "${finish.place},"
          "${finish.percentage}",
        );
      }
    }
    console.print("");
  }

  final csvFile = File(kDefaultCsvPath);
  csvFile.writeAsStringSync(csv.toString());

  console.print(
    "Processed ${pointers.length} matches ($loadErrors load errors). "
    "Qualifying entries: $qualifyingEntries. "
    "Unmapped to project rating: $unmappedEntries. "
    "Entries missing precalculated score: $missingScores.",
  );
  console.print("Wrote $kDefaultCsvPath");
}

void _addQualifier(
  List<_ShooterQualification> qualifiers,
  ShooterRating rating,
  _QualifyingFinish finish,
) {
  final existing = qualifiers.firstWhereOrNull(
    (q) => q.rating.equalsShooter(rating, allPossibleMemberNumbers: true),
  );
  if (existing != null) {
    existing.finishes.add(finish);
  }
  else {
    qualifiers.add(_ShooterQualification(rating: rating)..finishes.add(finish));
  }
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

String _padName(String name, int width) {
  if (name.length > width) {
    return name.substring(0, width);
  }
  return name.padRight(width);
}

String _csvCell(String value) {
  return value.replaceAll(",", " ").replaceAll("\n", " ").replaceAll("\r", "");
}
