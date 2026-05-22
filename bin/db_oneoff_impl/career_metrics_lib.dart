/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:io";
import "dart:math";

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart";

class CareerMetricsConfig {
  const CareerMetricsConfig({
    required this.minDataYear,
    required this.durationYears,
    required this.minMatches,
    required this.minYearsTrajectory,
    this.riseThreshold = 0.06,
    this.declineThreshold = 0.06,
    this.plateauBand = 0.04,
    this.betterEpsilon = 0.02,
    this.flatEpsilon = 0.02,
    this.inactiveMonthsThreshold = 18,
    this.survivalMonths = 12,
    this.tenureBinCount = 8,
    this.eraCohortEarlyEndYear = 2019,
    this.eraCohortLateStartYear = 2022,
  });

  final int minDataYear;
  final int durationYears;
  final int minMatches;
  final int minYearsTrajectory;
  final double riseThreshold;
  final double declineThreshold;
  final double plateauBand;
  final double betterEpsilon;
  final double flatEpsilon;
  final int inactiveMonthsThreshold;
  final int survivalMonths;
  final int tenureBinCount;
  final int eraCohortEarlyEndYear;
  final int eraCohortLateStartYear;
}

class ShooterCareerRow {
  ShooterCareerRow({
    required this.ratingId,
    required this.displayName,
    required this.memberNumber,
    required this.currentRating,
    required this.agedRating,
    required this.error,
    required this.dispersion,
    required this.connectivity,
    required this.matchCount,
    required this.stageEventCount,
    required this.distinctMatchIds,
    required this.firstSeen,
    required this.lastSeen,
    required this.monthsInactive,
    required this.activeYears,
    required this.rawByYear,
    required this.adjByYear,
    required this.displayByYear,
    required this.divisionsSeen,
    required this.earlyRating,
    required this.trajectory,
  });

  final int ratingId;
  final String displayName;
  final String memberNumber;
  final double currentRating;
  final double agedRating;
  final double error;
  final double dispersion;
  final double connectivity;
  final int matchCount;
  final int stageEventCount;
  final int distinctMatchIds;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final double monthsInactive;
  final List<int> activeYears;
  final Map<int, double> rawByYear;
  final Map<int, double> adjByYear;
  /// End-of-year rating on the same display scale as [currentRating] (LLR scale when available).
  final Map<int, double> displayByYear;
  final Set<String> divisionsSeen;
  final double earlyRating;
  final TrajectoryShape trajectory;

  int get activeYearCount => activeYears.length;

  int get firstActiveYear => activeYears.first;

  int get lastActiveYear => activeYears.last;

  double get logTenureMatches => log(1 + distinctMatchIds);

  String get eraCohort {
    if (firstActiveYear <= 2019) {
      return "2018-2019";
    }
    if (firstActiveYear >= 2022) {
      return "2022+";
    }
    return "2020-2021";
  }
}

enum TrajectoryShape {
  improvePlateauDecline,
  improvePlateau,
  improvePeakAtEnd,
  improvePlateauQuit,
  declineThenRiseAboveStart,
  weakImprove,
  flat,
  weakDecline,
  improveThenFallBelowStart,
  declinePlateauRise,
  declinePlateau,
  declineTroughAtEnd,
  declinePlateauQuit,
  declineQuit,
  other,
}

class GroupCareerDataset {
  GroupCareerDataset({
    required this.groupLabel,
    required this.rows,
    required this.medianByYear,
    required this.byStage,
    required this.groupHasMultipleDivisions,
  });

  final String groupLabel;
  final List<ShooterCareerRow> rows;
  final Map<int, double> medianByYear;
  final bool byStage;
  final bool groupHasMultipleDivisions;
}

