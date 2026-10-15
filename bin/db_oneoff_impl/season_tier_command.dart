/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Seasonal rating tiers for L2s Main LLR, per single-division group.
///
/// Cutoffs for season Y are percentile ratings of the prior year's cutoff
/// population: at least [kMinCareerMatchesForCutoff] distinct matches through
/// Dec 31 of that year, and at least one match in the year. A shooter earns a
/// tier when their rating after their last event in year Y is strictly above
/// that cutoff. Earning a tier requires at least [kMinCareerMatchesForTier]
/// career matches through Dec 31 and at least one match in the year.
///
/// Challenger is separate: a division finish of at least [kChallengerPercentage]
/// at USPSA Nationals or US IPSC Nationals, held from that match through
/// Dec 31 of the next calendar year. IPSC divisions map onto USPSA groups
/// through the IPSC-to-USPSA sport link.
///
/// Launch: dart run bin/db_oneoffs.dart TIER [startYear] [endYear] [classic|wide]
///
/// Every match in L2s Main LLR is a major, so consecutive match-end ratings
/// are consecutive majors.

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
const int kMinCareerMatchesForCutoff = 3;
const int kMinCareerMatchesForTier = 2;
const double kChallengerPercentage = 95.0;
const bool kDefaultWideTiers = false;

String _reportPath(bool wideTiers) =>
    wideTiers ? "/tmp/llr_season_tiers_wide.txt" : "/tmp/llr_season_tiers.txt";
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

  /// Percentile of the prior-year cutoff population. 92.5 means the 92.5th.
  final double percentile;

  double get fraction => percentile / 100.0;
}

/// Original ladder. Each row is the floor; the shooter keeps the highest floor exceeded.
const List<_Tier> kClassicTiersHighToLow = [
  _Tier("Diamond", 95),
  _Tier("Ruby", 90),
  _Tier("Emerald", 85),
  _Tier("Sapphire", 80),
  _Tier("Gold", 75),
  _Tier("Silver", 70),
  _Tier("Bronze", 60),
];

/// Wider metals at the bottom, tighter gems at the top.
/// Rank I is the first, lower step. Rank II is the next step up.
const List<_Tier> kWideTiersHighToLow = [
  _Tier("Diamond", 97),
  _Tier("Ruby", 95),
  _Tier("Emerald", 92.5),
  _Tier("Sapphire", 90),
  _Tier("Gold II", 85),
  _Tier("Gold I", 80),
  _Tier("Silver II", 75),
  _Tier("Silver I", 70),
  _Tier("Bronze II", 65),
  _Tier("Bronze I", 60),
];

/// Ruby and Sapphire stay at 95 and 90. The 10-point metal is rank I.
const List<_Tier> kWideRubyLadderHighToLow = [
  _Tier("Ruby", 95),
  _Tier("Sapphire", 90),
  _Tier("Gold I", 80),
  _Tier("Silver I", 70),
  _Tier("Bronze I", 60),
];

/// Sapphire stays at 90. The 10-point metal is rank I.
const List<_Tier> kWideSapphireLadderHighToLow = [
  _Tier("Sapphire", 90),
  _Tier("Gold I", 80),
  _Tier("Silver I", 70),
  _Tier("Bronze I", 60),
];

const int kFullLadderMinField = 300;
const int kRubyLadderMinField = 150;
const int kSapphireLadderMinField = 40;

List<_Tier> _tiersFor(bool wideTiers) =>
    wideTiers ? kWideTiersHighToLow : kClassicTiersHighToLow;

/// Wide ladder kept at the original percentiles. Thin fields drop tiers
/// instead of moving the ones that remain.
List<_Tier> _wideTiersForField(int cutoffField) {
  if (cutoffField >= kFullLadderMinField) {
    return kWideTiersHighToLow;
  }
  if (cutoffField >= kRubyLadderMinField) {
    return kWideRubyLadderHighToLow;
  }
  if (cutoffField >= kSapphireLadderMinField) {
    return kWideSapphireLadderHighToLow;
  }
  return const [];
}

String _ladderId(List<_Tier> tiers) {
  if (tiers.any((tier) => tier.name == "Diamond")) {
    return "full";
  }
  if (tiers.any((tier) => tier.name == "Ruby")) {
    return "ruby";
  }
  if (tiers.any((tier) => tier.name == "Sapphire")) {
    return "sapphire";
  }
  return "none";
}

String _ladderName(bool wideTiers) => wideTiers ? "wide" : "classic";

const List<_Tier> kWideDisplayOrder = [
  _Tier("Diamond", 97),
  _Tier("Ruby", 95),
  _Tier("Emerald", 92.5),
  _Tier("Sapphire", 90),
  _Tier("Gold II", 85),
  _Tier("Gold I", 80),
  _Tier("Silver II", 75),
  _Tier("Silver I", 70),
  _Tier("Bronze II", 65),
  _Tier("Bronze I", 60),
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

  bool get setsCutoff =>
      matchesThisYear >= 1 && careerMatches >= kMinCareerMatchesForCutoff;

  bool get earnsTier =>
      matchesThisYear >= 1 && careerMatches >= kMinCareerMatchesForTier;
}

