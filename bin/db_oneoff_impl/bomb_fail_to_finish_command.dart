/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// How often competitors bomb a match or fail to finish, per division.
///
/// A **bomb** is a completed match finish well below the rating-implied
/// expectation: actual ratio vs winner is less than [bombRatio] times
/// `exp(r_i - r_max)`, where ratings are pre-match LLR internal log units
/// and `r_max` is the highest-rated competitor in that division at the match.
/// Default [bombRatio] 0.85 is about 16 display points at scale factor 100
/// (`exp(-16/100) ≈ 0.85`).
///
/// **DQ** is `MatchEntry.dq`. **DNF** is two or more DNF stages that count in
/// ratings (chrono / ignored scoring excluded) and is not also a DQ. A
/// one-stage DNF can still count as a bomb. DQ and DNF are mutually exclusive
/// in the rates; someone who DQs is counted only as DQ even if remaining
/// stages are empty.
///
/// The sample is every division appearance that meets [minMatches] (unrated
/// count as 0 prior matches). Bombs require a rating and a completed match;
/// DQ and DNF appearances are excluded from the bomb denominator.
///
/// Rates are also split by 10-point pre-match **display** rating buckets
/// (`floor(display / 10) * 10`).
///
/// Appearances need at least [minMatches] distinct rated matches **before**
/// this one (default 2: the shooter's 3rd+ match in the project).
///
/// Launch: dart run bin/db_oneoffs.dart BF <startYear> <endYear> [project]
/// Example: BF 2022 2026

import "dart:math" as math;

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_settings.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const int kDefaultStartYear = 2022;
const double kDefaultBombRatio = 0.85;
const int kDefaultMinN = 8;
const int kDefaultMinMatches = 2;
const int kMaxListedCases = 15;
const int kDisplayBucketWidth = 10;

class BombFailToFinishCommand extends DbOneoffCommand {
  BombFailToFinishCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "BF";

  @override
  final String title = "Bomb / Fail-to-Finish Rates";

  @override
  String? get description =>
      "Per-division rates of rating bombs (~15% below expected), DQ, and "
      "multi-stage DNF for the full rated field.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Start year",
          required: true,
          defaultValue: kDefaultStartYear,
          description: "Inclusive start of the match-date year range.",
        ),
        IntMenuArgument(
          label: "End year",
          required: true,
          defaultValueFactory: () => DateTime.now().year,
          description: "Inclusive end of the match-date year range.",
        ),
        StringMenuArgument(
          label: "Project name",
          required: false,
          defaultValue: kDefaultLlrProjectName,
          description: "Rating project (LLR recommended).",
        ),
        StringMenuArgument(
          label: "Bomb ratio",
          required: false,
          defaultValue: kDefaultBombRatio.toString(),
          description:
              "Actual/expected finish ratio below this counts as a bomb "
              "(default 0.85 ≈ 15% / 16 display points).",
        ),
        IntMenuArgument(
          label: "Min N",
          required: false,
          defaultValue: kDefaultMinN,
          description:
              "Minimum competitors in a division (after reentry filter) "
              "to count the match.",
        ),
        IntMenuArgument(
          label: "Min matches",
          required: false,
          defaultValue: kDefaultMinMatches,
          description:
              "Minimum distinct rated matches already in the project "
              "before this appearance (default 2). 0 disables.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final startYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "Start year")
            ?.getAs<int>() ??
        kDefaultStartYear;
    final endYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "End year")
            ?.getAs<int>() ??
        DateTime.now().year;
    final projectName = arguments
            .firstWhereOrNull((a) => a.argument.label == "Project name")
            ?.getAs<String>()
            .trim() ??
        kDefaultLlrProjectName;
    final bombRaw = arguments
            .firstWhereOrNull((a) => a.argument.label == "Bomb ratio")
            ?.getAs<String>()
            .trim() ??
        "";
    final minN = arguments
            .firstWhereOrNull((a) => a.argument.label == "Min N")
            ?.getAs<int>() ??
        kDefaultMinN;
    final minMatches = arguments
            .firstWhereOrNull((a) => a.argument.label == "Min matches")
            ?.getAs<int>() ??
        kDefaultMinMatches;

    final bombRatio = double.tryParse(
          bombRaw.isEmpty ? kDefaultBombRatio.toString() : bombRaw,
        ) ??
        kDefaultBombRatio;

    if (startYear > endYear) {
      console.print("Start year ($startYear) must be <= end year ($endYear).");
      return;
    }
    if (bombRatio <= 0 || bombRatio >= 1.0) {
      console.print("Bomb ratio should be in (0, 1), e.g. 0.85 (got: $bombRatio).");
      return;
    }
    if (minN < 3) {
      console.print("Min N must be at least 3 (got $minN).");
      return;
    }
    if (minMatches < 0) {
      console.print("Min matches must be >= 0 (got $minMatches).");
      return;
    }

    await _run(
      db,
      console,
      projectName: projectName.isEmpty ? kDefaultLlrProjectName : projectName,
      startYear: startYear,
      endYear: endYear,
      bombRatio: bombRatio,
      minN: minN,
      minMatches: minMatches,
    );
  }
}

