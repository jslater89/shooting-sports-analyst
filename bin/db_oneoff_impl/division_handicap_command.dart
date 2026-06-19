/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Division handicap analysis for USPSA LLR.
///
/// For each match in the rating project from [startYear] to present, collects
/// per-competitor (field-percentile-bucket, match-ratio) and per-stage
/// (field-percentile-bucket, stage-ratio) observations for every per-division
/// rating group found in the project.
///
/// "Field percentile" is the competitor's pre-match rating rank among all
/// *rated* competitors in their division at that specific match (1.0 = top
/// rated entrant, 0.0 = lowest). Only rated, non-DQ, non-reentry competitors
/// are included.
///
/// Scale factor A→B is the ratio of expected performance in B relative to A
/// for a competitor at the same field-percentile position. A value < 1.0 means
/// division B has a comparatively deeper/harder field than division A.
///
/// CIs are bootstrapped by resampling matches (i.e., match-level clustering is
/// respected). The reported 95% CI is the normal approximation mean ± 1.96·SE
/// where SE is the SD of the bootstrap scale-factor distribution.
///
/// Also collects direct cross-division observations: when the same competitor
/// (by member number) appears in two division groups within [crossWindowDays]
/// of each other across the loaded match set, those paired ratios are recorded
/// and analysed separately.
///
/// Run: dart run bin/db_oneoffs.dart DH

import "dart:math";

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";

import "base.dart";

const String kDefaultDhProjectName = "L2s Main LLR";
const int kDefaultDhStartYear = 2020;
const int kDefaultCrossWindowDays = 60;

/// Number of quintile buckets (0 = bottom, 4 = top).
const int kNumBuckets = 5;

/// Minimum observations per bucket for a scale factor cell to be reported.
const int kMinBucketObs = 8;

/// Bootstrap resampling repetitions for CI estimation.
const int kBootstrapReps = 1000;

/// USPSA divisions to analyse, in display order.
/// The code will skip any for which the project has no group.
const List<({Division division, String short})> kDhTargetDivisions = [
  (division: uspsaOpen, short: "Open"),
  (division: uspsaCarryOptics, short: "CO"),
  (division: uspsaLimitedOptics, short: "LO"),
  (division: uspsaLimited, short: "LIM"),
  (division: uspsaProduction, short: "PROD"),
  (division: uspsaSingleStack, short: "SS"),
  (division: uspsaRevolver, short: "REV"),
];

// ---------------------------------------------------------------------------
// Command
// ---------------------------------------------------------------------------

class DivisionHandicapCommand extends DbOneoffCommand {
  DivisionHandicapCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "DH";

  @override
  final String title = "Division Handicap Analysis";

  @override
  String? get description =>
      "Estimates cross-division scale factors from L2s Main LLR matches (from a start year), "
      "using field-percentile-matched ratios (match- and stage-level) and direct cross-division "
      "shooter comparisons. CIs are bootstrapped by match.";

