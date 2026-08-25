/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Golf-style match slope from pre-match LLR ratings vs observed log finish ratios.
///
/// Primary estimator: Huber IRLS of L = ln(ratio) on pre-match rating R, using the
/// full rated field. Winner's curse is the intercept; slope > 1 means the match
/// stretched the field (weaker shooters finished further behind than ratings
/// predict). Theil-Sen is reported as a second robust check.
///
/// Scratch vs 40–60th percentile (by pre-match rating) is a diagnostic only —
/// not the primary slope.
///
/// Menu / CLI: SLP <startYear> <endYear> [project] [matchSearch] [minN]
/// Example: SLP 2024 2026

import "dart:math" as math;

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";

import "base.dart";

const String kDefaultLlrProjectName = "L2s Main LLR";
const int kDefaultMinN = 20;
const double kHuberK = 1.345;
const double kRefRatingGap = 0.50;
const double kScratchTopFrac = 0.10;
const double kMidLo = 0.40;
const double kMidHi = 0.60;
const int kQuintiles = 5;

class MatchSlopeCommand extends DbOneoffCommand {
  MatchSlopeCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "SLP";

  @override
  final String title = "Match Slope (LLR Huber)";

  @override
  String? get description =>
      "Huber slope of log finish ratio vs pre-match LLR rating. "
      "Slope > 1 means the match stretched the field.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Start year",
          required: true,
          description: "Inclusive start of the match-date year range.",
        ),
        IntMenuArgument(
          label: "End year",
          required: true,
          description: "Inclusive end of the match-date year range.",
        ),
        StringMenuArgument(
          label: "Project name",
          required: false,
          defaultValue: kDefaultLlrProjectName,
          description: "Rating project (LLR recommended).",
        ),
        StringMenuArgument(
          label: "Match search",
          required: false,
          defaultValue: "",
          description:
              "Case-insensitive substring of match name. Empty = all matches "
              "in the year range.",
        ),
        IntMenuArgument(
          label: "Min N",
          required: false,
          defaultValue: kDefaultMinN,
          description: "Minimum rated competitors in a group to fit a slope.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final startYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "Start year")
            ?.getAs<int>();
    final endYear = arguments
            .firstWhereOrNull((a) => a.argument.label == "End year")
            ?.getAs<int>();
    final projectName = arguments
            .firstWhereOrNull((a) => a.argument.label == "Project name")
            ?.getAs<String>()
            .trim() ??
        kDefaultLlrProjectName;
    final search = arguments
            .firstWhereOrNull((a) => a.argument.label == "Match search")
            ?.getAs<String>()
            .trim() ??
        "";
    final minN = arguments
            .firstWhereOrNull((a) => a.argument.label == "Min N")
            ?.getAs<int>() ??
        kDefaultMinN;

    if (startYear == null || endYear == null) {
      console.print("Start year and end year are required (e.g. SLP 2024 2026).");
      return;
    }
    if (startYear > endYear) {
      console.print("Start year ($startYear) must be <= end year ($endYear).");
      return;
    }
    if (minN < 8) {
      console.print("Min N must be at least 8 (got $minN).");
      return;
    }

    await _run(
      db,
      console,
      projectName: projectName.isEmpty ? kDefaultLlrProjectName : projectName,
      search: search,
      startYear: startYear,
      endYear: endYear,
      minN: minN,
    );
  }
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required String search,
  required int startYear,
  required int endYear,
  required int minN,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }

  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final isLlr = project.settings.algorithm is LatentLogRater;
  final ratingGroups = [...project.groups]..sort((a, b) {
      final o = a.sortOrder.compareTo(b.sortOrder);
      if (o != 0) {
        return o;
      }
      return a.name.compareTo(b.name);
    });

  final searchLower = search.toLowerCase();
  final pointers = project.matchPointers.where((p) {
    if (p.date == null) {
      return false;
    }
    final y = p.date!.year;
    if (y < startYear || y > endYear) {
      return false;
    }
    if (searchLower.isEmpty) {
      return true;
    }
    return p.name.toLowerCase().contains(searchLower);
  }).toList()
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  if (pointers.isEmpty) {
    console.print(
      "No match pointers in $projectName for $startYear–$endYear"
      "${search.isNotEmpty ? " matching \"$search\"" : ""}.",
    );
    return;
  }

  final buf = StringBuffer()
    ..writeln("Project: $projectName")
    ..writeln("Algorithm: ${project.settings.algorithm.runtimeType}")
    ..writeln(
      "Estimator: Huber IRLS (k=$kHuberK) of L=ln(ratio) on pre-match rating R",
    )
    ..writeln(
      "Identity: maybeKnownShooterSync(usePossibleMemberNumbers: true)",
    )
    ..writeln("Pre-match rating: ratingForEvent(beforeMatch: true)")
    ..writeln("Min N: $minN")
    ..writeln(
      "Match filter: $startYear–$endYear"
      "${search.isEmpty ? ", all names" : ", \"$search\""}",
    )
    ..writeln("Pointers: ${pointers.length}");
  if (!isLlr) {
    buf.writeln(
      "Warning: slope=1 is the LLR calibration. This project's algorithm "
      "is not LatentLogRater; interpret slope levels with care.",
    );
  }
  buf.writeln("");

  final bar = LabeledProgressBar(
    maxValue: pointers.length,
    initialLabel: "Match slope...",
    canHaveErrors: true,
  );

  final results = <_GroupFit>[];
  var hydrateErrors = 0;

  for (final ptr in pointers) {
    bar.tick(ptr.name);

    final res = await ptr.getDbMatch(db, downloadIfMissing: false);
    if (res.isErr()) {
      hydrateErrors++;
      bar.error("Load failed: ${ptr.name}");
      continue;
    }
    final dbMatch = res.unwrap();
    if (dbMatch.shootersStoredSeparately) {
      await dbMatch.shooterLinks.load();
    }

    final hydrated = await dbMatch.hydrate();
    if (hydrated.isErr()) {
      hydrateErrors++;
      bar.error("Hydrate failed: ${ptr.name}");
      continue;
    }
    final match = hydrated.unwrap();
    final dateStr = match.date.toIso8601String().split("T").first;

    for (final group in ratingGroups) {
      final fit = _fitGroup(
        db: db,
        project: project,
        match: match,
        group: group,
        minN: minN,
      );
      if (fit == null) {
        continue;
      }
      fit.matchName = match.name;
      fit.matchDate = dateStr;
      results.add(fit);
    }
  }

  bar.complete();

  if (hydrateErrors > 0) {
    buf.writeln("Hydrate/load errors: $hydrateErrors");
    buf.writeln("");
  }

  if (results.isEmpty) {
    buf.writeln("No group/match cells with at least $minN rated competitors.");
    console.print(buf.toString());
    return;
  }

  buf.writeln("=== Per match × group ===");
  buf.writeln("");
  for (final fit in results) {
    _writeDetail(buf, fit);
  }

  buf.writeln("=== Ranked summary (Huber slope) ===");
  buf.writeln(
    "slope>1 = stretched (harder for weaker shooters); slope<1 = compressed.",
  );
  buf.writeln("");

  final byGroup = <String, List<_GroupFit>>{};
  for (final fit in results) {
    byGroup.putIfAbsent(fit.groupLabel, () => []).add(fit);
  }

  for (final groupLabel in byGroup.keys.sorted()) {
    final fits = [...byGroup[groupLabel]!]
      ..sort((a, b) => b.huber.slope.compareTo(a.huber.slope));
    final slopes = fits.map((f) => f.huber.slope).toList();
    buf.writeln(
      "$groupLabel  n_matches=${fits.length}  "
      "Huber median=${_fmt( _median(slopes))}  "
      "p10=${_fmt(_percentile(slopes, 0.10))}  "
      "p90=${_fmt(_percentile(slopes, 0.90))}",
    );
    buf.writeln(
      "  ${_pad("date", 12)} ${_pad("n", 5)} ${_pad("Huber", 7)} "
      "${_pad("Theil", 7)} ${_pad("OLS", 7)} ${_pad("wt<1", 6)} "
      "${_pad("mid/scr", 8)} match",
    );
    for (final fit in fits) {
      final pct = _percentileRank(slopes, fit.huber.slope);
      buf.writeln(
        "  ${_pad(fit.matchDate, 12)} ${_pad("${fit.n}", 5)} "
        "${_pad(_fmt(fit.huber.slope), 7)} "
        "${_pad(_fmt(fit.theilSen.slope), 7)} "
        "${_pad(_fmt(fit.ols.slope), 7)} "
        "${_pad("${(fit.fracDownweighted * 100).toStringAsFixed(0)}%", 6)} "
        "${_pad(fit.midScratchRatio == null ? "—" : _fmt(fit.midScratchRatio!), 8)} "
        "${fit.matchName}  (p${pct.toStringAsFixed(0)} of this group)",
      );
    }
    buf.writeln("");
  }

  console.print(buf.toString());
}

