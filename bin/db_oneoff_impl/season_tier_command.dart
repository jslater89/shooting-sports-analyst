/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Seasonal rating tiers for L2s Main LLR, per single-division group.
///
/// Cutoffs for season Y are percentile ratings of the prior year's eligible
/// shooters. A shooter earns a tier when their rating after their last event
/// in year Y is strictly above that cutoff. Eligible means at least
/// [kMinCareerMatches] distinct matches on or before Dec 31 of the year, and
/// at least one match in the year.
///
/// Challenger is separate: a division finish of at least [kChallengerPercentage]
/// at USPSA Nationals or US IPSC Nationals, held from that match through
/// Dec 31 of the next calendar year. IPSC divisions map onto USPSA groups
/// through the IPSC-to-USPSA sport link.
///
/// Launch: dart run bin/db_oneoffs.dart TIER [startYear] [endYear]

import "dart:io";
import "dart:math";

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:isar_community/isar.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_system.dart";
import "package:shooting_sports_analyst/data/sport/builtins/registry.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const int kDefaultStartYear = 2023;
const int kDefaultEndYear = 2026;
const int kMinCareerMatches = 3;
const double kChallengerPercentage = 95.0;
const String kReportPath = "/tmp/llr_season_tiers.txt";
const String kOpenGroupUuid = "uspsa-open";

const List<String> kOpenNationalNameMarkers = [
  "open",
  "hi-cap",
  "hicap",
  "racegun",
  "race gun",
];

/// US IPSC Nationals, including "U.S IPSC" and "National Championship".
final RegExp kUsIpscNationalPattern = RegExp(
  r"\bU\.?S\.?\s+IPSC\b.*(\bNationals\b|\bNational\s+Championship)",
  caseSensitive: false,
);

class _Tier {
  const _Tier(this.name, this.percentile);

  final String name;
  final int percentile;

  double get fraction => percentile / 100.0;
}

const List<_Tier> kTiersHighToLow = [
  _Tier("Diamond", 95),
  _Tier("Ruby", 90),
  _Tier("Emerald", 85),
  _Tier("Sapphire", 80),
  _Tier("Gold", 75),
  _Tier("Silver", 70),
  _Tier("Bronze", 60),
];

class _YearShot {
  _YearShot({
    required this.rating,
    required this.matchesThisYear,
    required this.careerMatches,
  });

  final double rating;
  final int matchesThisYear;
  final int careerMatches;

  bool get eligible => matchesThisYear >= 1 && careerMatches >= kMinCareerMatches;
}

class SeasonTierCommand extends DbOneoffCommand {
  SeasonTierCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "TIER";

  @override
  final String title = "Season Tier Cutoffs (LLR)";

  @override
  String? get description =>
      "Prior-year percentile cutoffs and counts for Bronze–Diamond, plus "
      "Nationals 95% Challenger, on L2s Main LLR single-division groups.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Start Year",
          defaultValue: kDefaultStartYear,
          description: "First season to score. Cutoffs come from the previous year.",
        ),
        IntMenuArgument(
          label: "End Year",
          defaultValue: kDefaultEndYear,
          description: "Last season to score. The current year is reported year-to-date.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final startYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "Start Year")
            ?.getAs<int>() ??
        kDefaultStartYear;
    final endYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "End Year")
            ?.getAs<int>() ??
        kDefaultEndYear;
    await _run(
      db,
      console,
      projectName: kDefaultLlrProjectName,
      startYear: startYear,
      endYear: endYear,
    );
  }
}

bool _isUsIpscNationalPointer(MatchPointer pointer) {
  return pointer.sportName.toLowerCase() == "ipsc"
      && kUsIpscNationalPattern.hasMatch(pointer.name);
}

bool _isUspsaNationalPointer(MatchPointer pointer) {
  if (pointer.sportName.toLowerCase() == "ipsc") {
    return false;
  }
  final nameLower = pointer.name.toLowerCase();
  return nameLower.contains("national")
      && !nameLower.contains("ipsc")
      && !nameLower.contains("shooting international");
}