  @override
  List<MenuArgument> get arguments => [
        StringMenuArgument(
          label: "Project",
          required: false,
          defaultValue: kDefaultDhProjectName,
          description: "Rating project name.",
        ),
        IntMenuArgument(
          label: "Start year",
          required: false,
          defaultValue: kDefaultDhStartYear,
          description: "First calendar year to include (ratings stabilise before this).",
        ),
        IntMenuArgument(
          label: "Cross-div window (days)",
          required: false,
          defaultValue: kDefaultCrossWindowDays,
          description: "Max gap between matches for direct cross-division pairing.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final projectName = arguments
            .firstWhereOrNull((a) => a.argument.label == "Project")
            ?.getAs<String>()
            .trim() ??
        kDefaultDhProjectName;
    final startYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "Start year")
            ?.getAs<int>() ??
        kDefaultDhStartYear;
    final crossWindowDays = arguments
            .firstWhereOrNull((a) => a.argument.label == "Cross-div window (days)")
            ?.getAs<int>() ??
        kDefaultCrossWindowDays;

    await _run(
      db,
      console,
      projectName: projectName,
      startYear: startYear,
      crossWindowDays: crossWindowDays,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal data structures
// ---------------------------------------------------------------------------

/// One competitor at one match in one division.
final class _MatchObs {
  _MatchObs({
    required this.matchId,
    required this.divShort,
    required this.bucket,
    required this.logRatio,
  });

  final String matchId;
  final String divShort;

  /// Quintile bucket (0 = bottom 20 % of field, 4 = top 20 %).
  final int bucket;

  /// log(matchRatio): log of this competitor's score / winner's score.
  final double logRatio;
}

/// One competitor × one stage at one match in one division.
final class _StageObs {
  _StageObs({
    required this.matchId,
    required this.divShort,
    required this.bucket,
    required this.logStageRatio,
  });

  final String matchId;
  final String divShort;
  final int bucket;
  final double logStageRatio;
}

/// One appearance by a member in one division at one match (for direct pairing).
final class _PersonRecord {
  _PersonRecord({
    required this.divShort,
    required this.bucket,
    required this.matchRatio,
    required this.matchDate,
  });

  final String divShort;
  final int bucket;
  final double matchRatio;
  final DateTime matchDate;
}

/// Result cell for one division pair in the scale matrix.
typedef _ScaleCell = ({double scale, double ciLo, double ciHi, int nFrom, int nTo});

/// A direct cross-division ratio pair from the same competitor.
final class _DirectObs {
  _DirectObs({
    required this.divAShort,
    required this.divBShort,
    required this.logRatioAtoB,
  });

  /// log(ratioB / ratioA): positive means B performance was relatively better.
  final String divAShort;
  final String divBShort;
  final double logRatioAtoB;
}

// ---------------------------------------------------------------------------
// Main orchestration
// ---------------------------------------------------------------------------

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required int startYear,
  required int crossWindowDays,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }

  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  // Find per-division groups for each target division.
  final divGroups = <String, RatingGroup>{};
  for (final target in kDhTargetDivisions) {
    final group = project.groupForDivisionSync(target.division);
    if (group != null) {
      divGroups[target.short] = group;
    }
    else {
      console.print("  Note: no group found for ${target.short}, skipping.");
    }
  }

  if (divGroups.length < 2) {
    console.print("Need at least 2 division groups; found ${divGroups.length}. Aborting.");
    return;
  }

  final divNames = divGroups.keys.toList();

  // Filter match pointers to the requested start year and later.
  final startDate = DateTime(startYear, 1, 1);
  final pointers = project.matchPointers
      .where((p) => p.date != null && !p.date!.isBefore(startDate))
      .toList()
    ..sort((a, b) => a.date!.compareTo(b.date!));

  console.print(
    "Project: $projectName | Divisions: ${divNames.join(", ")} "
    "| Matches from $startYear: ${pointers.length}",
  );

  // Accumulators.
  final matchObs = <_MatchObs>[];
  final stageObs = <_StageObs>[];

  // For direct comparison: member# → list of records (across all matches and divs).
  final personRecords = <String, List<_PersonRecord>>{};

  int hydrateErrors = 0;
  int matchesProcessed = 0;

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    canHaveErrors: true,
    initialLabel: "Processing matches…",
  );

  for (final ptr in pointers) {
    bar.tick(ptr.name);

    final loadRes = await ptr.getDbMatch(db, downloadIfMissing: false);
    if (loadRes.isErr()) {
      bar.error("Load failed: ${ptr.name}");
      hydrateErrors++;
      continue;
    }
    final dbMatch = loadRes.unwrap();
    if (dbMatch.shootersStoredSeparately) {
      await dbMatch.shooterLinks.load();
    }

    final hydrateRes = await dbMatch.hydrate();
    if (hydrateRes.isErr()) {
      bar.error("Hydrate failed: ${dbMatch.eventName}");
      hydrateErrors++;
      continue;
    }
    final match = hydrateRes.unwrap();
    matchesProcessed++;

    final matchId = "${match.name}__${match.date.toIso8601String().split("T").first}";

    for (final entry in divGroups.entries) {
      final divShort = entry.key;
      final group = entry.value;

      _processMatchForDivision(
        db: db,
        project: project,
        match: match,
        matchId: matchId,
        divShort: divShort,
        group: group,
        matchObs: matchObs,
        stageObs: stageObs,
        personRecords: personRecords,
      );
    }
  }