class _Counts {
  int eligible = 0;
  int unratedEligible = 0;
  int bombEligible = 0;
  int bombs = 0;
  int dq = 0;
  int dnf = 0;
  int mishap = 0;
  int divisionMatches = 0;
  int shortFields = 0;
  int lowHistory = 0;
  final residuals = <double>[];
  /// Lower bound of a 10-point display-rating bucket → outcome counts.
  final byDisplayBucket = <int, _BucketCounts>{};
}

class _BucketCounts {
  int eligible = 0;
  int bombEligible = 0;
  int bombs = 0;
  int dq = 0;
  int dnf = 0;
  int mishap = 0;
}

class _Case {
  _Case({
    required this.matchName,
    required this.date,
    required this.groupLabel,
    required this.shooterName,
    required this.actualRatio,
    required this.expectedRatio,
    required this.residual,
    required this.dq,
    required this.dnfStages,
  });

  final String matchName;
  final DateTime date;
  final String groupLabel;
  final String shooterName;
  final double actualRatio;
  final double expectedRatio;
  final double residual;
  final bool dq;
  final int dnfStages;

  String get dateLabel => date.toIso8601String().split("T").first;
}

class _Row {
  _Row({
    required this.entry,
    required this.rel,
    required this.dnfStages,
    required this.failedToFinish,
    this.preRating,
    this.priorMatches = 0,
  });

  final MatchEntry entry;
  final RelativeMatchScore rel;
  final int dnfStages;
  final bool failedToFinish;
  final double? preRating;
  final int priorMatches;

  bool get rated => preRating != null;
  double get ratio => rel.ratio;
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required int startYear,
  required int endYear,
  required double bombRatio,
  required int minN,
  required int minMatches,
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