bool _isNationalPointer(MatchPointer pointer) {
  return _isUspsaNationalPointer(pointer) || _isUsIpscNationalPointer(pointer);
}

bool _isOpenNationalPointer(MatchPointer pointer) {
  if (!_isUspsaNationalPointer(pointer)) {
    return false;
  }
  final nameLower = pointer.name.toLowerCase();
  return kOpenNationalNameMarkers.any(nameLower.contains);
}

bool _groupCountsMatch(RatingGroup group, MatchPointer pointer) {
  if (_isUsIpscNationalPointer(pointer)) {
    return true;
  }
  if (group.uuid == kOpenGroupUuid) {
    return _isOpenNationalPointer(pointer);
  }
  return _isUspsaNationalPointer(pointer);
}

bool _entryCountsForGroup(RatingGroup group, DbShootingMatch match, DbMatchEntry entry) {
  final divisionName = entry.divisionName;
  if (divisionName == null || divisionName.isEmpty) {
    return false;
  }
  if (match.sportName.toLowerCase() == group.sportName.toLowerCase()
      && divisionName == group.divisionNames.single) {
    return true;
  }
  final sport = SportRegistry().lookup(match.sportName);
  if (sport == null) {
    return false;
  }
  final division = sport.divisions.lookupByName(divisionName, fallback: false);
  if (division == null) {
    return false;
  }
  return group.containsDivision(division);
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required int startYear,
  required int endYear,
}) async {
  if (endYear < startYear) {
    console.print("End year $endYear is before start year $startYear.");
    return;
  }

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

  final cutoffStartYear = startYear - 1;
  final windowStart = DateTime(cutoffStartYear, 1, 1);
  final windowEnd = DateTime(endYear, 12, 31, 23, 59, 59);
  final algorithm = project.settings.algorithm;

  final pointers = project.matchPointers.where((ptr) {
    if (!_isNationalPointer(ptr)) {
      return false;
    }
    final year = ptr.date?.year;
    if (year == null) {
      return true;
    }
    return year >= cutoffStartYear && year <= endYear;
  }).toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  final challengersByGroup = <String, Map<int, Set<int>>>{
    for (final group in groups) group.uuid: {},
  };
  final nationalsLines = <String>[];
  var nationalsLoadErrors = 0;
  var unmappedFinishes = 0;
  var qualifyingFinishes = 0;

  if (pointers.isNotEmpty) {
    final bar = LabeledProgressBar(
      maxValue: pointers.length,
      canHaveErrors: true,
      initialLabel: "Scanning Nationals matches…",
    );
    for (final ptr in pointers) {
      bar.tick(ptr.name);
      final loadRes = await ptr.getDbMatch(db, downloadIfMissing: false);
      if (loadRes.isErr()) {
        bar.error("Load failed: ${ptr.name}");
        nationalsLoadErrors++;
        continue;
      }
      final dbMatch = loadRes.unwrap();
      final year = dbMatch.date.year;
      if (year < cutoffStartYear || year > endYear) {
        continue;
      }
      if (dbMatch.shootersStoredSeparately) {
        await dbMatch.shooterLinks.load();
      }

      final dateLabel = dbMatch.date.toIso8601String().split("T").first;
      final kind = _isUsIpscNationalPointer(ptr) ? "US IPSC  " : "";
      nationalsLines.add("  $dateLabel  $kind${dbMatch.eventName}");

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
        final byYear = challengersByGroup[group.uuid]!;
        final ids = byYear.putIfAbsent(year, () => <int>{});
        for (final entry in entries) {
          if (entry.dq || !_entryCountsForGroup(group, dbMatch, entry)) {
            continue;
          }
          final score = entry.precalculatedScore;
          if (score == null || score.place <= 0 || score.percentage < kChallengerPercentage) {
            continue;
          }
          final dbRating = _lookupRating(db, project, group, entry);
          if (dbRating == null) {
            unmappedFinishes++;
            continue;
          }
          qualifyingFinishes++;
          ids.add(dbRating.id);
        }
      }
    }
    bar.complete();
  }

  final shotsByGroup = <String, Map<int, Map<int, _YearShot>>>{};
  var ratingsScanned = 0;

  for (final group in groups) {
    final ratingsRes = project.getRatingsSync(group);
    if (ratingsRes.isErr()) {
      console.print("Skipping ${group.name}; failed to load ratings.");
      shotsByGroup[group.uuid] = {};
      continue;
    }
    final ratings = ratingsRes.unwrap();
    final byYear = <int, Map<int, _YearShot>>{};
    for (var year = cutoffStartYear; year <= endYear; year++) {
      byYear[year] = {};
    }

    final tickEvery = 200;
    final ticks = max(1, (ratings.length / tickEvery).ceil());
    final bar = LabeledProgressBar(
      maxValue: ticks,
      initialLabel: "${group.name}: 0/${ratings.length}",
    );
    var sinceTick = 0;
    for (var i = 0; i < ratings.length; i++) {
      final rating = ratings[i];
      sinceTick++;
      if (sinceTick >= tickEvery || i == ratings.length - 1) {
        bar.tick("${group.name}: ${i + 1}/${ratings.length}");
        sinceTick = 0;
      }
      if (rating.cachedLength <= 0) {
        continue;
      }
      if (rating.lastSeen.isBefore(windowStart) || rating.firstSeen.isAfter(windowEnd)) {
        continue;
      }

      final earlyIds = <String>{};
      if (rating.firstSeen.isBefore(windowStart)) {
        final early = rating.events.filter()
            .dateLessThan(windowStart)
            .distinctByMatchId()
            .findAllSync();
        for (final event in early) {
          if (event.matchId.isNotEmpty) {
            earlyIds.add(event.matchId);
          }
        }
      }

      final events = db.getRatingEventsForSync(
        rating,
        after: windowStart,
        before: windowEnd,
        order: Order.descending,
      );
      final matchesByYear = <int, Set<String>>{};
      final endRatingByYear = <int, double>{};
      for (final event in events) {
        if (event.matchId.isEmpty) {
          continue;
        }
        final year = event.date.year;
        if (year < cutoffStartYear || year > endYear) {
          continue;
        }
        matchesByYear.putIfAbsent(year, () => <String>{}).add(event.matchId);
        endRatingByYear.putIfAbsent(year, () => event.newRating);
      }
      if (matchesByYear.isEmpty) {
        continue;
      }

      final known = {...earlyIds};
      var career = earlyIds.length;
      final years = matchesByYear.keys.toList()..sort();
      for (final year in years) {
        for (final matchId in matchesByYear[year]!) {
          if (known.add(matchId)) {
            career++;
          }
        }
        final endRating = endRatingByYear[year];
        final matchesThisYear = matchesByYear[year]!.length;
        if (endRating == null || matchesThisYear == 0) {
          continue;
        }
        byYear[year]![rating.id] = _YearShot(
          rating: endRating,
          matchesThisYear: matchesThisYear,
          careerMatches: career,
        );
      }
      ratingsScanned++;
    }
    bar.complete();
    shotsByGroup[group.uuid] = byYear;
  }

  final buf = StringBuffer();
  _writeHeader(
    buf,
    projectName: projectName,
    startYear: startYear,
    endYear: endYear,
    groups: groups,
    nationalsLines: nationalsLines,
    nationalsLoadErrors: nationalsLoadErrors,
    qualifyingFinishes: qualifyingFinishes,
    unmappedFinishes: unmappedFinishes,
    ratingsScanned: ratingsScanned,
  );

  final totals = <int, _SeasonTotals>{
    for (var year = startYear; year <= endYear; year++) year: _SeasonTotals(),
  };

  for (final group in groups) {
    _writeGroup(
      buf,
      algorithm: algorithm,
      group: group,
      startYear: startYear,
      endYear: endYear,
      shotsByYear: shotsByGroup[group.uuid] ?? {},
      challengersByYear: challengersByGroup[group.uuid] ?? {},
      totals: totals,
    );
  }

  _writeTotals(buf, startYear: startYear, endYear: endYear, totals: totals);

  final report = buf.toString();
  File(kReportPath).writeAsStringSync(report);
  console.print(report);
  console.print("Wrote $kReportPath");
}