  bar.complete();

  console.print(
    "Processed $matchesProcessed matches ($hydrateErrors errors). "
    "Match-level obs: ${matchObs.length}, stage-level obs: ${stageObs.length}.",
  );

  // Build direct observations from temporally close cross-division appearances.
  final directObs = _buildDirectObs(personRecords, crossWindowDays: crossWindowDays);
  console.print("Direct cross-division pairs (≤ $crossWindowDays days): ${directObs.length}");

  // Compute and print results.
  final buf = StringBuffer();
  buf.writeln("\n══════════════════════════════════════════════════════════════");
  buf.writeln("Division Handicap Analysis — $projectName");
  buf.writeln("Matches from $startYear | n processed: $matchesProcessed");
  buf.writeln(
    "Field-percentile method: quintile buckets of pre-match rating rank in match field.",
  );
  buf.writeln(
    "Scale A→B < 1.0: division B has a harder/deeper field at the same percentile.",
  );
  buf.writeln("CIs: bootstrapped by match (${kBootstrapReps} reps), 95 % normal approx.");
  buf.writeln("══════════════════════════════════════════════════════════════\n");

  _writeScaleMatrix(
    buf,
    label: "MATCH-LEVEL SCALE FACTORS",
    obs: matchObs,
    divNames: divNames,
    rng: Random(42),
  );

  buf.writeln("");

  _writeScaleMatrix(
    buf,
    label: "STAGE-LEVEL SCALE FACTORS",
    obs: stageObs.map((s) => _MatchObs(
          matchId: s.matchId,
          divShort: s.divShort,
          bucket: s.bucket,
          logRatio: s.logStageRatio,
        )).toList(),
    divNames: divNames,
    rng: Random(42),
  );

  buf.writeln("");
  _writeDirectPairs(buf, directObs: directObs, divNames: divNames);

  console.print(buf.toString());
}

// ---------------------------------------------------------------------------
// Per-match, per-division observation extraction
// ---------------------------------------------------------------------------

void _processMatchForDivision({
  required AnalystDatabase db,
  required DbRatingProject project,
  required ShootingMatch match,
  required String matchId,
  required String divShort,
  required RatingGroup group,
  required List<_MatchObs> matchObs,
  required List<_StageObs> stageObs,
  required Map<String, List<_PersonRecord>> personRecords,
}) {
  final scores = match.getScoresFromFilters(group.filters);
  if (scores.isEmpty) {
    return;
  }

  // Gather rated competitor (preMatchRating, matchRatio) pairs.
  final fieldData = <({String memberNum, double preRating, double matchRatio, MatchEntry entry, Map<MatchStage, double> stageRatios})>[];

  for (final kv in scores.entries) {
    final matchEntry = kv.key;
    final relScore = kv.value;

    if (matchEntry.dq) {
      continue;
    }
    if (!group.filters.reentries && matchEntry.reentry) {
      continue;
    }
    if (relScore.ratio <= 0.0) {
      continue;
    }

    final dbRating = _lookupRating(db, project, group, matchEntry);
    if (dbRating == null) {
      continue;
    }

    final wrapped = project.wrapDbRatingSync(dbRating);
    final preRating = wrapped.ratingForEvent(match, null, beforeMatch: true);

    // Collect per-stage ratios (skip DNF stages).
    final stageRatios = <MatchStage, double>{};
    for (final se in relScore.stageScores.entries) {
      if (!se.value.score.dnf && se.value.ratio > 0.0) {
        stageRatios[se.key] = se.value.ratio;
      }
    }

    final mn = matchEntry.memberNumber.trim();
    if (mn.isNotEmpty && mn != "(invalid)") {
      fieldData.add((
        memberNum: mn,
        preRating: preRating,
        matchRatio: relScore.ratio,
        entry: matchEntry,
        stageRatios: stageRatios,
      ));
    }
  }

  if (fieldData.length < kNumBuckets) {
    return;
  }

  // Sort by pre-match rating ascending to assign quintile buckets.
  final sorted = [...fieldData]..sort((a, b) => a.preRating.compareTo(b.preRating));
  final n = sorted.length;

  for (var i = 0; i < sorted.length; i++) {
    final rec = sorted[i];
    final bucket = _quintile(i, n);
    final logRatio = log(rec.matchRatio);

    matchObs.add(_MatchObs(
      matchId: matchId,
      divShort: divShort,
      bucket: bucket,
      logRatio: logRatio,
    ));

    for (final sr in rec.stageRatios.entries) {
      stageObs.add(_StageObs(
        matchId: matchId,
        divShort: divShort,
        bucket: bucket,
        logStageRatio: log(sr.value),
      ));
    }

    personRecords.putIfAbsent(rec.memberNum, () => []).add(_PersonRecord(
      divShort: divShort,
      bucket: bucket,
      matchRatio: rec.matchRatio,
      matchDate: match.date,
    ));
  }
}