  final pointers = project.matchPointers
      .where((p) => p.date != null && p.date!.year >= startYear && p.date!.year <= endYear)
      .toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));
  if (pointers.isEmpty) {
    console.print("No matches in $projectName for $startYear–$endYear.");
    return;
  }

  final isLlr = project.settings.algorithm is LatentLogRater;
  if (!isLlr) {
    console.print(
      "Warning: $projectName is not an LLR project. "
      "Bomb math assumes internal log-ratio ratings (exp(r_i - r_max)).",
    );
  }
  var scaleFactor = LatentLogSettings.defaultScaleFactor;
  var scaleOffset = LatentLogSettings.defaultScaleOffset;
  final algo = project.settings.algorithm;
  if (algo is LatentLogRater) {
    scaleFactor = algo.settings.scaleFactor;
    scaleOffset = algo.settings.scaleOffset;
  }
  final bombLog = math.log(bombRatio);
  final bombDisplayPts = -bombLog * scaleFactor;

  final overall = _Counts();
  final byGroup = <String, _Counts>{
    for (final g in groups) g.uiLabel: _Counts(),
  };
  final byYear = <int, _Counts>{};
  final wrapCache = <int, ShooterRating>{};
  final bombCases = <_Case>[];
  final dqCases = <_Case>[];
  final dnfCases = <_Case>[];

  var loadErrors = 0;
  var hydrateErrors = 0;
  var matchesScored = 0;

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    canHaveErrors: true,
    initialLabel: "Scanning matches for bombs / fail-to-finish…",
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
    final match = hydrated.unwrap();
    matchesScored++;

    for (final group in groups) {
      _processGroup(
        db: db,
        project: project,
        match: match,
        group: group,
        wrapCache: wrapCache,
        bombLog: bombLog,
        minN: minN,
        minMatches: minMatches,
        scaleFactor: scaleFactor,
        scaleOffset: scaleOffset,
        overall: overall,
        groupCounts: byGroup[group.uiLabel]!,
        yearCounts: byYear.putIfAbsent(match.date.year, () => _Counts()),
        bombCases: bombCases,
        dqCases: dqCases,
        dnfCases: dnfCases,
      );
    }
  }

  bar.complete();

  bombCases.sort((a, b) => a.residual.compareTo(b.residual));
  dqCases.sort((a, b) => b.dnfStages.compareTo(a.dnfStages));
  dnfCases.sort((a, b) => b.dnfStages.compareTo(a.dnfStages));

  final buf = StringBuffer()
    ..writeln("=== Bomb / Fail-to-Finish Rates ===")
    ..writeln("Project: $projectName")
    ..writeln("Years: $startYear–$endYear")
    ..writeln("Matches scored: $matchesScored  (load errors $loadErrors, hydrate errors $hydrateErrors)")
    ..writeln("Groups: per-division only (divisionNames.length == 1)")
    ..writeln("Identity: maybeKnownShooterSync(usePossibleMemberNumbers: true)")
    ..writeln("Pre-match rating: ratingForEvent(beforeMatch: true)")
    ..writeln("")
    ..writeln(
      "Bomb: completed match, actual/expected < ${bombRatio.toStringAsFixed(2)} "
      "(${(100 * (1.0 - bombRatio)).toStringAsFixed(0)}% below expected; "
      "≈ ${bombDisplayPts.toStringAsFixed(1)} display points at scale $scaleFactor).",
    )
    ..writeln("  expected ratio vs highest-rated in the division = exp(r_i − r_max) in internal units.")
    ..writeln(
      "DQ: MatchEntry.dq. DNF: ≥2 DNF stages with scoring.countsInRatings "
      "(chrono/ignored excluded), and not a DQ.",
    )
    ..writeln(
      "Sample: every division appearance with ≥$minMatches prior rated "
      "matches (unrated count as 0). DQ/DNF from hydrated scores, not rating events.",
    )
    ..writeln("Bombs exclude DQ and DNF appearances. Min division field: $minN.")
    ..writeln(
      "Dropped ${overall.lowHistory} appearances for min history.",
    )
    ..writeln(
      "Display buckets: 10-point floors of pre-match display rating "
      "(internal × $scaleFactor + $scaleOffset).",
    )
    ..writeln("");

  for (final group in groups) {
    _writeCounts(
      buf,
      label: group.uiLabel,
      c: byGroup[group.uiLabel]!,
    );
  }

  buf.writeln("--- Overall ---");
  _writeCounts(buf, label: null, c: overall);

  final years = byYear.keys.sorted((a, b) => a.compareTo(b));
  if (years.isNotEmpty) {
    buf.writeln("--- By Year ---");
    for (final y in years) {
      _writeCounts(buf, label: "$y", c: byYear[y]!, compact: true);
    }
    buf.writeln("");
  }

  buf.writeln("Example bombs (worst residual first, up to $kMaxListedCases):");
  if (bombCases.isEmpty) {
    buf.writeln("  (none)");
  }
  else {
    for (final c in bombCases.take(kMaxListedCases)) {
      buf.writeln(
        "  ${c.dateLabel}  ${c.groupLabel}  ${c.shooterName}  "
        "actual=${_pctRatio(c.actualRatio)}  expected=${_pctRatio(c.expectedRatio)}  "
        "resid=${c.residual.toStringAsFixed(3)}  ${c.matchName}",
      );
    }
  }
  buf.writeln("");
  buf.writeln("Example DQs (most DNF stages first, up to $kMaxListedCases):");
  if (dqCases.isEmpty) {
    buf.writeln("  (none)");
  }
  else {
    for (final c in dqCases.take(kMaxListedCases)) {
      buf.writeln(
        "  ${c.dateLabel}  ${c.groupLabel}  ${c.shooterName}  "
        "${c.dnfStages} DNF stages  actual=${_pctRatio(c.actualRatio)}  ${c.matchName}",
      );
    }
  }
  buf.writeln("");
  buf.writeln("Example DNFs (most DNF stages first, up to $kMaxListedCases):");
  if (dnfCases.isEmpty) {
    buf.writeln("  (none)");
  }
  else {
    for (final c in dnfCases.take(kMaxListedCases)) {
      buf.writeln(
        "  ${c.dateLabel}  ${c.groupLabel}  ${c.shooterName}  "
        "${c.dnfStages} DNF stages  actual=${_pctRatio(c.actualRatio)}  ${c.matchName}",
      );
    }
  }

  console.print(buf.toString());
}

