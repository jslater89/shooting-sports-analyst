/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Overlap between Limited Optics and Carry Optics Nationals competitor sets.
///
/// Uses [L2s Main LLR] match pointers and division rating groups. Match discovery
/// is by substring search on pointer name plus calendar year; fill in the
/// placeholders below with unambiguous search terms.
///
/// Identity comparison uses [ShooterRating.equalsShooter] with
/// [allPossibleMemberNumbers] so DB id equality is not required.
///
/// Competitor rosters use per-division filters; ratings are resolved in the
/// combined [uspsa-lo-co] (LO/CO) group. Decile overlap uses each competitor's
/// pre-match LO/CO rating at their nationals event. Decile cutoffs are computed
/// once per year from the pooled match-time LO/CO ratings at both nationals,
/// so D10 means the same skill tier at LO and CO events.

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const String kLoCoGroupUuid = "uspsa-lo-co";

/// Per-year Nationals match search terms (case-insensitive substring on pointer name).
///
/// LO: 2023/2024 Handgun Nationals; 2025 Race Gun Nationals.
/// CO: 2023/2024 standalone Carry Optics Nationals; 2025 Factory Gun Nationals.
const List<({int year, String loMatchSearch, String coMatchSearch})> kNationalsSearchTerms = [
  (
    year: 2023,
    loMatchSearch: "2023 Sig Sauer Hand Gun National",
    coMatchSearch: "2023 Sig Sauer Carry Optics Nationals",
  ),
  (
    year: 2024,
    loMatchSearch: "2024 Sig Sauer Handgun Nationals",
    coMatchSearch: "2024 Sig Sauer Carry Optics Nationals",
  ),
  (
    year: 2025,
    loMatchSearch: "Vortex Race Gun Nationals Presented by Berry Bullets",
    coMatchSearch: "2025 Sig Sauer Factory Gun Nationals",
  ),
];

class CoLoNationalsOverlapCommand extends DbOneoffCommand {
  CoLoNationalsOverlapCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "NOC";

  @override
  final String title = "CO/LO Nationals Overlap";

  @override
  String? get description =>
      "For each year, find LO and CO Nationals in L2s Main LLR and report competitor-set "
      "overlap using equalsShooter on LO/CO combined ratings, including by match-time decile.";

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

  final loCoGroup = project.groups.firstWhereOrNull((g) => g.uuid == kLoCoGroupUuid);
  if (loCoGroup == null) {
    console.print(
      "Project $projectName is missing the LO/CO combined rating group ($kLoCoGroupUuid).",
    );
    return;
  }

  final loRosterGroup = project.groupForDivisionSync(uspsaLimitedOptics);
  final coRosterGroup = project.groupForDivisionSync(uspsaCarryOptics);
  if (loRosterGroup == null || coRosterGroup == null) {
    console.print(
      "Project $projectName is missing LO and/or CO division groups for roster filters "
      "(got LO: ${loRosterGroup?.name}, CO: ${coRosterGroup?.name}).",
    );
    return;
  }

  final buf = StringBuffer()
    ..writeln("Project: $projectName")
    ..writeln("Rating group: ${loCoGroup.uiLabel} ($kLoCoGroupUuid)")
    ..writeln("LO roster filters: ${loRosterGroup.uiLabel}")
    ..writeln("CO roster filters: ${coRosterGroup.uiLabel}")
    ..writeln("Identity: ShooterRating.equalsShooter(allPossibleMemberNumbers: true)")
    ..writeln(
      "Deciles: pre-match LO/CO rating; shared cutoffs pooled from both nationals each year.",
    )
    ..writeln("");

  for (final cfg in kNationalsSearchTerms) {
    await _analyzeYear(
      db,
      buf,
      project: project,
      year: cfg.year,
      loMatchSearch: cfg.loMatchSearch,
      coMatchSearch: cfg.coMatchSearch,
      loCoGroup: loCoGroup,
      loRosterGroup: loRosterGroup,
      coRosterGroup: coRosterGroup,
    );
  }

  console.print(buf.toString());
}