void _writeDetail(StringBuffer buf, _GroupFit fit) {
  buf.writeln("${fit.matchDate}  ${fit.matchName}  —  ${fit.groupLabel}");
  buf.writeln(
    "  n=${fit.n} rated of ${fit.rosterN} roster "
    "(${fit.unmapped} unmapped, ${fit.dropped} dropped DQ/zero/DNF)",
  );
  buf.writeln(
    "  R range ${ _fmt(fit.rMin)} … ${_fmt(fit.rMax)}  "
    "(median ${_fmt(fit.rMedian)})",
  );
  buf.writeln(
    "  Huber  slope=${_fmt(fit.huber.slope)}  intercept=${_fmt(fit.huber.intercept)}  "
    "iters=${fit.huber.iterations}  meanWeight=${_fmt(fit.meanWeight)}  "
    "downweighted=${(fit.fracDownweighted * 100).toStringAsFixed(1)}%",
  );
  buf.writeln(
    "  Theil-Sen slope=${_fmt(fit.theilSen.slope)}  intercept=${_fmt(fit.theilSen.intercept)}",
  );
  buf.writeln(
    "  OLS       slope=${_fmt(fit.ols.slope)}  intercept=${_fmt(fit.ols.intercept)}",
  );
  final expected = math.exp(kRefRatingGap);
  final stretched = math.exp(kRefRatingGap * fit.huber.slope);
  buf.writeln(
    "  A ${_fmt(kRefRatingGap)} rating gap expects ${expected.toStringAsFixed(3)}×; "
    "this match stretches that to ${stretched.toStringAsFixed(3)}× "
    "(Huber).",
  );
  if (fit.midScratchRatio != null) {
    buf.writeln(
      "  Scratch (top ${(kScratchTopFrac * 100).toStringAsFixed(0)}%, n=${fit.scratchN}) vs "
      "mid ${(kMidLo * 100).toStringAsFixed(0)}–${(kMidHi * 100).toStringAsFixed(0)}% "
      "(n=${fit.midN}): observed/expected log-gap = ${_fmt(fit.midScratchRatio!)}  "
      "(obs=${_fmt(fit.observedMidScratchGap!)}, exp=${_fmt(fit.expectedMidScratchGap!)})",
    );
  }
  else {
    buf.writeln("  Scratch vs mid band: insufficient people in one or both bands.");
  }
  buf.writeln(
    "  Quintile mean residual vs slope=1 after removing median(L−R) "
    "(Q1=lowest rated):",
  );
  buf.write("   ");
  for (var q = 0; q < kQuintiles; q++) {
    final r = fit.quintileResiduals[q];
    final label = "Q${q + 1}";
    if (r == null) {
      buf.write(" $label=—");
    }
    else {
      buf.write(" $label=${_fmt(r)}");
    }
  }
  buf.writeln("");
  buf.writeln("");
}