void _processGroup({
  required AnalystDatabase db,
  required DbRatingProject project,
  required ShootingMatch match,
  required RatingGroup group,
  required Map<int, ShooterRating> wrapCache,
  required double bombLog,
  required int minN,
  required int minMatches,
  required double scaleFactor,
  required double scaleOffset,
  required _Counts overall,
  required _Counts groupCounts,
  required _Counts yearCounts,
  required List<_Case> bombCases,
  required List<_Case> dqCases,
  required List<_Case> dnfCases,
}) {
  final scores = match.getScoresFromFilters(group.filters);
  if (scores.isEmpty) {
    return;
  }

  final rows = <_Row>[];
  for (final kv in scores.entries) {
    final entry = kv.key;
    final rel = kv.value;
    if (!group.filters.reentries && entry.reentry) {
      continue;
    }
    final dnfStages = _dnfStageCount(rel);
    final failedToFinish = entry.dq || dnfStages >= 2;

    double? preRating;
    var priorMatches = 0;
    final dbRating = _lookupRating(db, project, group, entry);
    if (dbRating != null) {
      final wrapped = wrapCache[dbRating.id] ??
          (wrapCache[dbRating.id] = project.wrapDbRatingSync(dbRating));
      preRating = wrapped.ratingForEvent(match, null, beforeMatch: true);
      priorMatches = _priorDistinctMatchCount(wrapped, match);
    }

    rows.add(
      _Row(
        entry: entry,
        rel: rel,
        dnfStages: dnfStages,
        failedToFinish: failedToFinish,
        preRating: preRating,
        priorMatches: priorMatches,
      ),
    );
  }

  if (rows.length < minN) {
    groupCounts.shortFields++;
    overall.shortFields++;
    yearCounts.shortFields++;
    return;
  }

  groupCounts.divisionMatches++;
  overall.divisionMatches++;
  yearCounts.divisionMatches++;

  final rated = rows.where((r) => r.rated).toList();
  var maxRating = double.negativeInfinity;
  for (final r in rated) {
    if (r.preRating! > maxRating) {
      maxRating = r.preRating!;
    }
  }

  for (final row in rows) {
    if (row.priorMatches < minMatches) {
      overall.lowHistory++;
      groupCounts.lowHistory++;
      yearCounts.lowHistory++;
      continue;
    }

    overall.eligible++;
    groupCounts.eligible++;
    yearCounts.eligible++;
    if (!row.rated) {
      overall.unratedEligible++;
      groupCounts.unratedEligible++;
      yearCounts.unratedEligible++;
    }

    final bucketLo = row.rated
        ? _displayBucket(row.preRating!, scaleFactor: scaleFactor, scaleOffset: scaleOffset)
        : null;
    if (bucketLo != null) {
      _bucket(overall, bucketLo).eligible++;
      _bucket(groupCounts, bucketLo).eligible++;
      _bucket(yearCounts, bucketLo).eligible++;
    }

    if (row.failedToFinish) {
      overall.mishap++;
      groupCounts.mishap++;
      yearCounts.mishap++;
      if (bucketLo != null) {
        _bucket(overall, bucketLo).mishap++;
        _bucket(groupCounts, bucketLo).mishap++;
        _bucket(yearCounts, bucketLo).mishap++;
      }
      final example = _Case(
        matchName: match.name,
        date: match.date,
        groupLabel: group.uiLabel,
        shooterName: row.entry.getName(suffixes: false),
        actualRatio: row.ratio,
        expectedRatio: row.rated && maxRating.isFinite
            ? math.exp(row.preRating! - maxRating)
            : double.nan,
        residual: double.nan,
        dq: row.entry.dq,
        dnfStages: row.dnfStages,
      );
      if (row.entry.dq) {
        overall.dq++;
        groupCounts.dq++;
        yearCounts.dq++;
        if (bucketLo != null) {
          _bucket(overall, bucketLo).dq++;
          _bucket(groupCounts, bucketLo).dq++;
          _bucket(yearCounts, bucketLo).dq++;
        }
        dqCases.add(example);
      }
      else {
        overall.dnf++;
        groupCounts.dnf++;
        yearCounts.dnf++;
        if (bucketLo != null) {
          _bucket(overall, bucketLo).dnf++;
          _bucket(groupCounts, bucketLo).dnf++;
          _bucket(yearCounts, bucketLo).dnf++;
        }
        dnfCases.add(example);
      }
      continue;
    }

    if (!row.rated || !maxRating.isFinite || row.ratio <= 0) {
      continue;
    }

    overall.bombEligible++;
    groupCounts.bombEligible++;
    yearCounts.bombEligible++;
    if (bucketLo != null) {
      _bucket(overall, bucketLo).bombEligible++;
      _bucket(groupCounts, bucketLo).bombEligible++;
      _bucket(yearCounts, bucketLo).bombEligible++;
    }

    final expected = math.exp(row.preRating! - maxRating);
    final actualLog = math.log(row.ratio);
    final expectedLog = row.preRating! - maxRating;
    final residual = actualLog - expectedLog;
    overall.residuals.add(residual);
    groupCounts.residuals.add(residual);
    yearCounts.residuals.add(residual);

    if (residual < bombLog) {
      overall.bombs++;
      groupCounts.bombs++;
      yearCounts.bombs++;
      overall.mishap++;
      groupCounts.mishap++;
      yearCounts.mishap++;
      if (bucketLo != null) {
        _bucket(overall, bucketLo).bombs++;
        _bucket(groupCounts, bucketLo).bombs++;
        _bucket(yearCounts, bucketLo).bombs++;
        _bucket(overall, bucketLo).mishap++;
        _bucket(groupCounts, bucketLo).mishap++;
        _bucket(yearCounts, bucketLo).mishap++;
      }
      bombCases.add(
        _Case(
          matchName: match.name,
          date: match.date,
          groupLabel: group.uiLabel,
          shooterName: row.entry.getName(suffixes: false),
          actualRatio: row.ratio,
          expectedRatio: expected,
          residual: residual,
          dq: row.entry.dq,
          dnfStages: row.dnfStages,
        ),
      );
    }
  }
}