void _writeHeader(
  StringBuffer buf, {
  required String projectName,
  required int startYear,
  required int endYear,
  required List<RatingGroup> groups,
  required List<String> nationalsLines,
  required int nationalsLoadErrors,
  required int qualifyingFinishes,
  required int unmappedFinishes,
  required int ratingsScanned,
}) {
  buf.writeln("Project: $projectName");
  buf.writeln("Groups: ${groups.map((g) => g.name).join(", ")}");
  buf.writeln(
    "Seasons: $startYear–$endYear. "
    "A season's cutoffs are the prior year's percentiles.",
  );
  buf.writeln(
    "Eligible: >= $kMinCareerMatches distinct matches through Dec 31 of that year, "
    "and >= 1 match in the year. "
    "Year-end rating is the rating after the last event dated in that year.",
  );
  buf.writeln(
    "Percentile: linear interpolation (position = (n - 1) * p on the sorted ratings). "
    "Earn a threshold when year-end rating is strictly above the cutoff. "
    "In Tier is the highest threshold exceeded. "
    "Prior> / This> count eligible shooters above that cutoff.",
  );
  buf.writeln(
    "Challenger: division finish >= ${kChallengerPercentage.toStringAsFixed(0)}% "
    "at a USPSA match whose name contains National "
    "(excluding IPSC and Shooting International), or at US IPSC Nationals. "
    "Open USPSA matches count only when the name also contains "
    "${kOpenNationalNameMarkers.join(", ")}. "
    "US IPSC divisions map through the IPSC-to-USPSA sport link, including Open. "
    "Held through Dec 31 of the next calendar year. "
    "Challenger does not remove a shooter from a rating tier.",
  );
  buf.writeln(
    "Ratings are the project's display scale. "
    "Counts are division rating rows, not unique people across divisions.",
  );
  buf.writeln(
    "Ratings with a match in the window: $ratingsScanned. "
    "Nationals load errors: $nationalsLoadErrors. "
    "Qualifying Challenger finishes: $qualifyingFinishes. "
    "Unmapped Challenger finishes: $unmappedFinishes.",
  );
  buf.writeln("");
  buf.writeln("Nationals matches in ${startYear - 1}–$endYear:");
  if (nationalsLines.isEmpty) {
    buf.writeln("  (none)");
  }
  else {
    for (final line in nationalsLines) {
      buf.writeln(line);
    }
  }
  buf.writeln("");
}