GroupCareerDataset buildGroupCareerDataset({
  required AnalystDatabase db,
  required DbRatingProject project,
  required RatingGroup group,
  required CareerMetricsConfig config,
  LatentLogRater? llrRater,
}) {
  final ratingsRes = project.getRatingsSync(group);
  final byStage = project.settings.byStage;
  final groupHasMultipleDivisions = group.divisions.length > 1;
  if (ratingsRes.isErr()) {
    return GroupCareerDataset(
      groupLabel: group.uiLabel,
      rows: [],
      medianByYear: {},
      byStage: byStage,
      groupHasMultipleDivisions: groupHasMultipleDivisions,
    );
  }

  final ratings = ratingsRes.unwrap();
  final perShooterRaw = <int, Map<int, double>>{};
  final perShooterEvents = <int, List<DbRatingEvent>>{};
  final perShooterMatchIds = <int, Set<String>>{};
  final perShooterStageEvents = <int, int>{};
  final perShooterFirstSeen = <int, DateTime>{};
  final perShooterLastSeen = <int, DateTime>{};
  final perShooterEarly = <int, double>{};
  final matchIdsForDivisions = <String>{};

  for (final r in ratings) {
    final events = _ratingEventsOnOrAfter(db, r, minDataYear: config.minDataYear);
    if (events.isEmpty) {
      continue;
    }

    perShooterEvents[r.id] = events;
    perShooterRaw[r.id] = _endOfYearNewRatingByYear(events);
    perShooterMatchIds[r.id] = events.map((e) => e.matchId).toSet();
    perShooterStageEvents[r.id] = events.where((e) => e.stageNumber >= 0).length;
    perShooterFirstSeen[r.id] = events.first.date;
    perShooterLastSeen[r.id] = events.last.date;
    perShooterEarly[r.id] = events.first.newRating;

    if (groupHasMultipleDivisions) {
      matchIdsForDivisions.addAll(perShooterMatchIds[r.id]!);
    }
  }

  if (perShooterRaw.isEmpty) {
    return GroupCareerDataset(
      groupLabel: group.uiLabel,
      rows: [],
      medianByYear: {},
      byStage: byStage,
      groupHasMultipleDivisions: groupHasMultipleDivisions,
    );
  }

  final divisionByMatchEntry = groupHasMultipleDivisions
      ? _loadMatchEntryDivisionCache(db, matchIdsForDivisions)
      : const <String, Map<int, String>>{};

  final yearsInGroup = perShooterRaw.values.expand((m) => m.keys).toSet().toList()..sort();
  final medianByYear = <int, double>{};
  for (final y in yearsInGroup) {
    final ends = <double>[];
    for (final m in perShooterRaw.values) {
      final v = m[y];
      if (v != null) {
        ends.add(v);
      }
    }
    if (ends.isNotEmpty) {
      medianByYear[y] = _medianUnsorted(ends);
    }
  }

  final now = DateTime.now();
  final rows = <ShooterCareerRow>[];

  for (final r in ratings) {
    final rawByYear = perShooterRaw[r.id];
    if (rawByYear == null || rawByYear.isEmpty) {
      continue;
    }

    final activeYears = rawByYear.keys.toList()..sort();
    final adjByYear = <int, double>{};
    final displayByYear = <int, double>{};
    for (final y in activeYears) {
      final med = medianByYear[y];
      if (med != null) {
        adjByYear[y] = rawByYear[y]! - med;
      }
      displayByYear[y] = llrRater != null
          ? llrRater.scaleRating(rawByYear[y]!)
          : rawByYear[y]!;
    }

    final series = activeYears.map((y) => adjByYear[y]!).toList();
    final trajectory = series.length >= config.minYearsTrajectory
        ? classifyTrajectory(
            series,
            years: activeYears,
            riseThreshold: config.riseThreshold,
            declineThreshold: config.declineThreshold,
            plateauBand: config.plateauBand,
            betterEpsilon: config.betterEpsilon,
            flatEpsilon: config.flatEpsilon,
          )
        : TrajectoryShape.other;

    var displayRating = r.rating;
    var agedRating = r.rating;
    var dispersion = double.nan;
    if (llrRater != null) {
      final wrapped = LatentLogRating.wrapDbRatingWithSettings(llrRater, r);
      displayRating = wrapped.displayRating;
      agedRating = wrapped.displayAgedRating;
      dispersion = wrapped.displayDispersion;
    }

    final divisionsSeen = <String>{};
    if (groupHasMultipleDivisions) {
      for (final e in perShooterEvents[r.id]!) {
        final division = divisionByMatchEntry[e.matchId]?[e.entryId];
        if (division != null && division.isNotEmpty) {
          divisionsSeen.add(division);
        }
      }
    }

    rows.add(
      ShooterCareerRow(
        ratingId: r.id,
        displayName: "${r.firstName} ${r.lastName}".trim(),
        memberNumber: r.knownMemberNumbers.isNotEmpty ? r.knownMemberNumbers.first : "",
        currentRating: displayRating,
        agedRating: agedRating,
        error: r.error,
        dispersion: dispersion,
        connectivity: r.connectivity,
        matchCount: r.length,
        stageEventCount: perShooterStageEvents[r.id] ?? 0,
        distinctMatchIds: perShooterMatchIds[r.id]?.length ?? 0,
        firstSeen: perShooterFirstSeen[r.id]!,
        lastSeen: perShooterLastSeen[r.id]!,
        monthsInactive: _monthsBetween(perShooterLastSeen[r.id]!, now),
        activeYears: activeYears,
        rawByYear: rawByYear,
        adjByYear: adjByYear,
        displayByYear: displayByYear,
        divisionsSeen: divisionsSeen,
        earlyRating: perShooterEarly[r.id]!,
        trajectory: trajectory,
      ),
    );
  }

  return GroupCareerDataset(
    groupLabel: group.uiLabel,
    rows: rows,
    medianByYear: medianByYear,
    byStage: byStage,
    groupHasMultipleDivisions: groupHasMultipleDivisions,
  );
}