_BucketCounts _bucket(_Counts c, int lo) {
  return c.byDisplayBucket.putIfAbsent(lo, () => _BucketCounts());
}

int _displayBucket(
  double internalRating, {
  required double scaleFactor,
  required double scaleOffset,
}) {
  final display = internalRating * scaleFactor + scaleOffset;
  return (display / kDisplayBucketWidth).floor() * kDisplayBucketWidth;
}

int _dnfStageCount(RelativeMatchScore rel) {
  var n = 0;
  for (final se in rel.stageScores.entries) {
    if (!se.key.scoring.countsInRatings) {
      continue;
    }
    if (se.value.score.dnf) {
      n++;
    }
  }
  return n;
}

int _priorDistinctMatchCount(ShooterRating wrapped, ShootingMatch match) {
  final currentIds = match.sourceIds.toSet();
  final seen = <String>{};
  for (final e in wrapped.ratingEvents) {
    final id = e.wrappedEvent.matchId;
    if (currentIds.contains(id)) {
      continue;
    }
    if (e.date.isAfter(match.date)) {
      continue;
    }
    seen.add(id);
  }
  return seen.length;
}

void _writeCounts(StringBuffer buf, {required String? label, required _Counts c, bool compact = false}) {
  if (label != null) {
    buf.writeln("--- $label ---");
  }
  if (compact) {
    buf.writeln(
      "  matches=${c.divisionMatches}  eligible=${c.eligible}  "
      "DQ=${_pct(c.dq, c.eligible)}  "
      "DNF=${_pct(c.dnf, c.eligible)}  "
      "bomb=${_pct(c.bombs, c.bombEligible)}  "
      "mishap=${_pct(c.mishap, c.eligible)}",
    );
    return;
  }

  buf.writeln(
    "  Division-matches: ${c.divisionMatches}  (skipped ${c.shortFields} short fields)",
  );
  buf.writeln("  Eligible appearances: ${c.eligible}");
  if (c.lowHistory > 0) {
    buf.writeln("    dropped for min history: ${c.lowHistory}");
  }
  if (c.unratedEligible > 0) {
    buf.writeln("    unrated: ${c.unratedEligible}");
  }
  buf.writeln(
    "  DQ: ${_pct(c.dq, c.eligible)}",
  );
  buf.writeln(
    "  DNF (≥2 stages, not DQ): ${_pct(c.dnf, c.eligible)}",
  );
  buf.writeln(
    "  Bombs (eligible finishers with rating): ${_pct(c.bombs, c.bombEligible)}",
  );
  buf.writeln(
    "  Mishap (bomb or DQ or DNF): ${_pct(c.mishap, c.eligible)}",
  );
  if (c.residuals.length >= 2) {
    final sorted = [...c.residuals]..sort();
    buf.writeln(
      "  Residual ln(actual)−(r_i−r_max) among bomb-eligible finishers: "
      "p10=${_fmt(_percentile(sorted, 0.10))}  "
      "median=${_fmt(_percentile(sorted, 0.50))}  "
      "p90=${_fmt(_percentile(sorted, 0.90))}  "
      "n=${c.residuals.length}",
    );
  }
  _writeDisplayBuckets(buf, c);
  buf.writeln("");
}