void _writeGroup(
  StringBuffer buf, {
  required RatingSystem algorithm,
  required RatingGroup group,
  required int startYear,
  required int endYear,
  required Map<int, Map<int, _YearShot>> shotsByYear,
  required Map<int, Set<int>> challengersByYear,
  required Map<int, _SeasonTotals> totals,
}) {
  buf.writeln("======== ${group.name} ========");
  for (var year = startYear; year <= endYear; year++) {
    final priorShots = shotsByYear[year - 1] ?? {};
    final thisShots = shotsByYear[year] ?? {};
    final priorEligible = priorShots.values.where((s) => s.eligible).toList();
    final thisEligible = thisShots.values.where((s) => s.eligible).toList();
    final priorActive = priorShots.length;
    final thisActive = thisShots.length;
    final thisShortCareer = thisShots.values.where((s) => !s.eligible).length;

    buf.writeln("");
    buf.writeln("Season ${_seasonLabel(year)}");
    buf.writeln(
      "  Prior year ${year - 1}: $priorActive with a match, "
      "${priorEligible.length} eligible"
      "${priorEligible.isEmpty ? "" : ", median ${_fmt(algorithm, _median(priorEligible))}"}",
    );
    buf.writeln(
      "  This year: $thisActive with a match, "
      "${thisEligible.length} eligible, "
      "$thisShortCareer under $kMinCareerMatches career matches",
    );

    final totalsRow = totals[year]!;
    totalsRow.eligible += thisEligible.length;

    if (priorEligible.isEmpty) {
      totalsRow.noCutoff += thisEligible.length;
      buf.writeln("  No eligible shooters in ${year - 1}; rating cutoffs not set.");
    }
    else {
      final sortedPrior = priorEligible.map((s) => s.rating).toList()..sort();
      final sortedThis = thisEligible.map((s) => s.rating).toList()..sort();
      final cutoffs = <_Tier, double>{
        for (final tier in kTiersHighToLow) tier: _percentile(sortedPrior, tier.fraction),
      };

      buf.writeln(
        "  ${"Tier".padRight(10)}"
        "${"Pctl".padLeft(6)}"
        "${"Cutoff".padLeft(10)}"
        "${"Prior>".padLeft(9)}"
        "${"This>".padLeft(9)}"
        "${"In Tier".padLeft(9)}",
      );

      final exclusive = <_Tier, int>{for (final tier in kTiersHighToLow) tier: 0};
      var below = 0;
      for (final shot in thisEligible) {
        final tier = _highestTier(shot.rating, cutoffs);
        if (tier == null) {
          below++;
        }
        else {
          exclusive[tier] = exclusive[tier]! + 1;
        }
      }

      for (final tier in kTiersHighToLow) {
        final cutoff = cutoffs[tier]!;
        final priorAbove = _countAbove(sortedPrior, cutoff);
        final thisAbove = _countAbove(sortedThis, cutoff);
        final inTier = exclusive[tier]!;
        totalsRow.inTier[tier.name] = (totalsRow.inTier[tier.name] ?? 0) + inTier;
        buf.writeln(
          "  ${tier.name.padRight(10)}"
          "${tier.percentile.toString().padLeft(6)}"
          "${_fmt(algorithm, cutoff).padLeft(10)}"
          "${priorAbove.toString().padLeft(9)}"
          "${thisAbove.toString().padLeft(9)}"
          "${inTier.toString().padLeft(9)}",
        );
      }
      totalsRow.below += below;
      buf.writeln(
        "  ${"Below".padRight(10)}"
        "${"—".padLeft(6)}"
        "${"—".padLeft(10)}"
        "${"—".padLeft(9)}"
        "${"—".padLeft(9)}"
        "${below.toString().padLeft(9)}",
      );
    }

    final thisIds = challengersByYear[year] ?? {};
    final carriedIds = challengersByYear[year - 1] ?? {};
    final holders = {...thisIds, ...carriedIds};
    final newOnly = thisIds.difference(carriedIds).length;
    final carriedOnly = carriedIds.difference(thisIds).length;
    final both = thisIds.intersection(carriedIds).length;
    totalsRow.challenger += holders.length;

    buf.writeln(
      "  Challenger through end of $year: ${holders.length} "
      "(new $newOnly, carried $carriedOnly, both years $both)",
    );
    if (holders.isNotEmpty && priorEligible.isNotEmpty) {
      final sortedPrior = priorEligible.map((s) => s.rating).toList()..sort();
      final cutoffs = <_Tier, double>{
        for (final tier in kTiersHighToLow) tier: _percentile(sortedPrior, tier.fraction),
      };
      final holderTiers = <String, int>{};
      var holderIneligible = 0;
      var holderMissing = 0;
      for (final id in holders) {
        final shot = thisShots[id];
        if (shot == null) {
          holderMissing++;
          continue;
        }
        if (!shot.eligible) {
          holderIneligible++;
          continue;
        }
        final tier = _highestTier(shot.rating, cutoffs);
        final name = tier?.name ?? "Below";
        holderTiers[name] = (holderTiers[name] ?? 0) + 1;
      }
      final parts = <String>[
        for (final tier in kTiersHighToLow)
          if ((holderTiers[tier.name] ?? 0) > 0) "${tier.name} ${holderTiers[tier.name]}",
        if ((holderTiers["Below"] ?? 0) > 0) "Below ${holderTiers["Below"]}",
        if (holderIneligible > 0) "under $kMinCareerMatches matches $holderIneligible",
        if (holderMissing > 0) "no $year match $holderMissing",
      ];
      buf.writeln("  Challenger holders' $year rating tier: ${parts.join(", ")}");
    }
  }
  buf.writeln("");
}