class SeasonTierCommand extends DbOneoffCommand {
  SeasonTierCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "TIER";

  @override
  final String title = "Season Tier Cutoffs (LLR)";

  @override
  String? get description =>
      "Prior-year percentile cutoffs and counts for a rating ladder, plus "
      "within-season threshold churn and Nationals 95% Challenger. "
      "Wide Tiers uses broader metal bands with I/II splits.";

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
        BoolMenuArgument(
          label: "Wide Tiers",
          required: false,
          defaultValue: kDefaultWideTiers,
          description: "On: 60/65 Bronze, 70/75 Silver, 80/85 Gold, then 90, 92.5, 95, 97. "
              "Off: the original 60, 70, 75, 80, 85, 90, 95 ladder.",
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
    final wideTiers = arguments
            .firstWhereOrNull((a) => a.argument.label == "Wide Tiers")
            ?.getAs<bool>() ??
        kDefaultWideTiers;
    await _run(
      db,
      console,
      projectName: kDefaultLlrProjectName,
      startYear: startYear,
      endYear: endYear,
      wideTiers: wideTiers,
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
  required bool wideTiers,
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

  final tiers = _tiersFor(wideTiers);
  final shotsByGroup = <String, Map<int, Map<int, _YearShot>>>{};
  final pathsByGroup = <String, Map<int, Map<int, _YearPath>>>{};
  var ratingsScanned = 0;

  for (final group in groups) {
    final ratingsRes = project.getRatingsSync(group);
    if (ratingsRes.isErr()) {
      console.print("Skipping ${group.name}; failed to load ratings.");
      shotsByGroup[group.uuid] = {};
      pathsByGroup[group.uuid] = {};
      continue;
    }
    final ratings = ratingsRes.unwrap();
    final byYear = <int, Map<int, _YearShot>>{};
    final pathsByYear = <int, Map<int, _YearPath>>{};
    for (var year = cutoffStartYear; year <= endYear; year++) {
      byYear[year] = {};
      pathsByYear[year] = {};
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
      final pointsByYear = <int, List<_StagePoint>>{};
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
        pointsByYear.putIfAbsent(year, () => []).add(_StagePoint(
          key: event.dateAndStageNumber,
          matchId: event.matchId,
          oldRating: event.oldRating,
          newRating: event.newRating,
        ));
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
        final path = _matchEndPath(pointsByYear[year] ?? []);
        if (path != null) {
          pathsByYear[year]![rating.id] = path;
        }
      }
      ratingsScanned++;
    }
    bar.complete();
    shotsByGroup[group.uuid] = byYear;
    pathsByGroup[group.uuid] = pathsByYear;
  }

  final buf = StringBuffer();
  _writeHeader(
    buf,
    projectName: projectName,
    startYear: startYear,
    endYear: endYear,
    wideTiers: wideTiers,
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
  final rules = _RuleBook();

  for (final group in groups) {
    _writeGroup(
      buf,
      algorithm: algorithm,
      tiers: tiers,
      group: group,
      startYear: startYear,
      endYear: endYear,
      shotsByYear: shotsByGroup[group.uuid] ?? {},
      pathsByYear: pathsByGroup[group.uuid] ?? {},
      challengersByYear: challengersByGroup[group.uuid] ?? {},
      totals: totals,
      rules: rules,
      wideTiers: wideTiers,
    );
  }

  _writeTotals(
    buf,
    tiers: wideTiers ? kWideDisplayOrder : tiers,
    startYear: startYear,
    endYear: endYear,
    totals: totals,
  );
  _writeRankRules(buf, rules: rules, startYear: startYear, endYear: endYear);

  final report = buf.toString();
  final reportPath = _reportPath(wideTiers);
  File(reportPath).writeAsStringSync(report);
  console.print(report);
  console.print("Wrote $reportPath");
}

void _writeHeader(
  StringBuffer buf, {
  required String projectName,
  required int startYear,
  required int endYear,
  required bool wideTiers,
  required List<RatingGroup> groups,
  required List<String> nationalsLines,
  required int nationalsLoadErrors,
  required int qualifyingFinishes,
  required int unmappedFinishes,
  required int ratingsScanned,
}) {
  buf.writeln("Project: $projectName");
  buf.writeln("Ladder: ${_ladderName(wideTiers)}");
  if (wideTiers) {
    buf.writeln(
      "Full ladder at $kFullLadderMinField+ in the prior-year cutoff field: "
      "Bronze I 60, Bronze II 65, through Diamond 97. Rank I is the lower step. "
      "At $kRubyLadderMinField–${kFullLadderMinField - 1}: "
      "Bronze I 60, Silver I 70, Gold I 80, Sapphire 90, Ruby 95. "
      "At $kSapphireLadderMinField–${kRubyLadderMinField - 1}: "
      "those three rank-I metals plus Sapphire 90. "
      "Under $kSapphireLadderMinField: no percentile tiers. "
      "A collapsed metal keeps the rank I percentile. Rank II is not awarded.",
    );
  }
  else {
    buf.writeln("Bands: Bronze 60, Silver 70, Gold 75, Sapphire 80, Emerald 85, Ruby 90, Diamond 95.");
  }
  buf.writeln("Groups: ${groups.map((g) => g.name).join(", ")}");
  buf.writeln(
    "Seasons: $startYear–$endYear. "
    "A season's cutoffs are the prior year's percentiles.",
  );
  buf.writeln(
    "Churn: among shooters who can earn a tier, match-end rating went from "
    "at or below a cutoff to above it, then later in the same season back to "
    "at or below. Stage swings inside one match are ignored. "
    "Recovered means the year-end rating is above that cutoff again.",
  );
  buf.writeln(
    "Every match in this project is a major. Shield promotes on the first major "
    "over a line and drops after two majors in a row at or below. Series promotes "
    "only after two majors in a row over a line, and drops after two in a row "
    "at or below. A rating already over the line before the season is confirmed.",
  );
  buf.writeln(
    "Cutoff population: >= $kMinCareerMatchesForCutoff distinct matches through Dec 31 "
    "of that year, and >= 1 match in the year. "
    "Tier population: >= $kMinCareerMatchesForTier career matches and >= 1 match in the year. "
    "Year-end rating is the rating after the last event dated in that year.",
  );
  buf.writeln(
    "Percentile: linear interpolation (position = (n - 1) * p on the sorted cutoff population). "
    "Earn a threshold when year-end rating is strictly above the cutoff. "
    "In Tier is the highest threshold exceeded. "
    "Prior> counts the prior year's cutoff population above that cutoff. "
    "This> and In Tier count this year's tier population.",
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
  required List<_Tier> tiers,
  required RatingGroup group,
  required int startYear,
  required int endYear,
  required Map<int, Map<int, _YearShot>> shotsByYear,
  required Map<int, Map<int, _YearPath>> pathsByYear,
  required Map<int, Set<int>> challengersByYear,
  required Map<int, _SeasonTotals> totals,
  required _RuleBook rules,
  required bool wideTiers,
}) {
  buf.writeln("======== ${group.name} ========");
  for (var year = startYear; year <= endYear; year++) {
    final priorShots = shotsByYear[year - 1] ?? {};
    final thisShots = shotsByYear[year] ?? {};
    final priorEligible = priorShots.values.where((s) => s.setsCutoff).toList();
    final thisEligible = thisShots.values.where((s) => s.earnsTier).toList();
    final priorActive = priorShots.length;
    final thisActive = thisShots.length;
    final thisShortCareer = thisShots.values.where((s) => !s.earnsTier).length;

    buf.writeln("");
    buf.writeln("Season ${_seasonLabel(year)}");
    buf.writeln(
      "  Prior year ${year - 1}: $priorActive with a match, "
      "${priorEligible.length} in the cutoff population"
      "${priorEligible.isEmpty ? "" : ", median ${_fmt(algorithm, _median(priorEligible))}"}",
    );
    buf.writeln(
      "  This year: $thisActive with a match, "
      "${thisEligible.length} can earn a tier, "
      "$thisShortCareer under $kMinCareerMatchesForTier career matches",
    );

    final totalsRow = totals[year]!;
    totalsRow.eligible += thisEligible.length;

    final seasonTiers = wideTiers
        ? _wideTiersForField(priorEligible.length)
        : tiers;
    if (priorEligible.isEmpty || seasonTiers.isEmpty) {
      totalsRow.noCutoff += thisEligible.length;
      if (priorEligible.isEmpty) {
        buf.writeln("  No cutoff population in ${year - 1}; rating cutoffs not set.");
      }
      else {
        buf.writeln(
          "  Cutoff field ${priorEligible.length} is under $kSapphireLadderMinField. "
          "No percentile tiers this season. Challenger still applies.",
        );
      }
      buf.writeln("  LADDER\t${group.name}\t$year\tnone\t${priorEligible.length}");
    }
    else {
      final sortedPrior = priorEligible.map((s) => s.rating).toList()..sort();
      final sortedThis = thisEligible.map((s) => s.rating).toList()..sort();
      final cutoffs = <_Tier, double>{
        for (final tier in seasonTiers) tier: _percentile(sortedPrior, tier.fraction),
      };
      buf.writeln(
        "  Ladder ${_ladderId(seasonTiers)} from cutoff field ${priorEligible.length}.",
      );
      buf.writeln(
        "  LADDER\t${group.name}\t$year\t${_ladderId(seasonTiers)}\t${priorEligible.length}",
      );

      buf.writeln(
        "  ${"Tier".padRight(12)}"
        "${"Pctl".padLeft(6)}"
        "${"Cutoff".padLeft(10)}"
        "${"Prior>".padLeft(9)}"
        "${"This>".padLeft(9)}"
        "${"In Tier".padLeft(9)}",
      );

      final exclusive = <_Tier, int>{for (final tier in seasonTiers) tier: 0};
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

      for (final tier in seasonTiers) {
        final cutoff = cutoffs[tier]!;
        final priorAbove = _countAbove(sortedPrior, cutoff);
        final thisAbove = _countAbove(sortedThis, cutoff);
        final inTier = exclusive[tier]!;
        totalsRow.inTier[tier.name] = (totalsRow.inTier[tier.name] ?? 0) + inTier;
        buf.writeln(
          "  ${tier.name.padRight(12)}"
          "${_pctLabel(tier.percentile).padLeft(6)}"
          "${_fmt(algorithm, cutoff).padLeft(10)}"
          "${priorAbove.toString().padLeft(9)}"
          "${thisAbove.toString().padLeft(9)}"
          "${inTier.toString().padLeft(9)}",
        );
      }
      totalsRow.below += below;
      buf.writeln(
        "  ${"Below".padRight(12)}"
        "${"—".padLeft(6)}"
        "${"—".padLeft(10)}"
        "${"—".padLeft(9)}"
        "${"—".padLeft(9)}"
        "${below.toString().padLeft(9)}",
      );
      _writeShieldTiers(
        buf,
        groupName: group.name,
        year: year,
        algorithm: algorithm,
        tiers: seasonTiers,
        cutoffs: cutoffs,
        thisShots: thisShots,
        paths: pathsByYear[year] ?? {},
      );
      _writeChurn(
        buf,
        tiers: seasonTiers,
        cutoffs: cutoffs,
        thisShots: thisShots,
        paths: pathsByYear[year] ?? {},
        totals: totalsRow,
      );
      _accumulateRankRules(
        rules: rules,
        year: year,
        sortedPrior: sortedPrior,
        thisShots: thisShots,
        paths: pathsByYear[year] ?? {},
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
    if (holders.isNotEmpty && priorEligible.isNotEmpty && seasonTiers.isNotEmpty) {
      final sortedPrior = priorEligible.map((s) => s.rating).toList()..sort();
      final holderTiers = <String, int>{};
      final holderCutoffs = <_Tier, double>{
        for (final tier in seasonTiers) tier: _percentile(sortedPrior, tier.fraction),
      };
      var holderIneligible = 0;
      var holderMissing = 0;
      for (final id in holders) {
        final shot = thisShots[id];
        if (shot == null) {
          holderMissing++;
          continue;
        }
        if (!shot.earnsTier) {
          holderIneligible++;
          continue;
        }
        final path = pathsByYear[year]?[id];
        final ratings = path == null || path.ratings.isEmpty
            ? <double>[shot.rating]
            : path.ratings;
        final tier = wideTiers
            ? _shieldTier(ratings, seasonTiers, holderCutoffs)
            : _highestTier(shot.rating, holderCutoffs);
        final name = tier?.name ?? "Below";
        holderTiers[name] = (holderTiers[name] ?? 0) + 1;
      }
      final parts = <String>[
        for (final tier in seasonTiers)
          if ((holderTiers[tier.name] ?? 0) > 0) "${tier.name} ${holderTiers[tier.name]}",
        if ((holderTiers["Below"] ?? 0) > 0) "Below ${holderTiers["Below"]}",
        if (holderIneligible > 0) "under $kMinCareerMatchesForTier matches $holderIneligible",
        if (holderMissing > 0) "no $year match $holderMissing",
      ];
      buf.writeln("  Challenger holders' $year rating tier: ${parts.join(", ")}");
    }
  }
  _writePendingCutoffs(
    buf,
    algorithm: algorithm,
    groupName: group.name,
    wideTiers: wideTiers,
    classicTiers: tiers,
    pendingYear: endYear + 1,
    shots: shotsByYear[endYear] ?? {},
  );
  buf.writeln("");
}

void _writePendingCutoffs(
  StringBuffer buf, {
  required RatingSystem algorithm,
  required String groupName,
  required bool wideTiers,
  required List<_Tier> classicTiers,
  required int pendingYear,
  required Map<int, _YearShot> shots,
}) {
  final field = shots.values.where((shot) => shot.setsCutoff).toList();
  final pendingTiers = wideTiers ? _wideTiersForField(field.length) : classicTiers;
  buf.writeln("");
  buf.writeln(
    "Season $pendingYear pending, if $groupName ended ${pendingYear - 1} now "
    "(${field.length} in the cutoff field):",
  );
  if (field.isEmpty || pendingTiers.isEmpty) {
    buf.writeln("  No percentile tiers.");
    buf.writeln("  PENDING\t$groupName\t$pendingYear\tnone\t${field.length}");
    return;
  }
  final sorted = field.map((shot) => shot.rating).toList()..sort();
  buf.writeln("  Ladder ${_ladderId(pendingTiers)}.");
  buf.writeln("  PENDING\t$groupName\t$pendingYear\t${_ladderId(pendingTiers)}\t${field.length}");
  for (final tier in pendingTiers) {
    final cutoff = _percentile(sorted, tier.fraction);
    buf.writeln(
      "  ${tier.name.padRight(12)}${_pctLabel(tier.percentile).padLeft(6)}${_fmt(algorithm, cutoff).padLeft(10)}",
    );
    buf.writeln("  PENDING\t$groupName\t$pendingYear\t${tier.name}\t${_fmt(algorithm, cutoff)}");
  }
}

void _writeTotals(
  StringBuffer buf, {
  required List<_Tier> tiers,
  required int startYear,
  required int endYear,
  required Map<int, _SeasonTotals> totals,
}) {
  buf.writeln("======== Division slots, summed (not unique people) ========");
  final nameW = 12;
  buf.write("Season".padRight(12));
  buf.write("CanEarn".padLeft(8));
  for (final tier in tiers) {
    buf.write(tier.name.padLeft(nameW));
  }
  buf.write("Below".padLeft(nameW));
  buf.write("NoCutoff".padLeft(nameW));
  buf.writeln("Challenger".padLeft(12));
  for (var year = startYear; year <= endYear; year++) {
    final row = totals[year]!;
    buf.write(_seasonLabel(year).padRight(12));
    buf.write("${row.eligible}".padLeft(8));
    for (final tier in tiers) {
      buf.write("${row.inTier[tier.name] ?? 0}".padLeft(nameW));
    }
    buf.write("${row.below}".padLeft(nameW));
    buf.write("${row.noCutoff}".padLeft(nameW));
    buf.writeln("${row.challenger}".padLeft(12));
  }
  buf.writeln("");
  buf.writeln("======== Churn slots, summed (dropped / crossed up) ========");
  buf.write("Season".padRight(12));
  for (final tier in tiers) {
    buf.write(tier.name.padLeft(nameW));
  }
  buf.writeln("");
  for (var year = startYear; year <= endYear; year++) {
    final row = totals[year]!;
    buf.write(_seasonLabel(year).padRight(12));
    for (final tier in tiers) {
      final stats = row.churn[tier.name];
      final label = stats == null ? "0/0" : "${stats.dropped}/${stats.crossedUp}";
      buf.write(label.padLeft(nameW));
    }
    buf.writeln("");
  }
  buf.writeln("");
}

class _SeasonTotals {
  int eligible = 0;
  int below = 0;
  int noCutoff = 0;
  int challenger = 0;
  final Map<String, int> inTier = {};
  final Map<String, _ChurnStats> churn = {};
}

class _ChurnStats {
  int crossedUp = 0;
  int dropped = 0;
  int endedBelow = 0;
  int recovered = 0;
}

class _StagePoint {
  const _StagePoint({
    required this.key,
    required this.matchId,
    required this.oldRating,
    required this.newRating,
  });

  final int key;
  final String matchId;
  final double oldRating;
  final double newRating;
}

class _YearPath {
  const _YearPath(this.ratings);

  /// Rating before the first match of the year, then the rating after each
  /// match in that year, in match-end order.
  final List<double> ratings;
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

String _pctLabel(double percentile) {
  if (percentile == percentile.roundToDouble()) {
    return percentile.toStringAsFixed(0);
  }
  return percentile.toStringAsFixed(1);
}

void _writeShieldTiers(
  StringBuffer buf, {
  required String groupName,
  required int year,
  required RatingSystem algorithm,
  required List<_Tier> tiers,
  required Map<_Tier, double> cutoffs,
  required Map<int, _YearShot> thisShots,
  required Map<int, _YearPath> paths,
}) {
  final held = <_Tier, int>{for (final tier in tiers) tier: 0};
  var below = 0;
  for (final entry in thisShots.entries) {
    if (!entry.value.earnsTier) {
      continue;
    }
    final path = paths[entry.key];
    final ratings = path == null || path.ratings.isEmpty
        ? <double>[entry.value.rating]
        : path.ratings;
    final tier = _shieldTier(ratings, tiers, cutoffs);
    if (tier == null) {
      below++;
    }
    else {
      held[tier] = held[tier]! + 1;
    }
  }
  buf.writeln(
    "  Shield held at season end (promote on the first major over a line, "
    "drop after two majors in a row at or below):",
  );
  for (final tier in tiers) {
    buf.writeln(
      "  SHIELD\t$groupName\t$year\t${tier.name}\t${_fmt(algorithm, cutoffs[tier]!)}\t${held[tier]}",
    );
  }
  buf.writeln("  SHIELD\t$groupName\t$year\tBelow\t—\t$below");
}

_Tier? _shieldTier(
  List<double> ratings,
  List<_Tier> tiersHighToLow,
  Map<_Tier, double> cutoffs,
) {
  if (ratings.isEmpty) {
    return null;
  }
  final holding = <_Tier, bool>{};
  final belowStreak = <_Tier, int>{};
  for (final tier in tiersHighToLow) {
    holding[tier] = ratings.first > cutoffs[tier]!;
    belowStreak[tier] = 0;
  }
  for (var i = 1; i < ratings.length; i++) {
    final rating = ratings[i];
    for (final tier in tiersHighToLow) {
      final above = rating > cutoffs[tier]!;
      if (holding[tier]!) {
        if (above) {
          belowStreak[tier] = 0;
        }
        else {
          belowStreak[tier] = belowStreak[tier]! + 1;
          if (belowStreak[tier]! >= 2) {
            holding[tier] = false;
            belowStreak[tier] = 0;
          }
        }
      }
      else if (above) {
        holding[tier] = true;
        belowStreak[tier] = 0;
      }
    }
  }
  for (final tier in tiersHighToLow) {
    if (holding[tier]!) {
      return tier;
    }
  }
  return null;
}

void _writeChurn(
  StringBuffer buf, {
  required List<_Tier> tiers,
  required Map<_Tier, double> cutoffs,
  required Map<int, _YearShot> thisShots,
  required Map<int, _YearPath> paths,
  required _SeasonTotals totals,
}) {
  final earners = <_YearPath>[];
  for (final entry in thisShots.entries) {
    if (!entry.value.earnsTier) {
      continue;
    }
    final path = paths[entry.key];
    if (path != null) {
      earners.add(path);
    }
  }
  buf.writeln(
    "  Churn among ${earners.length} shooters who can earn a tier "
    "(Up, then Dropped, Ended<=, Recovered):",
  );
  buf.writeln(
    "  ${"Threshold".padRight(12)}"
    "${"Up".padLeft(8)}"
    "${"Dropped".padLeft(9)}"
    "${"Ended<=".padLeft(9)}"
    "${"Recovered".padLeft(11)}"
    "${"Drop%".padLeft(8)}",
  );
  for (final tier in tiers) {
    final stats = _churnAt(earners, cutoffs[tier]!);
    final summed = totals.churn.putIfAbsent(tier.name, () => _ChurnStats());
    summed.crossedUp += stats.crossedUp;
    summed.dropped += stats.dropped;
    summed.endedBelow += stats.endedBelow;
    summed.recovered += stats.recovered;
    final dropPct = stats.crossedUp == 0
        ? "—"
        : "${(100.0 * stats.dropped / stats.crossedUp).toStringAsFixed(0)}%";
    buf.writeln(
      "  ${tier.name.padRight(12)}"
      "${stats.crossedUp.toString().padLeft(8)}"
      "${stats.dropped.toString().padLeft(9)}"
      "${stats.endedBelow.toString().padLeft(9)}"
      "${stats.recovered.toString().padLeft(11)}"
      "${dropPct.padLeft(8)}",
    );
  }
}

const List<double> kRulePercentiles = [97, 95, 90, 80, 60];

class _RuleBook {
  final Map<int, _MajorHistogram> majors = {};
  final Map<int, Map<String, Map<String, _RuleRow>>> rows = {};

  _MajorHistogram majorsFor(int year) => majors.putIfAbsent(year, () => _MajorHistogram());

  _RuleRow rowFor(int year, String cohort, String percentile) {
    final byCohort = rows.putIfAbsent(year, () => {});
    final byPercent = byCohort.putIfAbsent(cohort, () => {});
    return byPercent.putIfAbsent(percentile, () => _RuleRow());
  }
}

class _MajorHistogram {
  int one = 0;
  int two = 0;
  int three = 0;
  int fourPlus = 0;
}

class _RuleRow {
  int startedBelow = 0;
  int startedAbove = 0;
  int shieldPromoted = 0;
  int seriesPromoted = 0;
  int aOnly = 0;
  int stranded = 0;
  int failedSeries = 0;
  int shieldSaved = 0;
  int shieldDemoted = 0;
  int seriesDemoted = 0;
  int patternAA = 0;
  int patternAB = 0;
  int patternBA = 0;
  int patternBB = 0;
}

void _accumulateRankRules({
  required _RuleBook rules,
  required int year,
  required List<double> sortedPrior,
  required Map<int, _YearShot> thisShots,
  required Map<int, _YearPath> paths,
}) {
  if (sortedPrior.isEmpty) {
    return;
  }
  final cutoffs = <double, double>{
    for (final percentile in kRulePercentiles)
      percentile: _percentile(sortedPrior, percentile / 100.0),
  };
  final histogram = rules.majorsFor(year);
  for (final entry in thisShots.entries) {
    if (!entry.value.earnsTier) {
      continue;
    }
    final path = paths[entry.key];
    if (path == null || path.ratings.length < 2) {
      continue;
    }
    final majors = path.ratings.length - 1;
    if (majors <= 1) {
      histogram.one++;
    }
    else if (majors == 2) {
      histogram.two++;
    }
    else if (majors == 3) {
      histogram.three++;
    }
    else {
      histogram.fourPlus++;
    }
    final cohort = majors == 2 ? "2" : (majors >= 3 ? "3+" : "1");
    for (final percentile in kRulePercentiles) {
      final label = _pctLabel(percentile);
      final outcome = _applyRankRules(path.ratings, cutoffs[percentile]!);
      _addOutcome(rules.rowFor(year, "all", label), outcome, majors);
      _addOutcome(rules.rowFor(year, cohort, label), outcome, majors);
    }
  }
}

void _addOutcome(_RuleRow row, _RankOutcome outcome, int majors) {
  if (outcome.startedAbove) {
    row.startedAbove++;
  }
  else {
    row.startedBelow++;
    if (outcome.shieldPromoted) {
      row.shieldPromoted++;
    }
    if (outcome.seriesPromoted) {
      row.seriesPromoted++;
    }
    if (outcome.shieldPromoted && !outcome.seriesPromoted) {
      row.aOnly++;
    }
    if (outcome.stranded) {
      row.stranded++;
    }
    if (outcome.failedSeries && !outcome.seriesPromoted) {
      row.failedSeries++;
    }
    if (majors == 2) {
      if (outcome.firstAbove && outcome.secondAbove) {
        row.patternAA++;
      }
      else if (outcome.firstAbove && !outcome.secondAbove) {
        row.patternAB++;
      }
      else if (!outcome.firstAbove && outcome.secondAbove) {
        row.patternBA++;
      }
      else {
        row.patternBB++;
      }
    }
  }
  if (outcome.shieldSaved) {
    row.shieldSaved++;
  }
  if (outcome.shieldDemoted) {
    row.shieldDemoted++;
  }
  if (outcome.seriesDemoted) {
    row.seriesDemoted++;
  }
}

class _RankOutcome {
  bool startedAbove = false;
  bool shieldPromoted = false;
  bool seriesPromoted = false;
  bool stranded = false;
  bool failedSeries = false;
  bool shieldSaved = false;
  bool shieldDemoted = false;
  bool seriesDemoted = false;
  bool firstAbove = false;
  bool secondAbove = false;
}

_RankOutcome _applyRankRules(List<double> ratings, double cutoff) {
  final outcome = _RankOutcome();
  final matches = ratings.sublist(1);
  outcome.startedAbove = ratings.first > cutoff;
  if (matches.isNotEmpty) {
    outcome.firstAbove = matches.first > cutoff;
  }
  if (matches.length > 1) {
    outcome.secondAbove = matches[1] > cutoff;
  }

  var shieldHolding = outcome.startedAbove;
  var shieldBelow = 0;
  for (final rating in matches) {
    final above = rating > cutoff;
    if (shieldHolding) {
      if (above) {
        shieldBelow = 0;
      }
      else {
        shieldBelow++;
        if (shieldBelow >= 2) {
          shieldHolding = false;
          shieldBelow = 0;
          outcome.shieldDemoted = true;
        }
      }
    }
    else if (above) {
      shieldHolding = true;
      shieldBelow = 0;
      outcome.shieldPromoted = true;
    }
  }
  if (shieldHolding && shieldBelow == 1) {
    outcome.shieldSaved = true;
  }

  var seriesHolding = outcome.startedAbove;
  var aboveStreak = 0;
  var belowStreak = 0;
  for (final rating in matches) {
    final above = rating > cutoff;
    if (seriesHolding) {
      if (above) {
        belowStreak = 0;
      }
      else {
        belowStreak++;
        if (belowStreak >= 2) {
          seriesHolding = false;
          belowStreak = 0;
          aboveStreak = 0;
          outcome.seriesDemoted = true;
        }
      }
    }
    else if (above) {
      aboveStreak++;
      belowStreak = 0;
      if (aboveStreak >= 2) {
        seriesHolding = true;
        aboveStreak = 0;
        outcome.seriesPromoted = true;
      }
    }
    else {
      if (aboveStreak == 1) {
        outcome.failedSeries = true;
      }
      aboveStreak = 0;
    }
  }
  if (!seriesHolding && aboveStreak == 1) {
    outcome.stranded = true;
  }
  return outcome;
}

void _writeRankRules(
  StringBuffer buf, {
  required _RuleBook rules,
  required int startYear,
  required int endYear,
}) {
  buf.writeln("======== Rank rules on majors ========");
  buf.writeln(
    "Slots, not unique people. Shield promotes on the first major over the line "
    "and drops after two majors in a row at or below. Series waits for two majors "
    "in a row over the line. Stranded means the season ended on an unconfirmed "
    "promotion major. A only means Shield would show the new rank this season "
    "and Series would not. Patterns AA/AB/BA/BB are the first two majors of "
    "shooters who started the season below the line and shot exactly two majors.",
  );
  buf.writeln("");
  for (var year = startYear; year <= endYear; year++) {
    final histogram = rules.majors[year];
    if (histogram == null) {
      continue;
    }
    buf.writeln(
      "${_seasonLabel(year)} majors among shooters who can earn a tier: "
      "1=${histogram.one}  2=${histogram.two}  "
      "3=${histogram.three}  4+=${histogram.fourPlus}",
    );
    buf.writeln(
      "  ${"Cohort".padRight(8)}"
      "${"Pctl".padLeft(6)}"
      "${"Below".padLeft(8)}"
      "${"Shield".padLeft(8)}"
      "${"Series".padLeft(8)}"
      "${"A only".padLeft(8)}"
      "${"Strand".padLeft(8)}"
      "${"Failed".padLeft(8)}"
      "${"DemSh".padLeft(7)}"
      "${"DemSe".padLeft(7)}"
      "${"AA".padLeft(6)}"
      "${"AB".padLeft(6)}"
      "${"BA".padLeft(6)}"
      "${"BB".padLeft(6)}",
    );
    for (final cohort in ["2", "3+", "1", "all"]) {
      for (final percentile in kRulePercentiles) {
        final label = _pctLabel(percentile);
        final row = rules.rows[year]?[cohort]?[label];
        if (row == null) {
          continue;
        }
        buf.writeln(
          "  ${cohort.padRight(8)}"
          "${label.padLeft(6)}"
          "${row.startedBelow.toString().padLeft(8)}"
          "${row.shieldPromoted.toString().padLeft(8)}"
          "${row.seriesPromoted.toString().padLeft(8)}"
          "${row.aOnly.toString().padLeft(8)}"
          "${row.stranded.toString().padLeft(8)}"
          "${row.failedSeries.toString().padLeft(8)}"
          "${row.shieldDemoted.toString().padLeft(7)}"
          "${row.seriesDemoted.toString().padLeft(7)}"
          "${row.patternAA.toString().padLeft(6)}"
          "${row.patternAB.toString().padLeft(6)}"
          "${row.patternBA.toString().padLeft(6)}"
          "${row.patternBB.toString().padLeft(6)}",
        );
      }
    }
    buf.writeln("");
  }
}

_ChurnStats _churnAt(List<_YearPath> paths, double cutoff) {
  final stats = _ChurnStats();
  for (final path in paths) {
    final ratings = path.ratings;
    if (ratings.length < 2) {
      continue;
    }
    var above = ratings.first > cutoff;
    var didCross = false;
    var didDrop = false;
    for (var i = 1; i < ratings.length; i++) {
      final now = ratings[i] > cutoff;
      if (!above && now) {
        didCross = true;
        above = true;
      }
      else if (above && !now) {
        if (didCross) {
          didDrop = true;
        }
        above = false;
      }
    }
    if (!didCross) {
      continue;
    }
    stats.crossedUp++;
    if (!didDrop) {
      continue;
    }
    stats.dropped++;
    if (ratings.last > cutoff) {
      stats.recovered++;
    }
    else {
      stats.endedBelow++;
    }
  }
  return stats;
}

_YearPath? _matchEndPath(List<_StagePoint> points) {
  if (points.isEmpty) {
    return null;
  }
  final ordered = [...points]..sort((a, b) => a.key.compareTo(b.key));
  final endKey = <String, int>{};
  final endRating = <String, double>{};
  double? start;
  for (final point in ordered) {
    start ??= point.oldRating;
    final previous = endKey[point.matchId];
    if (previous == null || point.key >= previous) {
      endKey[point.matchId] = point.key;
      endRating[point.matchId] = point.newRating;
    }
  }
  if (start == null || endKey.isEmpty) {
    return null;
  }
  final matchIds = endKey.keys.toList()
    ..sort((a, b) => endKey[a]!.compareTo(endKey[b]!));
  return _YearPath([
    start,
    for (final id in matchIds) endRating[id]!,
  ]);
}

double _median(List<_YearShot> shots) {
  final values = shots.map((s) => s.rating).toList()..sort();
  return _percentile(values, 0.5);
}

_Tier? _highestTier(double rating, Map<_Tier, double> cutoffs) {
  for (final entry in cutoffs.entries) {
    if (rating > entry.value) {
      return entry.key;
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