/// Assigns a quintile bucket (0–4) to rank [i] out of [n] items.
int _quintile(int i, int n) {
  if (n <= 1) {
    return 2;
  }
  return (i * kNumBuckets ~/ n).clamp(0, kNumBuckets - 1);
}

// ---------------------------------------------------------------------------
// Direct cross-division pair builder
// ---------------------------------------------------------------------------

List<_DirectObs> _buildDirectObs(
  Map<String, List<_PersonRecord>> personRecords, {
  required int crossWindowDays,
}) {
  final out = <_DirectObs>[];

  for (final records in personRecords.values) {
    if (records.length < 2) {
      continue;
    }

    // Look for any pair in different divisions within the time window.
    for (var i = 0; i < records.length; i++) {
      for (var j = i + 1; j < records.length; j++) {
        final a = records[i];
        final b = records[j];
        if (a.divShort == b.divShort) {
          continue;
        }
        final delta = a.matchDate.difference(b.matchDate).abs().inDays;
        if (delta > crossWindowDays) {
          continue;
        }
        if (a.matchRatio <= 0.0 || b.matchRatio <= 0.0) {
          continue;
        }

        // Record A→B and B→A (symmetric; analysis uses ordered pairs later).
        out.add(_DirectObs(
          divAShort: a.divShort,
          divBShort: b.divShort,
          logRatioAtoB: log(b.matchRatio) - log(a.matchRatio),
        ));
        out.add(_DirectObs(
          divAShort: b.divShort,
          divBShort: a.divShort,
          logRatioAtoB: log(a.matchRatio) - log(b.matchRatio),
        ));
      }
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// Scale factor computation (percentile-bucket method)
// ---------------------------------------------------------------------------

/// Computes the scale factor and bootstrap 95% CI for pair (fromDiv → toDiv).
///
/// Returns null if there is insufficient data (fewer than [kMinBucketObs]
/// per bucket in either division).
_ScaleCell? _computeScaleFactor(
  List<_MatchObs> allObs, {
  required String fromDiv,
  required String toDiv,
  required Random rng,
}) {
  final obsFrom = allObs.where((o) => o.divShort == fromDiv).toList();
  final obsTo = allObs.where((o) => o.divShort == toDiv).toList();

  if (obsFrom.isEmpty || obsTo.isEmpty) {
    return null;
  }

  final matchIdsFrom = obsFrom.map((o) => o.matchId).toSet().toList();
  final matchIdsTo = obsTo.map((o) => o.matchId).toSet().toList();

  // Compute point estimate.
  final pointEst = _scaleBetween(obsFrom, obsTo);
  if (pointEst == null) {
    return null;
  }

  // Bootstrap.
  final bootScales = <double>[];
  for (var rep = 0; rep < kBootstrapReps; rep++) {
    final sampledFrom = _resample(matchIdsFrom, rng);
    final sampledTo = _resample(matchIdsTo, rng);

    final obsFromBoot = _obsForMatches(obsFrom, sampledFrom);
    final obsToBoot = _obsForMatches(obsTo, sampledTo);

    final s = _scaleBetween(obsFromBoot, obsToBoot);
    if (s != null) {
      bootScales.add(s);
    }
  }

  if (bootScales.length < kBootstrapReps ~/ 2) {
    return null;
  }

  final bootMean = _mean(bootScales);
  final bootSe = _sd(bootScales, mean: bootMean);

  return (
    scale: exp(pointEst),
    ciLo: exp(pointEst - 1.96 * bootSe),
    ciHi: exp(pointEst + 1.96 * bootSe),
    nFrom: matchIdsFrom.length,
    nTo: matchIdsTo.length,
  );
}

/// Mean log-scale from [fromObs] to [toObs] averaged over quintile buckets.
///
/// Returns null if any bucket has < [kMinBucketObs] observations in *either* division.
double? _scaleBetween(List<_MatchObs> fromObs, List<_MatchObs> toObs) {
  double totalLogDiff = 0.0;
  int validBuckets = 0;

  for (var b = 0; b < kNumBuckets; b++) {
    final fBucket = fromObs.where((o) => o.bucket == b).map((o) => o.logRatio).toList();
    final tBucket = toObs.where((o) => o.bucket == b).map((o) => o.logRatio).toList();

    if (fBucket.length < kMinBucketObs || tBucket.length < kMinBucketObs) {
      continue;
    }

    totalLogDiff += _mean(tBucket) - _mean(fBucket);
    validBuckets++;
  }

  if (validBuckets == 0) {
    return null;
  }

  return totalLogDiff / validBuckets;
}

List<_MatchObs> _obsForMatches(List<_MatchObs> obs, List<String> matchIds) {
  final idSet = matchIds.toSet();
  return obs.where((o) => idSet.contains(o.matchId)).toList();
}

List<String> _resample(List<String> ids, Random rng) {
  return [for (var i = 0; i < ids.length; i++) ids[rng.nextInt(ids.length)]];
}

// ---------------------------------------------------------------------------
// Direct-pair CI computation
// ---------------------------------------------------------------------------

({double scale, double ciLo, double ciHi, int n})? _computeDirectScale(
  List<_DirectObs> allDirect, {
  required String fromDiv,
  required String toDiv,
}) {
  final logRatios = allDirect
      .where((o) => o.divAShort == fromDiv && o.divBShort == toDiv)
      .map((o) => o.logRatioAtoB)
      .toList();

  if (logRatios.length < 3) {
    return null;
  }

  final n = logRatios.length;
  final mu = _mean(logRatios);
  final se = _sd(logRatios, mean: mu) / sqrt(n.toDouble());

  // t-critical for 95 % CI (use 1.96 as a conservative approximation for df ≥ 20;
  // for small n it's slightly anti-conservative but acceptable for a research tool).
  final tCrit = n >= 30 ? 1.96 : _tCrit95(n - 1);

  return (
    scale: exp(mu),
    ciLo: exp(mu - tCrit * se),
    ciHi: exp(mu + tCrit * se),
    n: n,
  );
}

// ---------------------------------------------------------------------------
// Output formatting
// ---------------------------------------------------------------------------

void _writeScaleMatrix(
  StringBuffer buf, {
  required String label,
  required List<_MatchObs> obs,
  required List<String> divNames,
  required Random rng,
}) {
  buf.writeln("── $label ──────────────────────────────────────");
  buf.writeln(
    "  Rows = from-division, columns = to-division. "
    "Read: 'moving from row to column, expected ratio scales by this factor.'",
  );
  buf.writeln(
    "  n-obs per division: ${divNames.map((d) => "$d=${obs.where((o) => o.divShort == d).length}").join(", ")}",
  );
  buf.writeln("");

  // Precompute all cells.
  final cells = <String, Map<String, _ScaleCell?>>{};


  for (final from in divNames) {
    cells[from] = {};
    for (final to in divNames) {
      if (from == to) {
        cells[from]![to] = null;
        continue;
      }
      cells[from]![to] = _computeScaleFactor(obs, fromDiv: from, toDiv: to, rng: rng);
    }
  }

  // Header row.
  final colWidth = 22;
  final labelWidth = 6;
  buf.write("".padLeft(labelWidth));
  for (final to in divNames) {
    buf.write("→ ${to.padRight(colWidth - 2)}");
  }
  buf.writeln("");

  // Data rows.
  for (final from in divNames) {
    buf.write(from.padRight(labelWidth));
    for (final to in divNames) {
      if (from == to) {
        buf.write("  ---                 ");
        continue;
      }
      final cell = cells[from]![to];
      if (cell == null) {
        buf.write("  n/a                 ");
      }
      else {
        final s = cell.scale.toStringAsFixed(4);
        final lo = cell.ciLo.toStringAsFixed(4);
        final hi = cell.ciHi.toStringAsFixed(4);
        final text = "$s [$lo, $hi]";
        buf.write("  ${text.padRight(colWidth)}");
      }
    }
    buf.writeln("");
  }

  buf.writeln("");

  // Per-cell match counts.
  buf.writeln("  n-matches (from / to) per cell:");
  buf.write("".padLeft(labelWidth));
  for (final to in divNames) {
    buf.write("→ ${to.padRight(colWidth - 2)}");
  }
  buf.writeln("");
  for (final from in divNames) {
    buf.write(from.padRight(labelWidth));
    for (final to in divNames) {
      if (from == to) {
        buf.write("  ---                 ");
        continue;
      }
      final cell = cells[from]![to];
      if (cell == null) {
        buf.write("  n/a                 ");
      }
      else {
        final text = "${cell.nFrom} / ${cell.nTo}";
        buf.write("  ${text.padRight(colWidth)}");
      }
    }
    buf.writeln("");
  }
}

void _writeDirectPairs(
  StringBuffer buf, {
  required List<_DirectObs> directObs,
  required List<String> divNames,
}) {
  buf.writeln("── DIRECT CROSS-DIVISION COMPARISONS (same competitor, paired appearances) ──");
  buf.writeln("  Scale and 95% CI from log(ratioB / ratioA) per paired appearance.");
  buf.writeln("  t-distribution CI (df = n−1).");
  buf.writeln("");

  // Header.
  buf.writeln("  ${"Pair".padRight(12)}  ${"n".padLeft(5)}  ${"Scale".padRight(8)}  ${"95% CI".padRight(18)}");
  buf.writeln("  ${"────".padRight(12)}  ${"─".padLeft(5)}  ${"─────".padRight(8)}  ${"──────".padRight(18)}");

  for (final from in divNames) {
    for (final to in divNames) {
      if (from == to) {
        continue;
      }
      final res = _computeDirectScale(directObs, fromDiv: from, toDiv: to);
      if (res == null) {
        continue;
      }
      final pair = "$from→$to".padRight(12);
      final n = res.n.toString().padLeft(5);
      final s = res.scale.toStringAsFixed(4).padRight(8);
      final ci = "[${res.ciLo.toStringAsFixed(4)}, ${res.ciHi.toStringAsFixed(4)}]".padRight(18);
      buf.writeln("  $pair  $n  $s  $ci");
    }
  }
}

// ---------------------------------------------------------------------------
// Rating lookup helpers
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Statistics helpers
// ---------------------------------------------------------------------------

double _mean(List<double> xs) {
  if (xs.isEmpty) {
    return 0.0;
  }
  return xs.reduce((a, b) => a + b) / xs.length;
}

double _sd(List<double> xs, {required double mean}) {
  if (xs.length < 2) {
    return 0.0;
  }
  final variance = xs.map((x) => pow(x - mean, 2).toDouble()).reduce((a, b) => a + b) / (xs.length - 1);
  return sqrt(variance);
}

/// Approximate t-critical value for 95 % two-sided CI at df degrees of freedom.
/// Uses a small lookup table; falls back to 1.96 for df ≥ 30.
double _tCrit95(int df) {
  const table = <int, double>{
    1: 12.706,
    2: 4.303,
    3: 3.182,
    4: 2.776,
    5: 2.571,
    6: 2.447,
    7: 2.365,
    8: 2.306,
    9: 2.262,
    10: 2.228,
    15: 2.131,
    20: 2.086,
    25: 2.060,
  };
  if (df >= 30) {
    return 1.96;
  }
  final exact = table[df];
  if (exact != null) {
    return exact;
  }
  // Linear interpolation between nearest entries.
  final lower = table.keys.where((k) => k < df).maxOrNull;
  final upper = table.keys.where((k) => k > df).minOrNull;
  if (lower == null) {
    return table[1]!;
  }
  if (upper == null) {
    return 1.96;
  }
  final t = (df - lower) / (upper - lower);
  return table[lower]! + t * (table[upper]! - table[lower]!);
}