void _writeTotals(
  StringBuffer buf, {
  required int startYear,
  required int endYear,
  required Map<int, _SeasonTotals> totals,
}) {
  buf.writeln("======== Division slots, summed (not unique people) ========");
  final nameW = 10;
  buf.write("Season".padRight(12));
  buf.write("Elig".padLeft(8));
  for (final tier in kTiersHighToLow) {
    buf.write(tier.name.padLeft(nameW));
  }
  buf.write("Below".padLeft(nameW));
  buf.write("NoCutoff".padLeft(nameW));
  buf.writeln("Challenger".padLeft(12));
  for (var year = startYear; year <= endYear; year++) {
    final row = totals[year]!;
    buf.write(_seasonLabel(year).padRight(12));
    buf.write("${row.eligible}".padLeft(8));
    for (final tier in kTiersHighToLow) {
      buf.write("${row.inTier[tier.name] ?? 0}".padLeft(nameW));
    }
    buf.write("${row.below}".padLeft(nameW));
    buf.write("${row.noCutoff}".padLeft(nameW));
    buf.writeln("${row.challenger}".padLeft(12));
  }
  buf.writeln("");
}

class _SeasonTotals {
  int eligible = 0;
  int below = 0;
  int noCutoff = 0;
  int challenger = 0;
  final Map<String, int> inTier = {};
}