TrajectoryShape classifyTrajectory(
  List<double> series, {
  required List<int> years,
  required double riseThreshold,
  required double declineThreshold,
  required double plateauBand,
  required double betterEpsilon,
  required double flatEpsilon,
}) {
  if (series.length < 2 || years.length != series.length) {
    return TrajectoryShape.other;
  }

  final start = series.first;
  final end = series.last;
  if ((end - start).abs() <= flatEpsilon) {
    return TrajectoryShape.flat;
  }

  var peakIdx = 0;
  var peak = series.first;
  var troughIdx = 0;
  var trough = series.first;
  for (var i = 0; i < series.length; i++) {
    if (series[i] > peak) {
      peak = series[i];
      peakIdx = i;
    }
    if (series[i] < trough) {
      trough = series[i];
      troughIdx = i;
    }
  }

  final rise = peak - start;
  final fallFromPeak = peak - end;
  final drop = start - trough;
  final riseFromTrough = end - trough;
  final peakIsLast = peakIdx == series.length - 1;
  final troughIsLast = troughIdx == series.length - 1;
  final yearsAfterPeak = years.last - years[peakIdx];
  final yearsAfterTrough = years.last - years[troughIdx];

  if (end > start + betterEpsilon) {
    if (!troughIsLast &&
        trough < start - betterEpsilon &&
        drop >= declineThreshold &&
        riseFromTrough >= riseThreshold) {
      return TrajectoryShape.declineThenRiseAboveStart;
    }
    if (!peakIsLast && rise >= riseThreshold && fallFromPeak >= declineThreshold) {
      return TrajectoryShape.improvePlateauDecline;
    }
    if (!peakIsLast && rise >= riseThreshold && fallFromPeak < declineThreshold && end >= peak - plateauBand) {
      return TrajectoryShape.improvePlateau;
    }
    if (peakIsLast) {
      return TrajectoryShape.improvePeakAtEnd;
    }
    if (!peakIsLast && rise >= riseThreshold && yearsAfterPeak <= 1 && end >= peak - plateauBand) {
      return TrajectoryShape.improvePlateauQuit;
    }
    return TrajectoryShape.weakImprove;
  }

  if (end < start - betterEpsilon) {
    if (!peakIsLast && rise >= riseThreshold && fallFromPeak >= declineThreshold) {
      return TrajectoryShape.improveThenFallBelowStart;
    }
    if (!troughIsLast && drop >= declineThreshold && riseFromTrough >= riseThreshold) {
      return TrajectoryShape.declinePlateauRise;
    }
    if (!troughIsLast && drop >= declineThreshold && riseFromTrough < riseThreshold && end <= trough + plateauBand) {
      return TrajectoryShape.declinePlateau;
    }
    if (troughIsLast) {
      return TrajectoryShape.declineTroughAtEnd;
    }
    if (!troughIsLast && drop >= declineThreshold && yearsAfterTrough <= 1 && end <= trough + plateauBand) {
      return TrajectoryShape.declinePlateauQuit;
    }
    if (yearsAfterTrough <= 1 && riseFromTrough < riseThreshold) {
      return TrajectoryShape.declineQuit;
    }
    return TrajectoryShape.weakDecline;
  }

  return TrajectoryShape.other;
}

void printGroupCareerReports(Console console, GroupCareerDataset data, CareerMetricsConfig config) {
  if (data.rows.isEmpty) {
    console.print("=== ${data.groupLabel} === (no shooters)");
    console.print("");
    return;
  }

  console.print("=== ${data.groupLabel} ===");
  console.print("Shooters: ${data.rows.length}  byStage=${data.byStage}");
  console.print("");

  _printDurationBetterReport(console, data, config);
  _printTrajectoryReport(console, data, config);
  _printTenureRatingBins(console, data, config);
  _printCorrelations(console, data);
  _printEarlyRatingCareer(console, data, config);
  _printDivisionSwitchers(console, data);
  _printCohortInflation(console, data);
  _printInactiveAged(console, data, config);
  _printStageVsMatchTenure(console, data);
  _printEraCohortBins(console, data, config);
  _printLongitudinalQuantiles(console, data);
  _printSurvivalByDecile(console, data, config);
  console.print("");
}

void printTwoProjectContrast(
  Console console,
  GroupCareerDataset primary,
  GroupCareerDataset compare,
) {
  final compareByMember = <String, ShooterCareerRow>{};
  for (final row in compare.rows) {
    if (row.memberNumber.isEmpty) {
      continue;
    }
    compareByMember.putIfAbsent(row.memberNumber, () => row);
  }

  var matched = 0;
  var primaryRicher = 0;
  var compareRicher = 0;
  final tenureDiffs = <double>[];
  final ratingGaps = <double>[];

  for (final p in primary.rows) {
    if (p.memberNumber.isEmpty) {
      continue;
    }
    final c = compareByMember[p.memberNumber];
    if (c == null) {
      continue;
    }
    matched++;
    final diff = c.distinctMatchIds - p.distinctMatchIds;
    tenureDiffs.add(diff.toDouble());
    ratingGaps.add(p.currentRating - c.currentRating);
    if (diff > 0) {
      compareRicher++;
    }
    else if (diff < 0) {
      primaryRicher++;
    }
  }

  console.print("=== Two-project contrast: ${primary.groupLabel} vs ${compare.groupLabel} ===");
  console.print("Matched by first known member number: $matched");
  if (matched == 0) {
    console.print("");
    return;
  }

  console.print(
    "Tenure (compare − primary matches): median=${_medianUnsorted(tenureDiffs).toStringAsFixed(0)} "
    "mean=${tenureDiffs.average.toStringAsFixed(1)}",
  );
  console.print(
    "Rating gap (primary − compare): median=${_medianUnsorted(ratingGaps).toStringAsFixed(3)} "
    "ρ=${_spearman(tenureDiffs, ratingGaps).toStringAsFixed(3)}",
  );
  console.print(
    "Richer history in compare: $compareRicher (${_pct(compareRicher, matched)}%)  "
    "in primary: $primaryRicher (${_pct(primaryRicher, matched)}%)",
  );
  console.print("");
}