Future<void> _analyzeYear(
  AnalystDatabase db,
  StringBuffer buf, {
  required DbRatingProject project,
  required int year,
  required String loMatchSearch,
  required String coMatchSearch,
  required RatingGroup loCoGroup,
  required RatingGroup loRosterGroup,
  required RatingGroup coRosterGroup,
}) async {
  buf.writeln("=== $year ===");

  if (loMatchSearch.startsWith("FILL_IN_") || coMatchSearch.startsWith("FILL_IN_")) {
    buf
      ..writeln("  Skipped: replace search-term placeholders in kNationalsSearchTerms.")
      ..writeln("    LO search: $loMatchSearch")
      ..writeln("    CO search: $coMatchSearch")
      ..writeln("");
    return;
  }

  final loFind = _findMatchPointerWithWarning(
    project,
    year: year,
    search: loMatchSearch,
    label: "LO",
  );
  final coFind = _findMatchPointerWithWarning(
    project,
    year: year,
    search: coMatchSearch,
    label: "CO",
  );
  if (loFind.warning != null) {
    buf.writeln("  Warning: ${loFind.warning}");
  }
  if (coFind.warning != null) {
    buf.writeln("  Warning: ${coFind.warning}");
  }

  final loPtr = loFind.pointer;
  final coPtr = coFind.pointer;

  if (loPtr == null) {
    buf.writeln("  LO: no match pointer for year $year containing \"$loMatchSearch\".");
  }
  if (coPtr == null) {
    buf.writeln("  CO: no match pointer for year $year containing \"$coMatchSearch\".");
  }
  if (loPtr == null || coPtr == null) {
    buf.writeln("");
    return;
  }

  final loRes = await _ratingsAtMatch(
    db,
    project,
    rosterGroup: loRosterGroup,
    ratingGroup: loCoGroup,
    ptr: loPtr,
  );
  if (loRes.error != null) {
    buf.writeln("  LO: ${loRes.error}");
    buf.writeln("");
    return;
  }
  final coRes = await _ratingsAtMatch(
    db,
    project,
    rosterGroup: coRosterGroup,
    ratingGroup: loCoGroup,
    ptr: coPtr,
  );
  if (coRes.error != null) {
    buf.writeln("  CO: ${coRes.error}");
    buf.writeln("");
    return;
  }

  final loRatings = _dedupeRatings(loRes.ratings);
  final coRatings = _dedupeRatings(coRes.ratings);
  final loParticipants = _participantsAtMatch(loRatings, loRes.match!);
  final coParticipants = _participantsAtMatch(coRatings, coRes.match!);
  final overlap = _countOverlap(loRatings, coRatings);

  final loDate = loRes.match!.date.toIso8601String().split("T").first;
  final coDate = coRes.match!.date.toIso8601String().split("T").first;

  buf
    ..writeln("  LO: ${loRes.match!.name} ($loDate)")
    ..writeln("    Roster (non-DQ, group filters): ${loRes.rosterEntries}")
    ..writeln("    Mapped to LO/CO ratings: ${loRatings.length} (${loRes.unmappedEntries} unmapped)")
    ..writeln("  CO: ${coRes.match!.name} ($coDate)")
    ..writeln("    Roster (non-DQ, group filters): ${coRes.rosterEntries}")
    ..writeln("    Mapped to LO/CO ratings: ${coRatings.length} (${coRes.unmappedEntries} unmapped)")
    ..writeln("  Overlap: $overlap competitors")
    ..writeln("    As % of LO: ${_pct(overlap, loRatings.length)}")
    ..writeln("    As % of CO: ${_pct(overlap, coRatings.length)}")
    ..writeln("    Jaccard (|∩|/|∪|): ${_pct(overlap, _unionSize(loRatings, coRatings))}");

  _writeDecileOverlap(buf, loParticipants, coParticipants);
  buf.writeln("");
}

final class _RatedParticipant {
  _RatedParticipant({
    required this.rating,
    required this.matchTimeRating,
  });

  final ShooterRating rating;
  final double matchTimeRating;
}

List<_RatedParticipant> _participantsAtMatch(
  List<ShooterRating> ratings,
  ShootingMatch match,
) {
  return [
    for (final rating in ratings)
      _RatedParticipant(
        rating: rating,
        matchTimeRating: rating.ratingForEvent(match, null, beforeMatch: true),
      ),
  ];
}