String _seasonLabel(int year) {
  final now = DateTime.now();
  if (year == now.year && !(now.month == 12 && now.day == 31)) {
    return "$year YTD";
  }
  return "$year";
}

String _fmt(RatingSystem algorithm, double rating) {
  return algorithm.formatNumericRating(rating);
}

double _median(List<_YearShot> shots) {
  final values = shots.map((s) => s.rating).toList()..sort();
  return _percentile(values, 0.5);
}

_Tier? _highestTier(double rating, Map<_Tier, double> cutoffs) {
  for (final tier in kTiersHighToLow) {
    final cutoff = cutoffs[tier]!;
    if (rating > cutoff) {
      return tier;
    }
  }
  return null;
}

int _countAbove(List<double> sorted, double cutoff) {
  var count = 0;
  for (var i = sorted.length - 1; i >= 0; i--) {
    if (sorted[i] <= cutoff) {
      break;
    }
    count++;
  }
  return count;
}

double _percentile(List<double> sortedValues, double percentile) {
  if (sortedValues.isEmpty) {
    return double.nan;
  }
  if (sortedValues.length == 1) {
    return sortedValues.first;
  }
  final position = (sortedValues.length - 1) * percentile;
  final lowerIndex = position.floor();
  final upperIndex = position.ceil();
  if (lowerIndex == upperIndex) {
    return sortedValues[lowerIndex];
  }
  final weight = position - lowerIndex;
  return sortedValues[lowerIndex] + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * weight;
}

Iterable<String> _memberNumberCandidates(DbMatchEntry entry) sync* {
  final seen = <String>{};
  for (final candidate in [
    entry.memberNumber,
    entry.originalMemberNumber,
    ...entry.knownMemberNumbers,
  ]) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty || trimmed == "(invalid)") {
      continue;
    }
    if (seen.add(trimmed)) {
      yield trimmed;
    }
  }
}

DbShooterRating? _lookupRating(
  AnalystDatabase db,
  DbRatingProject project,
  RatingGroup group,
  DbMatchEntry entry,
) {
  for (final memberNumber in _memberNumberCandidates(entry)) {
    final dbRating = db.maybeKnownShooterSync(
      project: project,
      group: group,
      memberNumber: memberNumber,
      usePossibleMemberNumbers: true,
    );
    if (dbRating != null) {
      return dbRating;
    }
  }
  return null;
}