_GroupFit? _fitGroup({
  required AnalystDatabase db,
  required DbRatingProject project,
  required ShootingMatch match,
  required RatingGroup group,
  required int minN,
}) {
  final scores = match.getScoresFromFilters(group.filters);
  if (scores.isEmpty) {
    return null;
  }

  var rosterN = 0;
  var unmapped = 0;
  var dropped = 0;
  final points = <_Point>[];

  for (final kv in scores.entries) {
    final entry = kv.key;
    final rel = kv.value;
    if (entry.dq) {
      dropped++;
      continue;
    }
    if (!group.filters.reentries && entry.reentry) {
      continue;
    }
    rosterN++;
    if (!rel.hasResults || rel.ratio <= 0) {
      dropped++;
      continue;
    }

    final dbRating = _lookupRating(db, project, group, entry);
    if (dbRating == null) {
      unmapped++;
      continue;
    }
    final wrapped = project.wrapDbRatingSync(dbRating);
    final pre = wrapped.ratingForEvent(match, null, beforeMatch: true);
    points.add(_Point(r: pre, l: math.log(rel.ratio)));
  }

  if (points.length < minN) {
    return null;
  }

  final rs = points.map((p) => p.r).toList();
  final ls = points.map((p) => p.l).toList();
  final ols = _ols(rs, ls);
  final huber = _huberIrlS(rs, ls, initial: ols);
  final theil = _theilSen(rs, ls);

  var weightSum = 0.0;
  var downweighted = 0;
  final scale = _madScale(
    List<double>.generate(points.length, (i) => ls[i] - (huber.intercept + huber.slope * rs[i])),
  );
  for (var i = 0; i < points.length; i++) {
    final resid = ls[i] - (huber.intercept + huber.slope * rs[i]);
    final w = _huberWeight(scale <= 0 ? 0.0 : resid / scale, kHuberK);
    weightSum += w;
    if (w < 1.0 - 1e-12) {
      downweighted++;
    }
  }

  final sortedByR = [...points]..sort((a, b) => a.r.compareTo(b.r));
  final lr = sortedByR.map((p) => p.l - p.r).toList();
  final intercept1 = _median(lr);
  final quintileResiduals = List<double?>.filled(kQuintiles, null);
  final n = sortedByR.length;
  for (var q = 0; q < kQuintiles; q++) {
    final start = (q * n / kQuintiles).floor();
    final end = ((q + 1) * n / kQuintiles).floor();
    if (end <= start) {
      continue;
    }
    final slice = sortedByR.sublist(start, end);
    final vals = slice.map((p) => p.l - p.r - intercept1).toList();
    quintileResiduals[q] = vals.average;
  }

  double? midScratchRatio;
  double? observedGap;
  double? expectedGap;
  var scratchN = 0;
  var midN = 0;
  final scratchCut = (n * (1.0 - kScratchTopFrac)).floor();
  final midLo = (n * kMidLo).floor();
  final midHi = (n * kMidHi).ceil();
  if (scratchCut < n && midHi > midLo) {
    final scratch = sortedByR.sublist(scratchCut);
    final mid = sortedByR.sublist(midLo, math.min(midHi, n));
    scratchN = scratch.length;
    midN = mid.length;
    if (scratchN >= 3 && midN >= 3) {
      final lScratch = _median(scratch.map((p) => p.l).toList());
      final lMid = _median(mid.map((p) => p.l).toList());
      final rScratch = _median(scratch.map((p) => p.r).toList());
      final rMid = _median(mid.map((p) => p.r).toList());
      observedGap = lScratch - lMid;
      expectedGap = rScratch - rMid;
      if (expectedGap.abs() > 1e-9) {
        midScratchRatio = observedGap / expectedGap;
      }
    }
  }

  final rSorted = [...rs]..sort();
  return _GroupFit(
    groupLabel: group.uiLabel,
    n: points.length,
    rosterN: rosterN,
    unmapped: unmapped,
    dropped: dropped,
    rMin: rSorted.first,
    rMax: rSorted.last,
    rMedian: _median(rSorted),
    huber: huber,
    theilSen: theil,
    ols: ols,
    meanWeight: weightSum / points.length,
    fracDownweighted: downweighted / points.length,
    quintileResiduals: quintileResiduals,
    midScratchRatio: midScratchRatio,
    observedMidScratchGap: observedGap,
    expectedMidScratchGap: expectedGap,
    scratchN: scratchN,
    midN: midN,
  );
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

class _Point {
  _Point({required this.r, required this.l});
  final double r;
  final double l;
}

class _Line {
  const _Line({required this.intercept, required this.slope, this.iterations = 1});
  final double intercept;
  final double slope;
  final int iterations;
}

class _GroupFit {
  _GroupFit({
    required this.groupLabel,
    required this.n,
    required this.rosterN,
    required this.unmapped,
    required this.dropped,
    required this.rMin,
    required this.rMax,
    required this.rMedian,
    required this.huber,
    required this.theilSen,
    required this.ols,
    required this.meanWeight,
    required this.fracDownweighted,
    required this.quintileResiduals,
    required this.midScratchRatio,
    required this.observedMidScratchGap,
    required this.expectedMidScratchGap,
    required this.scratchN,
    required this.midN,
  });

  String matchName = "";
  String matchDate = "";
  final String groupLabel;
  final int n;
  final int rosterN;
  final int unmapped;
  final int dropped;
  final double rMin;
  final double rMax;
  final double rMedian;
  final _Line huber;
  final _Line theilSen;
  final _Line ols;
  final double meanWeight;
  final double fracDownweighted;
  final List<double?> quintileResiduals;
  final double? midScratchRatio;
  final double? observedMidScratchGap;
  final double? expectedMidScratchGap;
  final int scratchN;
  final int midN;
}

_Line _ols(List<double> x, List<double> y) {
  return _wls(x, y, List<double>.filled(x.length, 1.0));
}

_Line _wls(List<double> x, List<double> y, List<double> w) {
  var sumW = 0.0;
  var sumWX = 0.0;
  var sumWY = 0.0;
  var sumWXX = 0.0;
  var sumWXY = 0.0;
  for (var i = 0; i < x.length; i++) {
    final wi = w[i];
    sumW += wi;
    sumWX += wi * x[i];
    sumWY += wi * y[i];
    sumWXX += wi * x[i] * x[i];
    sumWXY += wi * x[i] * y[i];
  }
  final den = sumW * sumWXX - sumWX * sumWX;
  if (den.abs() < 1e-18 || sumW <= 0) {
    return _Line(intercept: y.isEmpty ? 0.0 : _median(y), slope: 0.0);
  }
  final slope = (sumW * sumWXY - sumWX * sumWY) / den;
  final intercept = (sumWY - slope * sumWX) / sumW;
  return _Line(intercept: intercept, slope: slope);
}

_Line _huberIrlS(List<double> x, List<double> y, {required _Line initial}) {
  var intercept = initial.intercept;
  var slope = initial.slope;
  var iters = 0;
  for (var iter = 0; iter < 50; iter++) {
    iters = iter + 1;
    final resid = List<double>.generate(x.length, (i) => y[i] - (intercept + slope * x[i]));
    final scale = _madScale(resid);
    final weights = <double>[];
    for (final r in resid) {
      final z = scale <= 0 ? 0.0 : r / scale;
      weights.add(_huberWeight(z, kHuberK));
    }
    final next = _wls(x, y, weights);
    final da = (next.intercept - intercept).abs();
    final db = (next.slope - slope).abs();
    intercept = next.intercept;
    slope = next.slope;
    if (da < 1e-10 && db < 1e-10) {
      break;
    }
  }
  return _Line(intercept: intercept, slope: slope, iterations: iters);
}

_Line _theilSen(List<double> x, List<double> y) {
  final slopes = <double>[];
  for (var i = 0; i < x.length; i++) {
    for (var j = i + 1; j < x.length; j++) {
      final dx = x[j] - x[i];
      if (dx.abs() < 1e-12) {
        continue;
      }
      slopes.add((y[j] - y[i]) / dx);
    }
  }
  if (slopes.isEmpty) {
    return _Line(intercept: _median(y), slope: 0.0);
  }
  final slope = _median(slopes);
  final intercepts = List<double>.generate(x.length, (i) => y[i] - slope * x[i]);
  return _Line(intercept: _median(intercepts), slope: slope);
}

double _huberWeight(double z, double k) {
  final absZ = z.abs();
  if (k <= 0 || absZ <= k) {
    return 1.0;
  }
  return k / absZ;
}

double _madScale(List<double> resid) {
  if (resid.isEmpty) {
    return 0.0;
  }
  final med = _median(resid);
  final absDev = resid.map((r) => (r - med).abs()).toList();
  final mad = _median(absDev);
  final scale = mad / 0.67448975;
  return math.max(scale, 1e-12);
}

double _median(List<double> xs) {
  if (xs.isEmpty) {
    return 0.0;
  }
  final s = [...xs]..sort();
  final mid = s.length ~/ 2;
  if (s.length.isOdd) {
    return s[mid];
  }
  return 0.5 * (s[mid - 1] + s[mid]);
}

double _percentile(List<double> xs, double p) {
  if (xs.isEmpty) {
    return 0.0;
  }
  final s = [...xs]..sort();
  if (s.length == 1) {
    return s.first;
  }
  final idx = (p * (s.length - 1)).clamp(0.0, (s.length - 1).toDouble());
  final lo = idx.floor();
  final hi = idx.ceil();
  if (lo == hi) {
    return s[lo];
  }
  final t = idx - lo;
  return s[lo] * (1 - t) + s[hi] * t;
}

double _percentileRank(List<double> xs, double value) {
  if (xs.isEmpty) {
    return 0.0;
  }
  var le = 0;
  for (final x in xs) {
    if (x <= value) {
      le++;
    }
  }
  return 100.0 * le / xs.length;
}

String _fmt(double x) => x.toStringAsFixed(3);

String _pad(String s, int width) {
  if (s.length >= width) {
    return s;
  }
  return s.padRight(width);
}