void writeAllCareerCsv(String path, List<GroupCareerDataset> datasets, {required String projectName}) {
  final file = File(path);
  final sink = file.openWrite();
  sink.writeln(
    "project,group,ratingId,name,memberNumber,currentRating,agedRating,error,dispersion,connectivity,"
    "distinctMatches,stageEvents,matchCount,monthsInactive,activeYears,earlyRating,"
    "divisions,trajectory,eraCohort,firstYear,lastYear",
  );
  for (final data in datasets) {
    for (final r in data.rows) {
      sink.writeln(
        "${_csv(projectName)},${_csv(data.groupLabel)},${r.ratingId},${_csv(r.displayName)},${_csv(r.memberNumber)},"
      "${r.currentRating},${r.agedRating},${r.error},${r.dispersion},${r.connectivity},"
      "${r.distinctMatchIds},${r.stageEventCount},${r.matchCount},${r.monthsInactive.toStringAsFixed(1)},"
      "${r.activeYearCount},${r.earlyRating},"
      "${_csv(r.divisionsSeen.join("|"))},${r.trajectory.name},${r.eraCohort},${r.firstActiveYear},${r.lastActiveYear}",
      );
    }
  }
  sink.close();
}

/// One row per (shooter, active calendar year) for trajectory plots. [fieldAdjDisplay] is
/// ratingDisplay − scaled group median that year (same linear structure as CFA console).
void writeCareerTrajectoryLongCsv(
  String path,
  List<GroupCareerDataset> datasets, {
  required String projectName,
  LatentLogRater? llrRater,
}) {
  final file = File(path);
  final sink = file.openWrite();
  sink.writeln(
    "project,group,ratingId,memberNumber,name,trajectory,activeYearCount,distinctMatches,"
    "calendarYear,careerAge,rawLlR,ratingDisplay,fieldMedianDisplay,fieldAdjDisplay",
  );
  for (final data in datasets) {
    for (final r in data.rows) {
      if (r.activeYears.length < 2) {
        continue;
      }
      for (final y in r.activeYears) {
        final raw = r.rawByYear[y];
        final rd = r.displayByYear[y];
        final medRaw = data.medianByYear[y];
        if (raw == null || rd == null || medRaw == null) {
          continue;
        }
        final medDisplay = llrRater != null ? llrRater.scaleRating(medRaw) : medRaw;
        final adjD = rd - medDisplay;
        final careerAge = y - r.firstActiveYear;
        sink.writeln(
          "${_csv(projectName)},${_csv(data.groupLabel)},${r.ratingId},${_csv(r.memberNumber)},${_csv(r.displayName)},"
          "${r.trajectory.name},${r.activeYearCount},${r.distinctMatchIds},"
          "$y,$careerAge,$raw,$rd,$medDisplay,$adjD",
        );
      }
    }
  }
  sink.close();
}

void _printDurationBetterReport(Console console, GroupCareerDataset data, CareerMetricsConfig config) {
  var eligible = 0;
  var better = 0;
  for (final r in data.rows) {
    if (r.distinctMatchIds < config.minMatches) {
      continue;
    }
    final endYear = r.firstActiveYear + config.durationYears - 1;
    if (r.lastActiveYear < endYear) {
      continue;
    }
    final rawStart = r.rawByYear[r.firstActiveYear];
    final rawEnd = r.rawByYear[endYear];
    final medStart = data.medianByYear[r.firstActiveYear];
    final medEnd = data.medianByYear[endYear];
    if (rawStart == null || rawEnd == null || medStart == null || medEnd == null) {
      continue;
    }
    eligible++;
    if ((rawEnd - medEnd) > (rawStart - medStart) + config.betterEpsilon) {
      better++;
    }
  }
  console.print("--- Duration-X (field-adjusted better vs own start) ---");
  console.print("Eligible (≥${config.minMatches} matches, active through first+${config.durationYears - 1}): $eligible");
  if (eligible > 0) {
    console.print("P(better | eligible): $better/$eligible (${_pct(better, eligible)}%)");
  }
  console.print("");
}