void _writeDecileOverlap(
  StringBuffer buf,
  List<_RatedParticipant> loParticipants,
  List<_RatedParticipant> coParticipants,
) {
  final pooledRatings = [
    ...loParticipants.map((p) => p.matchTimeRating),
    ...coParticipants.map((p) => p.matchTimeRating),
  ];
  final thresholds = _RatingDecileThresholds.fromValues(pooledRatings);
  if (thresholds == null) {
    buf.writeln("  Overlap by match-time LO/CO rating decile: insufficient mapped ratings.");
    return;
  }

  buf
    ..writeln(
      "  Overlap by match-time LO/CO rating decile "
      "(shared cutoffs from both nationals fields):",
    )
    ..writeln("    ${thresholds.summary("LO/CO")}");

  for (var decile = 1; decile <= 10; decile++) {
    final loInD = loParticipants
        .where((p) => thresholds.decileFor(p.matchTimeRating) == decile)
        .toList();
    final coInD = coParticipants
        .where((p) => thresholds.decileFor(p.matchTimeRating) == decile)
        .toList();
    final overlap = _countParticipantOverlap(loInD, coInD);
    buf.writeln(
      "    D$decile (${thresholds.decileRangeLabel(decile)}) — overlap $overlap; "
      "as % LO: ${_pct(overlap, loInD.length)}; "
      "as % CO: ${_pct(overlap, coInD.length)}",
    );
  }

  buf.writeln("  Top-decile crossover (% of that decile who also did the other nationals):");
  for (final decile in [10, 9, 8]) {
    final loInD = loParticipants
        .where((p) => thresholds.decileFor(p.matchTimeRating) == decile)
        .toList();
    final coInD = coParticipants
        .where((p) => thresholds.decileFor(p.matchTimeRating) == decile)
        .toList();
    final loRate = loInD.isEmpty ? "n/a" : _pctShort(_countParticipantOverlap(loInD, coParticipants), loInD.length);
    final coRate = coInD.isEmpty ? "n/a" : _pctShort(_countParticipantOverlap(loParticipants, coInD), coInD.length);
    buf.writeln("    D$decile — LO: $loRate; CO: $coRate (n LO: ${loInD.length}, n CO: ${coInD.length})");
  }
}

String _pctShort(int numerator, int denominator) {
  if (denominator == 0) {
    return "n/a";
  }
  final pct = 100.0 * numerator / denominator;
  return "${pct.toStringAsFixed(1)}%";
}

int _countParticipantOverlap(
  List<_RatedParticipant> loParticipants,
  List<_RatedParticipant> coParticipants,
) {
  var count = 0;
  for (final lo in loParticipants) {
    if (coParticipants.any(
      (co) => lo.rating.equalsShooter(co.rating, allPossibleMemberNumbers: true),
    )) {
      count++;
    }
  }
  return count;
}

final class _RatingDecileThresholds {
  _RatingDecileThresholds({
    required this.cutoffs,
    required this.populationSize,
  });

  /// Upper bounds for deciles 1–9 (length 9).
  final List<double> cutoffs;
  final int populationSize;

  static _RatingDecileThresholds? fromValues(Iterable<double> values) {
    final sorted = [...values]..sort();
    if (sorted.isEmpty) {
      return null;
    }
    return _RatingDecileThresholds(
      cutoffs: [
        for (var i = 1; i <= 9; i++)
          _percentile(sorted, i / 10.0),
      ],
      populationSize: sorted.length,
    );
  }

  int decileFor(double rating) {
    for (var i = 0; i < 9; i++) {
      if (rating <= cutoffs[i]) {
        return i + 1;
      }
    }
    return 10;
  }

  String summary(String fieldLabel) {
    return "$fieldLabel decile cutoffs (n=$populationSize): "
        "D1≤${cutoffs[0].toStringAsFixed(3)}, "
        "D5≤${cutoffs[4].toStringAsFixed(3)}, "
        "D9≤${cutoffs[8].toStringAsFixed(3)}, "
        "D10>${cutoffs[8].toStringAsFixed(3)}";
  }

  String decileRangeLabel(int decile) {
    if (decile == 1) {
      return "≤ ${cutoffs[0].toStringAsFixed(3)}";
    }
    if (decile == 10) {
      return "> ${cutoffs[8].toStringAsFixed(3)}";
    }
    return "${cutoffs[decile - 2].toStringAsFixed(3)}–${cutoffs[decile - 1].toStringAsFixed(3)}";
  }
}

double _percentile(List<double> sortedValues, double percentile) {
  if (sortedValues.isEmpty) {
    return 0.0;
  }
  if (sortedValues.length == 1) {
    return sortedValues.first;
  }

  final clamped = percentile.clamp(0.0, 1.0);
  final position = (sortedValues.length - 1) * clamped;
  final lowerIndex = position.floor();
  final upperIndex = position.ceil();

  if (lowerIndex == upperIndex) {
    return sortedValues[lowerIndex];
  }

  final lowerValue = sortedValues[lowerIndex];
  final upperValue = sortedValues[upperIndex];
  final weight = position - lowerIndex;
  return lowerValue + (upperValue - lowerValue) * weight;
}