void _writeDisplayBuckets(StringBuffer buf, _Counts c) {
  if (c.byDisplayBucket.isEmpty) {
    return;
  }
  buf.writeln("  By display rating (${kDisplayBucketWidth}-pt buckets):");
  final keys = c.byDisplayBucket.keys.sorted((a, b) => a.compareTo(b));
  for (final lo in keys) {
    final b = c.byDisplayBucket[lo]!;
    final hi = lo + kDisplayBucketWidth - 1;
    final label = "$lo-$hi".padLeft(8);
    buf.writeln(
      "   $label  elig=${b.eligible.toString().padLeft(4)}  "
      "DQ=${_pct(b.dq, b.eligible)}  "
      "DNF=${_pct(b.dnf, b.eligible)}  "
      "bomb=${_pct(b.bombs, b.bombEligible)}  "
      "mishap=${_pct(b.mishap, b.eligible)}",
    );
  }
}

double _percentile(List<double> sortedAsc, double p) {
  if (sortedAsc.isEmpty) {
    return double.nan;
  }
  if (sortedAsc.length == 1) {
    return sortedAsc.first;
  }
  final pos = p * (sortedAsc.length - 1);
  final lo = pos.floor();
  final hi = pos.ceil();
  if (lo == hi) {
    return sortedAsc[lo];
  }
  final w = pos - lo;
  return sortedAsc[lo] * (1.0 - w) + sortedAsc[hi] * w;
}

String _pct(int num, int den) {
  if (den == 0) {
    return "n/a ($num/0)";
  }
  return "${(100.0 * num / den).toStringAsFixed(1)}% ($num/$den)";
}

String _pctRatio(double ratio) {
  if (ratio.isNaN) {
    return "n/a";
  }
  return "${(100.0 * ratio).toStringAsFixed(1)}%";
}

String _fmt(double v) {
  if (v.isNaN) {
    return "n/a";
  }
  return v.toStringAsFixed(3);
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
      useCache: true,
    );
    if (dbRating != null) {
      return dbRating;
    }
  }
  return null;
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