void _printTrajectoryReport(Console console, GroupCareerDataset data, CareerMetricsConfig config) {
  final eligible = data.rows.where((r) => r.activeYearCount >= config.minYearsTrajectory).toList();
  console.print("--- Trajectories (≥${config.minYearsTrajectory} active years, field-adjusted annual) ---");
  console.print("Sample: ${eligible.length}");
  if (eligible.isEmpty) {
    console.print("");
    return;
  }

  final counts = <TrajectoryShape, int>{};
  for (final r in eligible) {
    counts[r.trajectory] = (counts[r.trajectory] ?? 0) + 1;
  }

  void line(String label, TrajectoryShape shape) {
    final n = counts[shape] ?? 0;
    console.print("  $label: $n (${_pct(n, eligible.length)}%)");
  }

  line("Improve → plateau → decline", TrajectoryShape.improvePlateauDecline);
  line("Improve → plateau", TrajectoryShape.improvePlateau);
  line("Improve → plateau → quit (≤1 yr after peak)", TrajectoryShape.improvePlateauQuit);
  line("Improve, peak at last active year", TrajectoryShape.improvePeakAtEnd);
  line("Decline below start → rise above start (net up)", TrajectoryShape.declineThenRiseAboveStart);
  line("Weak improve (net up)", TrajectoryShape.weakImprove);
  line("Flat (|Δ| ≤ ${config.flatEpsilon})", TrajectoryShape.flat);
  line("Weak decline (net down)", TrajectoryShape.weakDecline);
  line("Rise above start → fall below start (net down)", TrajectoryShape.improveThenFallBelowStart);
  line("Decline → recover (net still down)", TrajectoryShape.declinePlateauRise);
  line("Decline → plateau", TrajectoryShape.declinePlateau);
  line("Decline → plateau → quit (≤1 yr after trough)", TrajectoryShape.declinePlateauQuit);
  line("Decline → quit (trough late, little recovery)", TrajectoryShape.declineQuit);
  line("Decline, trough at last active year", TrajectoryShape.declineTroughAtEnd);
  line("Other / short series", TrajectoryShape.other);
  console.print("");
}

void _printTenureRatingBins(Console console, GroupCareerDataset data, CareerMetricsConfig config) {
  console.print("--- Tenure vs rating (log(1+matches) bins: median, Q1, Q3, N) ---");
  _printBinnedTable(
    console,
    data.rows,
    valueOf: (r) => r.logTenureMatches,
    metricOf: (r) => r.currentRating,
    binCount: config.tenureBinCount,
  );
  console.print("ρ(tenure, rating)=${_spearman(data.rows.map((r) => r.logTenureMatches).toList(), data.rows.map((r) => r.currentRating).toList()).toStringAsFixed(3)}");
  console.print("");
}

void _printCorrelations(Console console, GroupCareerDataset data) {
  final tenure = data.rows.map((r) => r.logTenureMatches).toList();
  console.print("--- Tenure vs estimate tightness (LLR) ---");
  final withDisp = data.rows.where((r) => !r.dispersion.isNaN).toList();
  if (withDisp.isNotEmpty) {
    console.print(
      "ρ(tenure, dispersion)=${_spearman(withDisp.map((r) => r.logTenureMatches).toList(), withDisp.map((r) => r.dispersion).toList()).toStringAsFixed(3)} "
      "(often rises with tenure; variance/error is the primary certainty measure until rating is well known)",
    );
  }
  console.print(
    "ρ(tenure, error)=${_spearman(tenure, data.rows.map((r) => r.error).toList()).toStringAsFixed(3)} "
    "(negative ⇒ more events, tighter rating estimate)  "
    "ρ(tenure, connectivity)=${_spearman(tenure, data.rows.map((r) => r.connectivity).toList()).toStringAsFixed(3)}",
  );
  console.print("");
}

void _printEarlyRatingCareer(Console console, GroupCareerDataset data, CareerMetricsConfig config) {
  console.print("--- Early rating vs career length ---");
  final early = data.rows.map((r) => r.earlyRating).toList();
  final matches = data.rows.map((r) => r.distinctMatchIds.toDouble()).toList();
  console.print(
    "ρ(early rating, distinct matches)=${_spearman(early, matches).toStringAsFixed(3)}  "
    "ρ(early rating, active years)=${_spearman(early, data.rows.map((r) => r.activeYearCount.toDouble()).toList()).toStringAsFixed(3)}",
  );

  final slices = _earlyRatingDecileSlices(data.rows);
  if (slices == null) {
    console.print("");
    return;
  }
  console.print(
    "Decile (first-event rating)   N   Early lo→hi   Med early   Med matches   Med yrs",
  );
  for (var d = 0; d < slices.length; d++) {
    final slice = slices[d];
    final earlyVals = slice.map((r) => r.earlyRating).toList();
    final medMatches = _medianUnsorted(slice.map((r) => r.distinctMatchIds.toDouble()).toList());
    final medYears = _medianUnsorted(slice.map((r) => r.activeYearCount.toDouble()).toList());
    console.print(
      "${(d + 1).toString().padLeft(2)}                           "
      "${slice.length.toString().padLeft(4)}   "
      "${_earlyRatingDecileRange(slice).padLeft(11)}   "
      "${_medianUnsorted(earlyVals).toStringAsFixed(3).padLeft(8)}   "
      "${medMatches.toStringAsFixed(0).padLeft(8)}   "
      "${medYears.toStringAsFixed(0).padLeft(5)}",
    );
  }
  console.print("");
}