/// Finds a match pointer by year and name substring; warns when multiple hit.
({MatchPointer? pointer, String? warning}) _findMatchPointerWithWarning(
  DbRatingProject project, {
  required int year,
  required String search,
  required String label,
}) {
  final needle = search.toLowerCase();
  final hits = project.matchPointers
      .where((p) => p.date != null && p.date!.year == year)
      .where((p) => p.name.toLowerCase().contains(needle))
      .toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  if (hits.isEmpty) {
    return (pointer: null, warning: null);
  }
  String? warning;
  if (hits.length > 1) {
    warning =
        "$label: ${hits.length} pointers match year $year and \"$search\"; using \"${hits.first.name}\".";
  }
  return (pointer: hits.first, warning: warning);
}

final class _MatchRatingsResult {
  _MatchRatingsResult({
    this.match,
    required this.ratings,
    required this.rosterEntries,
    required this.unmappedEntries,
    this.error,
  });

  final ShootingMatch? match;
  final List<ShooterRating> ratings;
  final int rosterEntries;
  final int unmappedEntries;
  final String? error;
}

Future<_MatchRatingsResult> _ratingsAtMatch(
  AnalystDatabase db,
  DbRatingProject project, {
  required RatingGroup rosterGroup,
  required RatingGroup ratingGroup,
  required MatchPointer ptr,
}) async {
  final loadRes = await ptr.getDbMatch(db, downloadIfMissing: false);
  if (loadRes.isErr()) {
    return _MatchRatingsResult(
      ratings: const [],
      rosterEntries: 0,
      unmappedEntries: 0,
      error: "could not load \"${ptr.name}\": ${loadRes.unwrapErr().message}",
    );
  }

  final dbMatch = loadRes.unwrap();
  if (dbMatch.shootersStoredSeparately) {
    await dbMatch.shooterLinks.load();
  }

  final hydrated = await dbMatch.hydrate();
  if (hydrated.isErr()) {
    return _MatchRatingsResult(
      ratings: const [],
      rosterEntries: 0,
      unmappedEntries: 0,
      error: "hydrate failed for \"${dbMatch.eventName}\": ${hydrated.unwrapErr()}",
    );
  }

  final shootingMatch = hydrated.unwrap();
  final scores = shootingMatch.getScoresFromFilters(rosterGroup.filters);
  final ratings = <ShooterRating>[];
  var rosterEntries = 0;
  var unmappedEntries = 0;

  for (final entry in scores.entries) {
    final matchEntry = entry.key;
    if (matchEntry.dq) {
      continue;
    }
    if (!rosterGroup.filters.reentries && matchEntry.reentry) {
      continue;
    }
    rosterEntries++;

    final dbRating = _lookupRating(db, project, ratingGroup, matchEntry);
    if (dbRating == null) {
      unmappedEntries++;
      continue;
    }
    ratings.add(project.wrapDbRatingSync(dbRating));
  }

  return _MatchRatingsResult(
    match: shootingMatch,
    ratings: ratings,
    rosterEntries: rosterEntries,
    unmappedEntries: unmappedEntries,
  );
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

List<ShooterRating> _dedupeRatings(List<ShooterRating> ratings) {
  final out = <ShooterRating>[];
  for (final rating in ratings) {
    if (!out.any((existing) => existing.equalsShooter(rating, allPossibleMemberNumbers: true))) {
      out.add(rating);
    }
  }
  return out;
}

int _countOverlap(List<ShooterRating> loRatings, List<ShooterRating> coRatings) {
  var count = 0;
  for (final lo in loRatings) {
    if (coRatings.any((co) => lo.equalsShooter(co, allPossibleMemberNumbers: true))) {
      count++;
    }
  }
  return count;
}

int _unionSize(List<ShooterRating> loRatings, List<ShooterRating> coRatings) {
  final union = [...loRatings];
  for (final co in coRatings) {
    if (!union.any((existing) => existing.equalsShooter(co, allPossibleMemberNumbers: true))) {
      union.add(co);
    }
  }
  return union.length;
}

String _pct(int numerator, int denominator) {
  if (denominator == 0) {
    return "n/a";
  }
  final pct = 100.0 * numerator / denominator;
  return "${pct.toStringAsFixed(1)}% ($numerator / $denominator)";
}