void _printDivisionSwitchers(Console console, GroupCareerDataset data) {
  if (!data.groupHasMultipleDivisions) {
    return;
  }

  // Match level / classifier mix omitted: current ingest is major-match-heavy and not comparable across locals.
  console.print("--- Division switching (multi-division rating group only) ---");
  final switchers = data.rows.where((r) => r.divisionsSeen.length > 1).toList();
  final singleDiv = data.rows.where((r) => r.divisionsSeen.length == 1).toList();
  console.print(
    "≥2 divisions seen in match entries: ${switchers.length} (${_pct(switchers.length, data.rows.length)}%)",
  );
  if (switchers.isNotEmpty && singleDiv.isNotEmpty) {
    console.print(
      "  Median matches: switchers=${_medianUnsorted(switchers.map((r) => r.distinctMatchIds.toDouble()).toList()).toStringAsFixed(0)} "
      "single-division=${_medianUnsorted(singleDiv.map((r) => r.distinctMatchIds.toDouble()).toList()).toStringAsFixed(0)}",
    );
    console.print(
      "  Median rating: switchers=${_medianUnsorted(switchers.map((r) => r.currentRating).toList()).toStringAsFixed(3)} "
      "single-division=${_medianUnsorted(singleDiv.map((r) => r.currentRating).toList()).toStringAsFixed(3)}",
    );
  }
  console.print("");
}

void _printCohortInflation(Console console, GroupCareerDataset data) {
  console.print("--- New-entrant cohort (first active year → early rating) ---");
  final byFirstYear = groupBy(data.rows, (r) => r.firstActiveYear);
  final years = byFirstYear.keys.toList()..sort();
  console.print("FirstYr   N   Med early   Q1 early   Q3 early");
  for (final y in years) {
    final slice = byFirstYear[y]!;
    final vals = slice.map((r) => r.earlyRating).toList()..sort();
    console.print(
      "$y   ${slice.length.toString().padLeft(4)}   "
      "${_medianSorted(vals).toStringAsFixed(3).padLeft(8)}   "
      "${_percentileSorted(vals, 0.25).toStringAsFixed(3).padLeft(8)}   "
      "${_percentileSorted(vals, 0.75).toStringAsFixed(3).padLeft(8)}",
    );
  }
  console.print("");
}

void _printInactiveAged(Console console, GroupCareerDataset data, CareerMetricsConfig config) {
  final inactive = data.rows.where((r) => r.monthsInactive >= config.inactiveMonthsThreshold).toList();
  console.print("--- Inactive-but-rated (≥${config.inactiveMonthsThreshold} mo since last event) ---");
  console.print("Count: ${inactive.length} (${_pct(inactive.length, data.rows.length)}% of group)");
  if (inactive.isEmpty) {
    console.print("");
    return;
  }
  final gaps = inactive.map((r) => r.agedRating - r.currentRating).toList();
  console.print(
    "Aged − raw rating: median=${_medianUnsorted(gaps).toStringAsFixed(3)} "
    "mean=${gaps.average.toStringAsFixed(3)} (negative ⇒ mean reversion pulled rating down)",
  );
  final longHistory = inactive.where((r) => r.distinctMatchIds >= config.minMatches).toList();
  if (longHistory.isNotEmpty) {
    console.print(
      "Long-history inactive (≥${config.minMatches} matches): ${longHistory.length}, "
      "median gap=${_medianUnsorted(longHistory.map((r) => r.agedRating - r.currentRating).toList()).toStringAsFixed(3)}",
    );
  }
  console.print("");
}

void _printStageVsMatchTenure(Console console, GroupCareerDataset data) {
  if (!data.byStage) {
    console.print("--- Stage vs match volume (project not byStage) --- skipped");
    console.print("");
    return;
  }
  console.print("--- Stage events vs distinct matches (byStage project) ---");
  final matches = data.rows.map((r) => r.distinctMatchIds.toDouble()).toList();
  final stages = data.rows.map((r) => r.stageEventCount.toDouble()).toList();
  console.print(
    "ρ(matches, stage events)=${_spearman(matches, stages).toStringAsFixed(3)}  "
    "median stages/match=${_medianUnsorted(data.rows.map((r) => r.stageEventCount / max(1, r.distinctMatchIds)).toList()).toStringAsFixed(2)}",
  );
  console.print("");
}

void _printEraCohortBins(Console console, GroupCareerDataset data, CareerMetricsConfig config) {
  console.print("--- Era cohort (first active year) vs rating by tenure bin ---");
  final cohorts = ["2018-2019", "2020-2021", "2022+"];
  for (final label in cohorts) {
    final slice = data.rows.where((r) => r.eraCohort == label).toList();
    if (slice.isEmpty) {
      continue;
    }
    console.print("Cohort $label (n=${slice.length}):");
    _printBinnedTable(console, slice, valueOf: (r) => r.logTenureMatches, metricOf: (r) => r.currentRating, binCount: min(6, config.tenureBinCount), indent: "  ");
  }
  console.print("");
}

void _printLongitudinalQuantiles(Console console, GroupCareerDataset data) {
  console.print("--- Longitudinal field-adjusted rating by career age (years since first active) ---");
  final byAge = <int, List<double>>{};
  for (final r in data.rows) {
    for (final y in r.activeYears) {
      final age = y - r.firstActiveYear;
      final adj = r.adjByYear[y];
      if (adj == null) {
        continue;
      }
      byAge.putIfAbsent(age, () => []).add(adj);
    }
  }
  final ages = byAge.keys.toList()..sort();
  final maxAge = ages.isEmpty ? 0 : min(ages.last, 12);
  console.print("CareerAge   N   Median   Q1       Q3");
  for (var age = 0; age <= maxAge; age++) {
    final vals = byAge[age];
    if (vals == null || vals.isEmpty) {
      continue;
    }
    final sorted = [...vals]..sort();
    console.print(
      "${age.toString().padLeft(4)}   ${sorted.length.toString().padLeft(4)}   "
      "${_medianSorted(sorted).toStringAsFixed(3).padLeft(7)}   "
      "${_percentileSorted(sorted, 0.25).toStringAsFixed(3).padLeft(7)}   "
      "${_percentileSorted(sorted, 0.75).toStringAsFixed(3).padLeft(7)}",
    );
  }
  console.print("");
}

void _printSurvivalByDecile(Console console, GroupCareerDataset data, CareerMetricsConfig config) {
  console.print("--- Retention: active ≥${config.survivalMonths} months after first match ---");
  final slices = _earlyRatingDecileSlices(data.rows);
  if (slices == null) {
    console.print("(too few shooters)");
    console.print("");
    return;
  }
  console.print("Decile   N   Early lo→hi   Med early   Survived   P(survive)");
  for (var d = 0; d < slices.length; d++) {
    final slice = slices[d];
    final earlyVals = slice.map((r) => r.earlyRating).toList();
    var survived = 0;
    for (final r in slice) {
      final cutoff = r.firstSeen.add(Duration(days: config.survivalMonths * 30));
      if (r.lastSeen.isAfter(cutoff) || r.lastSeen.isAtSameMomentAs(cutoff)) {
        survived++;
      }
    }
    console.print(
      "${(d + 1).toString().padLeft(2)}     ${slice.length.toString().padLeft(4)}   "
      "${_earlyRatingDecileRange(slice).padLeft(11)}   "
      "${_medianUnsorted(earlyVals).toStringAsFixed(3).padLeft(8)}   "
      "${survived.toString().padLeft(6)}   ${_pct(survived, slice.length)}%",
    );
  }
  console.print("");
}

void _printBinnedTable(
  Console console,
  List<ShooterCareerRow> rows, {
  required double Function(ShooterCareerRow) valueOf,
  required double Function(ShooterCareerRow) metricOf,
  required int binCount,
  String indent = "",
}) {
  if (rows.isEmpty) {
    return;
  }
  final values = rows.map(valueOf).toList();
  final minV = values.reduce(min);
  final maxV = values.reduce(max);
  if (minV == maxV) {
    console.print("${indent}(all same tenure bin)");
    return;
  }

  final bins = List.generate(binCount, (_) => <double>[]);
  for (final r in rows) {
    final v = valueOf(r);
    var idx = ((v - minV) / (maxV - minV) * binCount).floor();
    if (idx >= binCount) {
      idx = binCount - 1;
    }
    bins[idx].add(metricOf(r));
  }

  console.print("${indent}BinLo→Hi      N   Median   Q1       Q3");
  for (var i = 0; i < binCount; i++) {
    if (bins[i].isEmpty) {
      continue;
    }
    final lo = minV + (maxV - minV) * i / binCount;
    final hi = minV + (maxV - minV) * (i + 1) / binCount;
    final sorted = [...bins[i]]..sort();
    console.print(
      "${indent}${lo.toStringAsFixed(2)}–${hi.toStringAsFixed(2)}  "
      "${sorted.length.toString().padLeft(4)}   "
      "${_medianSorted(sorted).toStringAsFixed(3).padLeft(7)}   "
      "${_percentileSorted(sorted, 0.25).toStringAsFixed(3).padLeft(7)}   "
      "${_percentileSorted(sorted, 0.75).toStringAsFixed(3).padLeft(7)}",
    );
  }
}

/// entryId → division name for each match, loaded once per distinct matchId.
Map<String, Map<int, String>> _loadMatchEntryDivisionCache(AnalystDatabase db, Set<String> matchIds) {
  final cache = <String, Map<int, String>>{};
  for (final id in matchIds) {
    final m = db.getMatchByAnySourceIdSync([id]);
    if (m == null) {
      continue;
    }
    final entries = <int, String>{};
    for (final entry in m.shooters) {
      final division = entry.divisionName;
      if (division != null && division.isNotEmpty) {
        entries[entry.entryId] = division;
      }
    }
    cache[id] = entries;
  }
  return cache;
}

/// Filtered rating events via Isar query (does not load the full events link into memory).
List<DbRatingEvent> _ratingEventsOnOrAfter(
  AnalystDatabase db,
  DbShooterRating rating, {
  required int minDataYear,
}) {
  return db.getRatingEventsForSync(
    rating,
    after: DateTime(minDataYear),
    order: Order.ascending,
  );
}

Map<int, double> _endOfYearNewRatingByYear(List<DbRatingEvent> sortedEvents) {
  final byYear = <int, DbRatingEvent>{};
  for (final e in sortedEvents) {
    final y = e.date.year;
    final prev = byYear[y];
    if (prev == null) {
      byYear[y] = e;
    }
    else if (_isEventAfterInTimeline(e, prev)) {
      byYear[y] = e;
    }
  }
  return byYear.map((k, v) => MapEntry(k, v.newRating));
}

bool _isEventAfterInTimeline(DbRatingEvent a, DbRatingEvent b) {
  final c = a.date.compareTo(b.date);
  if (c > 0) {
    return true;
  }
  if (c < 0) {
    return false;
  }
  return a.dateAndStageNumber >= b.dateAndStageNumber;
}

double _monthsBetween(DateTime from, DateTime to) {
  return (to.difference(from).inDays / 30.4375);
}

/// Equal-count deciles by [ShooterCareerRow.earlyRating] (first event `newRating`).
List<List<ShooterCareerRow>>? _earlyRatingDecileSlices(List<ShooterCareerRow> rows) {
  if (rows.length < 10) {
    return null;
  }
  final sorted = [...rows]..sort((a, b) => a.earlyRating.compareTo(b.earlyRating));
  final decileSize = (sorted.length / 10).ceil();
  final slices = <List<ShooterCareerRow>>[];
  for (var d = 0; d < 10; d++) {
    final start = d * decileSize;
    if (start >= sorted.length) {
      break;
    }
    final end = min(start + decileSize, sorted.length);
    slices.add(sorted.sublist(start, end));
  }
  return slices;
}

String _earlyRatingDecileRange(List<ShooterCareerRow> slice) {
  final vals = slice.map((r) => r.earlyRating).toList()..sort();
  return "${vals.first.toStringAsFixed(3)}–${vals.last.toStringAsFixed(3)}";
}

double _medianUnsorted(List<double> values) {
  if (values.isEmpty) {
    return double.nan;
  }
  final sorted = [...values]..sort();
  return _medianSorted(sorted);
}

double _medianSorted(List<double> sorted) {
  if (sorted.isEmpty) {
    return double.nan;
  }
  if (sorted.length == 1) {
    return sorted.first;
  }
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

double _percentileSorted(List<double> sorted, double p) {
  if (sorted.isEmpty) {
    return double.nan;
  }
  if (sorted.length == 1) {
    return sorted.first;
  }
  final pos = (sorted.length - 1) * p.clamp(0.0, 1.0);
  final lo = pos.floor();
  final hi = pos.ceil();
  if (lo == hi) {
    return sorted[lo];
  }
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

double _spearman(List<double> x, List<double> y) {
  if (x.length != y.length || x.length < 3) {
    return double.nan;
  }
  final rx = _rank(x);
  final ry = _rank(y);
  return _pearson(rx, ry);
}

List<double> _rank(List<double> values) {
  final indexed = values.indexed.toList()
    ..sort((a, b) => a.$2.compareTo(b.$2));
  final ranks = List<double>.filled(values.length, 0);
  var i = 0;
  while (i < indexed.length) {
    var j = i;
    while (j + 1 < indexed.length && indexed[j + 1].$2 == indexed[i].$2) {
      j++;
    }
    final avgRank = (i + j) / 2.0 + 1.0;
    for (var k = i; k <= j; k++) {
      ranks[indexed[k].$1] = avgRank;
    }
    i = j + 1;
  }
  return ranks;
}

double _pearson(List<double> x, List<double> y) {
  final n = x.length;
  final mx = x.average;
  final my = y.average;
  var num = 0.0;
  var dx = 0.0;
  var dy = 0.0;
  for (var i = 0; i < n; i++) {
    final a = x[i] - mx;
    final b = y[i] - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  if (dx == 0 || dy == 0) {
    return double.nan;
  }
  return num / sqrt(dx * dy);
}

String _pct(int n, int total) => total == 0 ? "0.0" : (100.0 * n / total).toStringAsFixed(1);

String _csv(String s) {
  if (s.contains(",") || s.contains("\"") || s.contains("\n")) {
    return "\"${s.replaceAll("\"", "\"\"")}\"";
  }
  return s;
}
