// ignore_for_file: unused_local_variable

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Comparative connectivity research.
///
/// Builds a clustered match graph (club locals, an isolated mega-series,
/// area matches, nationals, and travelers) and scores every participant with
/// several candidate measures after each match.
///
/// Run with:
///   dart run research/connectivity/connectivity_simulation.dart
///   dart run research/connectivity/connectivity_simulation.dart --isolated-sweep
///
/// Competitor methods:
///   sqrt      geometric mean of unique 1-hop neighbors and encounters
///   carriers  field-size moments (production RatingCarrier formula)
///   effective geometric mean of effective degree and encounters
///   credit    recency-weighted mean of recent coverage credits
///
/// Match-level coverage is calculated directly from pre-match neighborhoods.

import "dart:math";

import "package:collection/collection.dart";

const int kSeed = 42;
const int kRegionCount = 8;
const int kIsolatedRegion = 0;
const int kClubsPerRegion = 5;
const int kMatchCount = 1800;
const int kWindowSize = 5;
const int kLocalHighPerRegion = 220;
const int kTravelerCount = 350;
const int kIsolatedHighCount = 280;
const int kInitialLowPerRegion = 280;

enum CompetitorKind {
  localHigh,
  localLow,
  traveler,
  isolatedHigh,
}

enum MatchKind {
  club,
  isolatedMega,
  area,
  national,
}

void main(List<String> args) {
  _runMetricSelfTests();
  if (args.contains("--isolated-sweep")) {
    runIsolatedPopulationSweep();
    return;
  }

  print("Generating clustered match graph (seed $kSeed)...");
  var world = generateEntities();
  var competitors = world.competitors;
  var matches = world.matches;

  print("Processing ${matches.length} matches...");
  var tracker = ConnectivityTracker();
  var processed = 0;
  for (var match in matches.values) {
    var matchCompetitors = <int, Competitor>{
      for (var id in match.competitorIds) id: competitors[id]!,
    };
    tracker.processMatch(match, matchCompetitors);
    processed++;
    if (processed % 100 == 0) {
      print("  Processed $processed/${matches.length}");
    }
  }

  print("Analyzing...");
  analyzeConnectivity(tracker, competitors, matches);
}

void runIsolatedPopulationSweep() {
  const populationSizes = [280, 500, 1000, 2000, 4000];
  const fieldSize = 188;
  const targetMatchesPerCompetitor = 100;
  const warmupMatchesPerCompetitor = 20;
  var rows = <List<String>>[];

  print("Running isolated-component population sweep...");
  print("Field size: $fieldSize");
  print("Target matches per competitor: $targetMatchesPerCompetitor");

  for (var populationSize in populationSizes) {
    var random = Random(kSeed + populationSize);
    var competitors = <int, Competitor>{
      for (var id = 0; id < populationSize; id++)
        id: Competitor(id, CompetitorKind.isolatedHigh, kIsolatedRegion, 0),
    };
    var competitorList = competitors.values.toList();
    var matchCount = (populationSize * targetMatchesPerCompetitor / fieldSize).ceil();
    var warmupCount = (populationSize * warmupMatchesPerCompetitor / fieldSize).ceil();
    var tracker = ConnectivityTracker();
    var measuredMatches = <Match>[];
    var date = DateTime(2018, 1, 1);

    for (var matchId = 0; matchId < matchCount; matchId++) {
      var match = Match(
        matchId,
        date,
        MatchKind.isolatedMega,
        const [kIsolatedRegion],
      );
      var selected = competitorList.sample(fieldSize, random);
      for (var competitor in selected) {
        match.competitorIds.add(competitor.shooterId);
        competitor.matchIds.add(matchId);
      }
      tracker.processMatch(
        match,
        {for (var competitor in selected) competitor.shooterId: competitor},
      );
      if (matchId >= warmupCount) {
        measuredMatches.add(match);
      }
      date = date.add(const Duration(days: 1));
    }

    var maxExternal = populationSize - fieldSize;
    var coverageMean = measuredMatches.map((m) => m.externalCoverage).average;
    var active = competitorList.where((c) => c.matchCount > 0).toList();
    var projected200kMs = tracker.mathWatch.elapsedMilliseconds /
        tracker.scoredEntries *
        200000;
    rows.add([
      "$populationSize",
      "$matchCount",
      competitorList.map((c) => c.matchIds.length).average.toStringAsFixed(1),
      coverageMean.toStringAsFixed(1),
      (coverageMean / maxExternal).toStringAsFixed(3),
      measuredMatches.map((m) => m.coverageEfficiency).average.toStringAsFixed(3),
      measuredMatches.map((m) => m.effectiveCarrierCount).average.toStringAsFixed(1),
      measuredMatches.map((m) => m.matchScores.credit).average.toStringAsFixed(1),
      active.map((c) => c.recentCoverageCredit).average.toStringAsFixed(1),
      active.map((c) => c.uniqueOpponentCount).average.toStringAsFixed(0),
      active.map((c) => c.effectiveDegree).average.toStringAsFixed(1),
      projected200kMs.toStringAsFixed(0),
    ]);
    print("  Completed population $populationSize "
        "($matchCount matches, ${tracker.mathWatch.elapsedMilliseconds}ms math)");
  }

  print("\n========== Equal-Activity Isolated Population Sweep ==========");
  _printTable(
    [
      "population",
      "matches",
      "matches/c",
      "coverage",
      "coverage/max",
      "efficiency",
      "carriers",
      "match Q",
      "shooter Q",
      "U",
      "D_eff",
      "200k ms",
    ],
    rows,
  );
  print("\nEvery population above is completely disconnected. Growth in coverage or credit "
      "therefore reflects component population size, not attachment to a global component.");
}

World generateEntities() {
  var random = Random(kSeed);
  var competitors = <int, Competitor>{};
  var matches = <int, Match>{};
  var nextId = 0;

  Competitor addCompetitor(CompetitorKind kind, int homeRegion) {
    var homeClub = switch (kind) {
      CompetitorKind.traveler => -1,
      CompetitorKind.isolatedHigh => 0,
      _ => random.nextInt(kClubsPerRegion),
    };
    var c = Competitor(nextId, kind, homeRegion, homeClub);
    competitors[nextId] = c;
    nextId++;
    return c;
  }

  // Region 0 is a deliberately isolated population. Ordinary locals live in
  // regions 1 through 7 so that the simulation has a clean isolated control.
  for (var region = 1; region < kRegionCount; region++) {
    for (var i = 0; i < kLocalHighPerRegion; i++) {
      addCompetitor(CompetitorKind.localHigh, region);
    }
    for (var i = 0; i < kInitialLowPerRegion; i++) {
      addCompetitor(CompetitorKind.localLow, region);
    }
  }
  for (var i = 0; i < kTravelerCount; i++) {
    addCompetitor(CompetitorKind.traveler, 1 + random.nextInt(kRegionCount - 1));
  }
  for (var i = 0; i < kIsolatedHighCount; i++) {
    addCompetitor(CompetitorKind.isolatedHigh, kIsolatedRegion);
  }

  print("  Competitors: ${competitors.length} "
      "(${kLocalHighPerRegion * (kRegionCount - 1)} local-high, "
      "$kTravelerCount travelers, "
      "$kIsolatedHighCount isolated-high, "
      "${kInitialLowPerRegion * (kRegionCount - 1)} local-low)");

  var start = DateTime(2018, 1, 1);
  var currentYear = 2018;
  var totalEntries = 0;

  double lowRetireRate = 0.20;
  double lowGrowRate = 0.24;
  double highRetireRate = 0.03;
  double highGrowRate = 0.03;

  List<Competitor> activeOf(CompetitorKind kind, {int? region}) {
    return competitors.values.where((c) {
      if (c.retired || c.kind != kind) {
        return false;
      }
      if (region != null && c.homeRegion != region) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Competitor> activeHome(int region) {
    return competitors.values.where((c) {
      if (c.retired || c.homeRegion != region) {
        return false;
      }
      return c.kind != CompetitorKind.traveler;
    }).toList();
  }

  List<Competitor> activeClub(int region, int club) {
    return competitors.values.where((c) {
      return !c.retired &&
          c.homeRegion == region &&
          c.homeClub == club &&
          c.kind != CompetitorKind.traveler;
    }).toList();
  }

  for (var matchId = 0; matchId < kMatchCount; matchId++) {
    if (start.year > currentYear) {
      currentYear = start.year;
      var low = competitors.values.where((c) => !c.retired && c.kind == CompetitorKind.localLow).toList();
      var high = competitors.values.where((c) => !c.retired && c.kind != CompetitorKind.localLow).toList();
      var lowRetire = (low.length * (lowRetireRate + random.nextDouble() * 0.05 - 0.025)).round();
      var highRetire = (high.length * (highRetireRate + random.nextDouble() * 0.01 - 0.005)).round();
      var lowAdd = (low.length * (lowGrowRate + random.nextDouble() * 0.03 - 0.015)).round();
      var highAdd = (high.length * (highGrowRate + random.nextDouble() * 0.01 - 0.005)).round();
      print("  Year $currentYear: retire $lowRetire low / $highRetire high, add $lowAdd low / $highAdd high");

      for (var c in low.sample(min(lowRetire, low.length), random)) {
        c.retired = true;
      }
      for (var c in high.sample(min(highRetire, high.length), random)) {
        c.retired = true;
      }
      for (var i = 0; i < lowAdd; i++) {
        addCompetitor(CompetitorKind.localLow, 1 + random.nextInt(kRegionCount - 1));
      }
      for (var i = 0; i < highAdd; i++) {
        var roll = random.nextDouble();
        if (roll < 0.12) {
          addCompetitor(CompetitorKind.traveler, 1 + random.nextInt(kRegionCount - 1));
        }
        else if (roll < 0.22) {
          addCompetitor(CompetitorKind.isolatedHigh, kIsolatedRegion);
        }
        else {
          addCompetitor(CompetitorKind.localHigh, 1 + random.nextInt(kRegionCount - 1));
        }
      }
    }

    var roll = random.nextDouble();
    MatchKind kind;
    var regions = <int>[];
    int size;
    if (roll < 0.10) {
      kind = MatchKind.isolatedMega;
      regions = [kIsolatedRegion];
      size = _logNormalSize(random, median: 180, sigma: 0.25, min: 120, max: 280);
    }
    else if (roll < 0.18) {
      kind = MatchKind.national;
      regions = [for (var r = 0; r < kRegionCount; r++) r];
      size = _logNormalSize(random, median: 220, sigma: 0.25, min: 140, max: 400);
    }
    else if (roll < 0.38) {
      kind = MatchKind.area;
      var startRegion = 1 + random.nextInt(kRegionCount - 1);
      regions = [
        startRegion,
        1 + (startRegion % (kRegionCount - 1)),
        1 + ((startRegion + 1) % (kRegionCount - 1)),
      ];
      size = _logNormalSize(random, median: 120, sigma: 0.3, min: 70, max: 200);
    }
    else {
      kind = MatchKind.club;
      var region = 1 + random.nextInt(kRegionCount - 1);
      regions = [region];
      size = _logNormalSize(random, median: 50, sigma: 0.35, min: 25, max: 90);
    }

    var match = Match(matchId, start, kind, regions);
    var selected = <int>{};

    void take(List<Competitor> pool, int n) {
      var remainingSlots = size - selected.length;
      if (n <= 0 || remainingSlots <= 0) {
        return;
      }
      var available = pool.where((c) => !selected.contains(c.shooterId)).toList();
      var takeN = min(min(n, remainingSlots), available.length);
      if (takeN <= 0) {
        return;
      }
      for (var c in available.sample(takeN, random)) {
        selected.add(c.shooterId);
        match.competitorIds.add(c.shooterId);
        c.matchIds.add(matchId);
      }
    }

    var travelers = activeOf(CompetitorKind.traveler);
    if (kind == MatchKind.club) {
      var region = regions.first;
      var club = random.nextInt(kClubsPerRegion);
      take(travelers, max(1, (size * 0.06).round()));
      var clubPool = activeClub(region, club);
      take(
        clubPool.where((c) => c.kind == CompetitorKind.localHigh).toList(),
        (size * 0.30).round(),
      );
      take(
        clubPool.where((c) => c.kind == CompetitorKind.localLow).toList(),
        size - selected.length,
      );
      take(clubPool, size - selected.length);
      take(activeHome(region), size - selected.length);
    }
    else if (kind == MatchKind.isolatedMega) {
      // No travelers or national competitors: this is the intentionally
      // isolated high-volume control population.
      take(activeOf(CompetitorKind.isolatedHigh), size);
    }
    else if (kind == MatchKind.area) {
      take(travelers, (size * 0.20).round());
      var remaining = size - selected.length;
      var perRegion = (remaining / regions.length).ceil();
      for (var region in regions) {
        take(activeOf(CompetitorKind.localHigh, region: region), (perRegion * 0.65).round());
        take(activeOf(CompetitorKind.localLow, region: region), perRegion);
      }
      if (selected.length < size) {
        take(travelers, size - selected.length);
      }
    }
    else {
      take(travelers, (size * 0.70).round());
      take(activeOf(CompetitorKind.localHigh), (size * 0.15).round());
      take(activeOf(CompetitorKind.localLow), (size * 0.15).round());
      if (selected.length < size) {
        take(travelers, size - selected.length);
      }
      if (selected.length < size) {
        take(activeOf(CompetitorKind.localHigh), size - selected.length);
      }
    }

    if (match.competitorIds.length >= 8) {
      matches[matchId] = match;
      totalEntries += match.competitorIds.length;
    }

    start = start.add(const Duration(hours: 18));
  }

  print("  Matches kept: ${matches.length}");
  print("  Total entries: $totalEntries");
  print("  Final competitors: ${competitors.length} "
      "(${competitors.values.where((c) => !c.retired).length} active)");
  return World(competitors: competitors, matches: matches, totalEntries: totalEntries);
}

class World {
  final Map<int, Competitor> competitors;
  final Map<int, Match> matches;
  final int totalEntries;

  World({
    required this.competitors,
    required this.matches,
    required this.totalEntries,
  });
}

class MatchWindow {
  final int matchId;
  final DateTime date;
  final Set<int> uniqueOpponents;
  final int totalOpponents;
  final int fieldSize;
  final Set<int> regions;
  final MatchKind kind;
  final int externalCoverage;
  final double coverageCredit;
  final double coverageShare;

  MatchWindow({
    required this.matchId,
    required this.date,
    required this.uniqueOpponents,
    required this.totalOpponents,
    required this.fieldSize,
    required this.regions,
    required this.kind,
    required this.externalCoverage,
    required this.coverageCredit,
    required this.coverageShare,
  });
}

class ScoreSet {
  double sqrt = 0;
  double carriers = 0;
  double effective = 0;
  double credit = 0;

  double operator [](String name) {
    return switch (name) {
      "sqrt" => sqrt,
      "carriers" => carriers,
      "effective" => effective,
      "credit" => credit,
      _ => throw ArgumentError.value(name),
    };
  }
}

const methodNames = ["sqrt", "carriers", "effective", "credit"];

class CoverageCreditResult {
  final int externalCoverage;
  final int externalEdgeMass;
  final double coverageEfficiency;
  final double effectiveCarrierCount;
  final Map<int, double> credits;

  const CoverageCreditResult({
    required this.externalCoverage,
    required this.externalEdgeMass,
    required this.coverageEfficiency,
    required this.effectiveCarrierCount,
    required this.credits,
  });
}

CoverageCreditResult calculateCoverageCredit({
  required Set<int> field,
  required Map<int, Set<int>> neighborhoods,
}) {
  var externalByShooter = <int, Set<int>>{};
  var externalMultiplicity = <int, int>{};
  for (var entry in neighborhoods.entries) {
    var external = entry.value.difference(field);
    externalByShooter[entry.key] = external;
    for (var id in external) {
      externalMultiplicity[id] = (externalMultiplicity[id] ?? 0) + 1;
    }
  }

  var externalCoverage = externalMultiplicity.length;
  var externalEdgeMass = externalByShooter.values.map((ids) => ids.length).sum;
  var credits = <int, double>{};
  for (var entry in externalByShooter.entries) {
    var credit = 0.0;
    for (var id in entry.value) {
      credit += 1.0 / externalMultiplicity[id]!;
    }
    credits[entry.key] = credit;
  }

  var creditSum = credits.values.sum;
  var creditSumSquared = credits.values.map((credit) => credit * credit).sum;
  return CoverageCreditResult(
    externalCoverage: externalCoverage,
    externalEdgeMass: externalEdgeMass,
    coverageEfficiency: externalEdgeMass == 0 ? 0 : externalCoverage / externalEdgeMass,
    effectiveCarrierCount: creditSumSquared == 0
        ? 0
        : creditSum * creditSum / creditSumSquared,
    credits: credits,
  );
}

class Competitor {
  Competitor(this.shooterId, this.kind, this.homeRegion, this.homeClub);

  final int shooterId;
  final CompetitorKind kind;
  final int homeRegion;
  final int homeClub;
  final List<int> matchIds = [];
  final List<MatchWindow> allWindows = [];
  final ScoreSet scores = ScoreSet();
  bool retired = false;

  List<MatchWindow> get windows => allWindows.getTailWindow(kWindowSize);

  void addMatch({
    required int matchId,
    required DateTime date,
    required Iterable<int> opponents,
    required Set<int> regions,
    required MatchKind kind,
    required int externalCoverage,
    required double coverageCredit,
    required double coverageShare,
  }) {
    var ids = opponents.where((id) => id != shooterId).toSet();
    allWindows.add(MatchWindow(
      matchId: matchId,
      date: date,
      uniqueOpponents: ids,
      totalOpponents: ids.length,
      fieldSize: opponents.length,
      regions: {...regions},
      kind: kind,
      externalCoverage: externalCoverage,
      coverageCredit: coverageCredit,
      coverageShare: coverageShare,
    ));
  }

  int get matchCount => windows.length;

  Set<int> get uniqueOpponents => windows.expand((w) => w.uniqueOpponents).toSet();

  int get uniqueOpponentCount => uniqueOpponents.length;

  int get totalOpponentCount => windows.map((w) => w.totalOpponents).sum;

  int get regionDiversity => windows.expand((w) => w.regions).toSet().length;

  double get effectiveDegree {
    var counts = <int, double>{};
    for (var window in windows) {
      for (var id in window.uniqueOpponents) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return _effectiveDegreeFromCounts(counts.values);
  }

  double get recentCoverageCredit => _recencyWeightedMean(
    windows.map((w) => w.coverageCredit).toList(),
  );

  double get recentCoverageShare => _recencyWeightedMean(
    windows.map((w) => w.coverageShare).toList(),
  );

  double get meanFieldSize {
    if (windows.isEmpty) {
      return 0;
    }
    return windows.map((w) => w.fieldSize).average;
  }

  int get lastExternalCoverage => windows.isEmpty ? 0 : windows.last.externalCoverage;
}

class Match {
  Match(this.matchId, this.start, this.kind, this.regions);

  final int matchId;
  final DateTime start;
  final MatchKind kind;
  final List<int> regions;
  final List<int> competitorIds = [];

  int externalCoverage = 0;
  int externalEdgeMass = 0;
  double coverageEfficiency = 0;
  double effectiveCarrierCount = 0;
  int creditedCarrierCount = 0;
  final ScoreSet matchScores = ScoreSet();
}

class ConnectivityTracker {
  final Stopwatch mathWatch = Stopwatch();
  int scoredEntries = 0;

  void processMatch(
    Match match,
    Map<int, Competitor> matchCompetitors,
  ) {
    var field = match.competitorIds.toSet();
    var fieldSize = field.length;
    if (fieldSize < 2) {
      return;
    }

    mathWatch.start();

    // Match connectivity is causal: snapshot and aggregate participant scores
    // before adding the current match to anyone's windows.
    _fillMatchScores(match, matchCompetitors.values.map((c) => c.scores).toList());

    var coverage = calculateCoverageCredit(
      field: field,
      neighborhoods: {
        for (var competitor in matchCompetitors.values)
          competitor.shooterId: competitor.uniqueOpponents,
      },
    );
    match.externalCoverage = coverage.externalCoverage;
    match.externalEdgeMass = coverage.externalEdgeMass;
    match.coverageEfficiency = coverage.coverageEfficiency;
    match.effectiveCarrierCount = coverage.effectiveCarrierCount;
    match.creditedCarrierCount = coverage.credits.values.where((credit) => credit > 0).length;

    for (var competitor in matchCompetitors.values) {
      var credit = coverage.credits[competitor.shooterId]!;
      competitor.addMatch(
        matchId: match.matchId,
        date: match.start,
        opponents: match.competitorIds,
        regions: match.regions.toSet(),
        kind: match.kind,
        externalCoverage: match.externalCoverage,
        coverageCredit: credit,
        coverageShare: match.externalCoverage == 0 ? 0 : credit / match.externalCoverage,
      );
    }

    for (var competitor in matchCompetitors.values) {
      var unique = competitor.uniqueOpponentCount;
      var total = competitor.totalOpponentCount;
      var ownSqrt = unique == 0 || total == 0 ? 0.0 : sqrt(unique * total);
      var carriers = _carriersScore(competitor);
      var effective = competitor.effectiveDegree;
      var effectiveScore = effective == 0 || total == 0
          ? 0.0
          : sqrt(effective * total);

      competitor.scores.sqrt = ownSqrt;
      competitor.scores.carriers = carriers;
      competitor.scores.effective = effectiveScore;
      competitor.scores.credit = competitor.recentCoverageCredit;
      scoredEntries++;
    }

    mathWatch.stop();
  }

  void _fillMatchScores(Match match, List<ScoreSet> participantScores) {
    if (participantScores.isEmpty) {
      return;
    }
    for (var name in methodNames) {
      var values = participantScores.map((s) => s[name]).toList()..sort();
      // Mirror the production aggregators where they exist. Effective degree
      // and credit use the sqrt calculator's robust match aggregator.
      var matchScore = name == "carriers"
          ? values.average
          : _medianSorted(values) * 0.7 + values.last * 0.3;
      switch (name) {
        case "sqrt":
          match.matchScores.sqrt = matchScore;
        case "carriers":
          match.matchScores.carriers = matchScore;
        case "effective":
          match.matchScores.effective = matchScore;
        case "credit":
          match.matchScores.credit = matchScore;
      }
    }
  }
}

double _carriersScore(Competitor competitor) {
  var recent = competitor.windows.map((w) => w.fieldSize).toList();
  if (recent.isEmpty) {
    return 0.0;
  }

  var weightedSum = 0.0;
  var totalWeight = 0.0;
  for (var i = 0; i < recent.length; i++) {
    var weight = 1.0 + (i * 0.2);
    weightedSum += recent[i] * weight;
    totalWeight += weight;
  }
  var fieldQuality = sqrt(weightedSum / totalWeight) * 25;

  if (recent.length <= 1) {
    return fieldQuality;
  }

  var mean = recent.average;
  var sumSquared = recent.map((s) => s * s).sum.toDouble();
  var variance = (sumSquared / recent.length) - (mean * mean);
  if (variance < 0) {
    variance = 0;
  }
  var range = (recent.max - recent.min).toDouble();
  var diversity = (1.0 + log(sqrt(variance) + 1) * 0.05) * (1.0 + log(range + 1) * 0.03);

  var skewSource = competitor.allWindows.map((w) => w.fieldSize).toList();
  if (skewSource.length > 12) {
    skewSource = skewSource.sublist(skewSource.length - 12);
  }
  var skewness = _skewness(skewSource);
  double bridge;
  if (skewness > 0) {
    bridge = 1.0 + (skewness * 0.1).clamp(0.0, 0.2);
  }
  else {
    bridge = 1.0 + (skewness * 0.05).clamp(-0.1, 0.0);
  }

  return fieldQuality * diversity * bridge;
}

void analyzeConnectivity(
  ConnectivityTracker tracker,
  Map<int, Competitor> competitors,
  Map<int, Match> matches,
) {
  var active = competitors.values.where((c) => !c.retired && c.matchCount > 0).toList();
  var stale = competitors.values.where((c) => c.retired && c.matchCount > 0).toList();
  var matchList = matches.values.toList();
  var mathMs = tracker.mathWatch.elapsedMilliseconds;
  var entries = tracker.scoredEntries;

  print("\n========== Timing ==========");
  print("Scored entries: $entries");
  print("Math time: ${mathMs}ms (${entries == 0 ? 0 : mathMs / entries * 1000} µs/entry)");
  print("Extrapolated 200k entries: ${entries == 0 ? 0 : (mathMs / entries * 200000).toStringAsFixed(0)}ms");

  print("\n========== Generator Sanity ==========");
  print("Living competitors in analysis: ${active.length}");
  print("Retired competitors excluded: ${stale.length}");
  _printKindCounts(matchList);
  print("");
  _printTable(
    ["Kind", "n", "Matches", "Regions", "Club%", "Mega%", "Area%", "Nat%"],
    [
      for (var kind in CompetitorKind.values)
        _competitorSanityRow(active.where((c) => c.kind == kind).toList()),
    ],
  );

  print("\n========== Shooter Scores By Archetype (mean) ==========");
  _printTable(
    ["Kind", "n", "U", "T", "D_eff", "D/U", "Q", "Q share", "reg", "field", ...methodNames],
    [
      for (var kind in CompetitorKind.values)
        _archetypeRow(active.where((c) => c.kind == kind).toList()),
    ],
  );

  print("\n========== Match Scores By Type (mean) ==========");
  _printTable(
    ["Type", "n", "size", "coverage", "edge mass", "efficiency", "carriers", ...methodNames],
    [
      for (var kind in MatchKind.values)
        _matchTypeRow(matchList.where((m) => m.kind == kind).toList()),
    ],
  );

  print("\n========== Coverage Credit By Archetype And Match Type ==========");
  print("Values are means over each living competitor's five-match window.");
  _printTable(
    ["Kind", for (var kind in MatchKind.values) kind.name],
    [
      for (var kind in CompetitorKind.values)
        _coverageCreditByMatchTypeRow(
          active.where((c) => c.kind == kind).toList(),
        ),
    ],
  );

  print("\n========== Rank Correlations Between Methods (shooters) ==========");
  _printCorrelationMatrix(active, (c) => c.scores);

  print("\n========== Rank Correlations Between Methods (matches) ==========");
  _printCorrelationMatrix(matchList, (m) => m.matchScores);

  print("\n========== What Each Method Tracks (shooter Spearman) ==========");
  print("Feature proxies: region diversity, field size, unique 1-hop, effective degree, and coverage credit.");
  _printTable(
    ["Method", "vs regions", "vs field", "vs unique", "vs D_eff", "vs Q"],
    [
      for (var name in methodNames)
        [
          name,
          _spearman(active.map((c) => c.scores[name]).toList(), active.map((c) => c.regionDiversity.toDouble()).toList()).toStringAsFixed(3),
          _spearman(active.map((c) => c.scores[name]).toList(), active.map((c) => c.meanFieldSize).toList()).toStringAsFixed(3),
          _spearman(active.map((c) => c.scores[name]).toList(), active.map((c) => c.uniqueOpponentCount.toDouble()).toList()).toStringAsFixed(3),
          _spearman(active.map((c) => c.scores[name]).toList(), active.map((c) => c.effectiveDegree).toList()).toStringAsFixed(3),
          _spearman(active.map((c) => c.scores[name]).toList(), active.map((c) => c.recentCoverageCredit).toList()).toStringAsFixed(3),
        ],
    ],
  );

  print("\n========== Top-20 Composition By Method ==========");
  _printTable(
    ["Method", "traveler%", "isolated%", "localHigh%", "localLow%"],
    [
      for (var name in methodNames) _topCompositionRow(active, name, 20),
    ],
  );

  print("\n========== Isolated Mega vs National (pre-match scores) ==========");
  print("The direct coverage rows measure graph attachment; competitor methods contain only historical information.");
  var megas = matchList.where((m) => m.kind == MatchKind.isolatedMega).toList();
  var nationals = matchList.where((m) => m.kind == MatchKind.national).toList();
  _printTable(
    ["Method", "mega mean", "nat mean", "nat/mega", "size-corr"],
    [
      [
        "coverage",
        megas.map((m) => m.externalCoverage.toDouble()).average.toStringAsFixed(1),
        nationals.map((m) => m.externalCoverage.toDouble()).average.toStringAsFixed(1),
        (nationals.map((m) => m.externalCoverage.toDouble()).average / max(1.0, megas.map((m) => m.externalCoverage.toDouble()).average)).toStringAsFixed(2),
        _spearman(matchList.map((m) => m.externalCoverage.toDouble()).toList(), matchList.map((m) => m.competitorIds.length.toDouble()).toList()).toStringAsFixed(3),
      ],
      [
        "efficiency",
        megas.map((m) => m.coverageEfficiency).average.toStringAsFixed(3),
        nationals.map((m) => m.coverageEfficiency).average.toStringAsFixed(3),
        (nationals.map((m) => m.coverageEfficiency).average / max(1e-6, megas.map((m) => m.coverageEfficiency).average)).toStringAsFixed(2),
        _spearman(matchList.map((m) => m.coverageEfficiency).toList(), matchList.map((m) => m.competitorIds.length.toDouble()).toList()).toStringAsFixed(3),
      ],
      [
        "effective carriers",
        megas.map((m) => m.effectiveCarrierCount).average.toStringAsFixed(1),
        nationals.map((m) => m.effectiveCarrierCount).average.toStringAsFixed(1),
        (nationals.map((m) => m.effectiveCarrierCount).average / max(1e-6, megas.map((m) => m.effectiveCarrierCount).average)).toStringAsFixed(2),
        _spearman(matchList.map((m) => m.effectiveCarrierCount).toList(), matchList.map((m) => m.competitorIds.length.toDouble()).toList()).toStringAsFixed(3),
      ],
      for (var name in methodNames)
        [
          name,
          megas.map((m) => m.matchScores[name]).average.toStringAsFixed(1),
          nationals.map((m) => m.matchScores[name]).average.toStringAsFixed(1),
          (nationals.map((m) => m.matchScores[name]).average / max(1e-6, megas.map((m) => m.matchScores[name]).average)).toStringAsFixed(2),
          _spearman(matchList.map((m) => m.matchScores[name]).toList(), matchList.map((m) => m.competitorIds.length.toDouble()).toList()).toStringAsFixed(3),
        ],
    ],
  );

  print("\n========== Example Competitors ==========");
  _printExamples(active);

  print("\n========== Score Histograms (active high-volume) ==========");
  var highVolume = active.where((c) => c.matchIds.length >= 8).toList();
  for (var name in methodNames) {
    print("\n$name:");
    print(_createHistogram(
      highVolume.map((c) => c.scores[name]).toList(),
      buckets: 12,
      width: 40,
      entityName: "high-volume",
    ));
  }

  print("\n========== Traveler vs Isolated-High ==========");
  for (var name in methodNames) {
    var travelers = highVolume.where((c) => c.kind == CompetitorKind.traveler).map((c) => c.scores[name]).toList();
    var isolated = highVolume.where((c) => c.kind == CompetitorKind.isolatedHigh).map((c) => c.scores[name]).toList();
    print("\n$name  traveler mean=${travelers.isEmpty ? 0 : travelers.average.toStringAsFixed(1)}  "
        "isolated mean=${isolated.isEmpty ? 0 : isolated.average.toStringAsFixed(1)}  "
        "ratio=${travelers.isEmpty || isolated.isEmpty ? 0 : (travelers.average / max(1e-6, isolated.average)).toStringAsFixed(2)}");
  }
}

List<String> _competitorSanityRow(List<Competitor> group) {
  if (group.isEmpty) {
    return ["(empty)", "0", "0", "0", "-", "-", "-", "-"];
  }
  var kinds = <MatchKind, int>{};
  for (var c in group) {
    for (var w in c.windows) {
      kinds[w.kind] = (kinds[w.kind] ?? 0) + 1;
    }
  }
  var windowTotal = max(1, kinds.values.sum);
  return [
    group.first.kind.name,
    "${group.length}",
    group.map((c) => c.matchIds.length).average.toStringAsFixed(1),
    group.map((c) => c.regionDiversity).average.toStringAsFixed(2),
    ((kinds[MatchKind.club] ?? 0) / windowTotal * 100).toStringAsFixed(0),
    ((kinds[MatchKind.isolatedMega] ?? 0) / windowTotal * 100).toStringAsFixed(0),
    ((kinds[MatchKind.area] ?? 0) / windowTotal * 100).toStringAsFixed(0),
    ((kinds[MatchKind.national] ?? 0) / windowTotal * 100).toStringAsFixed(0),
  ];
}

List<String> _archetypeRow(List<Competitor> group) {
  if (group.isEmpty) {
    return [for (var i = 0; i < 10 + methodNames.length; i++) "-"];
  }
  return [
    group.first.kind.name,
    "${group.length}",
    group.map((c) => c.uniqueOpponentCount).average.toStringAsFixed(0),
    group.map((c) => c.totalOpponentCount).average.toStringAsFixed(0),
    group.map((c) => c.effectiveDegree).average.toStringAsFixed(1),
    group.map((c) => c.uniqueOpponentCount == 0 ? 0 : c.effectiveDegree / c.uniqueOpponentCount).average.toStringAsFixed(3),
    group.map((c) => c.recentCoverageCredit).average.toStringAsFixed(1),
    group.map((c) => c.recentCoverageShare).average.toStringAsFixed(3),
    group.map((c) => c.regionDiversity).average.toStringAsFixed(2),
    group.map((c) => c.meanFieldSize).average.toStringAsFixed(0),
    for (var name in methodNames) group.map((c) => c.scores[name]).average.toStringAsFixed(1),
  ];
}

List<String> _matchTypeRow(List<Match> group) {
  if (group.isEmpty) {
    return [for (var i = 0; i < 7 + methodNames.length; i++) "-"];
  }
  return [
    group.first.kind.name,
    "${group.length}",
    group.map((m) => m.competitorIds.length).average.toStringAsFixed(0),
    group.map((m) => m.externalCoverage).average.toStringAsFixed(0),
    group.map((m) => m.externalEdgeMass).average.toStringAsFixed(0),
    group.map((m) => m.coverageEfficiency).average.toStringAsFixed(3),
    group.map((m) => m.effectiveCarrierCount).average.toStringAsFixed(1),
    for (var name in methodNames) group.map((m) => m.matchScores[name]).average.toStringAsFixed(1),
  ];
}

List<String> _coverageCreditByMatchTypeRow(List<Competitor> group) {
  if (group.isEmpty) {
    return ["(empty)", for (var _ in MatchKind.values) "-"];
  }
  var credits = <MatchKind, List<double>>{
    for (var kind in MatchKind.values) kind: [],
  };
  for (var competitor in group) {
    for (var window in competitor.windows) {
      credits[window.kind]!.add(window.coverageCredit);
    }
  }
  return [
    group.first.kind.name,
    for (var kind in MatchKind.values)
      credits[kind]!.isEmpty ? "-" : credits[kind]!.average.toStringAsFixed(1),
  ];
}

List<String> _topCompositionRow(List<Competitor> active, String method, int n) {
  var top = active.sorted((a, b) => b.scores[method].compareTo(a.scores[method])).take(n).toList();
  double pct(CompetitorKind kind) =>
      top.where((c) => c.kind == kind).length / max(1, top.length) * 100;
  return [
    method,
    pct(CompetitorKind.traveler).toStringAsFixed(0),
    pct(CompetitorKind.isolatedHigh).toStringAsFixed(0),
    pct(CompetitorKind.localHigh).toStringAsFixed(0),
    pct(CompetitorKind.localLow).toStringAsFixed(0),
  ];
}

void _printKindCounts(List<Match> matchList) {
  print("Match counts by type:");
  for (var kind in MatchKind.values) {
    var group = matchList.where((m) => m.kind == kind).toList();
    if (group.isEmpty) {
      continue;
    }
    print("  ${kind.name.padRight(13)} n=${group.length.toString().padLeft(4)}  "
        "avg size=${group.map((m) => m.competitorIds.length).average.toStringAsFixed(0)}  "
        "avg coverage=${group.map((m) => m.externalCoverage).average.toStringAsFixed(0)}");
  }
}

void _printCorrelationMatrix<T>(List<T> items, ScoreSet Function(T) scoresOf) {
  if (items.length < 3) {
    print("  (not enough items)");
    return;
  }
  _printTable(
    ["", ...methodNames],
    [
      for (var row in methodNames)
        [
          row,
          for (var col in methodNames)
            _spearman(
              items.map((item) => scoresOf(item)[row]).toList(),
              items.map((item) => scoresOf(item)[col]).toList(),
            ).toStringAsFixed(3),
        ],
    ],
  );
}

void _printExamples(List<Competitor> active) {
  Competitor? pick(CompetitorKind kind, bool Function(Competitor) extra) {
    var pool = active.where((c) => c.kind == kind && extra(c)).toList()
      ..sort((a, b) => b.matchIds.length.compareTo(a.matchIds.length));
    if (pool.isEmpty) {
      return null;
    }
    return pool[pool.length ~/ 3];
  }

  var examples = <Competitor>[
    ?pick(CompetitorKind.traveler, (c) => c.regionDiversity >= 3),
    ?pick(CompetitorKind.isolatedHigh, (c) => c.meanFieldSize >= 140),
    ?pick(CompetitorKind.localHigh, (c) => c.regionDiversity <= 2),
    ?pick(CompetitorKind.localLow, (c) => c.matchIds.length >= 4),
  ];

  _printTable(
    ["id", "kind", "matches", "U", "T", "D_eff", "D/U", "Q", "Q share", "reg", "field", ...methodNames],
    [
      for (var c in examples)
        [
          "${c.shooterId}",
          c.kind.name,
          "${c.matchIds.length}",
          "${c.uniqueOpponentCount}",
          "${c.totalOpponentCount}",
          c.effectiveDegree.toStringAsFixed(1),
          (c.uniqueOpponentCount == 0 ? 0 : c.effectiveDegree / c.uniqueOpponentCount).toStringAsFixed(3),
          c.recentCoverageCredit.toStringAsFixed(1),
          c.recentCoverageShare.toStringAsFixed(3),
          "${c.regionDiversity}",
          c.meanFieldSize.toStringAsFixed(0),
          for (var name in methodNames) c.scores[name].toStringAsFixed(1),
        ],
    ],
  );
}

void _printTable(List<String> header, List<List<String>> rows) {
  var cols = header.length;
  var widths = List<int>.generate(cols, (i) {
    var w = header[i].length;
    for (var row in rows) {
      w = max(w, row[i].length);
    }
    return w;
  });
  String fmt(List<String> cells) =>
      [for (var i = 0; i < cols; i++) cells[i].padLeft(widths[i])].join("  ");
  print(fmt(header));
  print([for (var w in widths) "-" * w].join("  "));
  for (var row in rows) {
    print(fmt(row));
  }
}

int _logNormalSize(Random random, {required double median, required double sigma, required int min, required int max}) {
  var u1 = random.nextDouble().clamp(1e-12, 1.0);
  var u2 = random.nextDouble();
  var z = sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  return exp(log(median) + sigma * z).round().clamp(min, max);
}

void _runMetricSelfTests() {
  void expectClose(String name, double actual, double expected) {
    if ((actual - expected).abs() > 1e-9) {
      throw StateError("$name: expected $expected, got $actual");
    }
  }

  expectClose(
    "Effective degree, repeated club",
    _effectiveDegreeFromCounts(List<double>.filled(40, 5)),
    40,
  );
  expectClose(
    "Effective degree, disjoint fields",
    _effectiveDegreeFromCounts(List<double>.filled(200, 1)),
    200,
  );
  expectClose(
    "Effective degree, mixed core",
    _effectiveDegreeFromCounts([
      ...List<double>.filled(20, 5),
      ...List<double>.filled(100, 1),
    ]),
    200 * 200 / 600,
  );

  var coverage = calculateCoverageCredit(
    field: {1, 2, 3, 4},
    neighborhoods: {
      1: {10, 11, 12, 13},
      2: {10, 11, 12, 13},
      3: {10, 11, 12, 13},
      4: {20, 21, 22},
    },
  );
  if (coverage.externalCoverage != 7) {
    throw StateError("Coverage: expected 7, got ${coverage.externalCoverage}");
  }
  expectClose("Local coverage credit", coverage.credits[1]!, 4 / 3);
  expectClose("Traveler coverage credit", coverage.credits[4]!, 3);
  expectClose("Coverage conservation", coverage.credits.values.sum, 7);

  print("Metric self-tests passed.");
}

double _effectiveDegreeFromCounts(Iterable<double> counts) {
  if (counts.isEmpty) {
    return 0;
  }
  var total = counts.sum;
  var sumSquared = counts.map((count) => count * count).sum;
  if (sumSquared == 0) {
    return 0;
  }
  return total * total / sumSquared;
}

double _medianSorted(List<double> sorted) {
  if (sorted.isEmpty) {
    return 0;
  }
  var mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

double _recencyWeightedMean(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  var weightedSum = 0.0;
  var weightSum = 0.0;
  for (var i = 0; i < values.length; i++) {
    var weight = 1.0 + i * 0.2;
    weightedSum += values[i] * weight;
    weightSum += weight;
  }
  return weightedSum / weightSum;
}

double _skewness(List<int> values) {
  if (values.length < 3) {
    return 0.0;
  }
  var mean = values.average;
  var sumSquared = values.map((s) => s * s).sum.toDouble();
  var variance = (sumSquared / values.length) - (mean * mean);
  var stdDev = sqrt(max(0, variance));
  if (stdDev == 0) {
    return 0.0;
  }
  var sumCubed = values.map((s) => s * s * s).sum.toDouble();
  var thirdMoment = (sumCubed / values.length) - (3 * mean * variance) - (mean * mean * mean);
  return thirdMoment / (stdDev * stdDev * stdDev);
}

double _spearman(List<double> a, List<double> b) {
  return _pearson(_ranks(a), _ranks(b));
}

List<double> _ranks(List<double> values) {
  var indexed = [for (var i = 0; i < values.length; i++) (i, values[i])];
  indexed.sort((a, b) => a.$2.compareTo(b.$2));
  var ranks = List<double>.filled(values.length, 0);
  var start = 0;
  while (start < indexed.length) {
    var end = start + 1;
    while (end < indexed.length && indexed[end].$2 == indexed[start].$2) {
      end++;
    }
    var averageRank = (start + end - 1) / 2.0;
    for (var r = start; r < end; r++) {
      ranks[indexed[r].$1] = averageRank;
    }
    start = end;
  }
  return ranks;
}

double _pearson(List<double> x, List<double> y) {
  assert(x.length == y.length);
  if (x.length < 2) {
    return 0;
  }
  var xMean = x.average;
  var yMean = y.average;
  var numerator = 0.0;
  var xDenom = 0.0;
  var yDenom = 0.0;
  for (var i = 0; i < x.length; i++) {
    var xDiff = x[i] - xMean;
    var yDiff = y[i] - yMean;
    numerator += xDiff * yDiff;
    xDenom += xDiff * xDiff;
    yDenom += yDiff * yDiff;
  }
  var denom = sqrt(xDenom * yDenom);
  if (denom == 0) {
    return 0;
  }
  return numerator / denom;
}

String _createHistogram(List<double> values, {
  int buckets = 20,
  int width = 60,
  String entityName = "competitors",
}) {
  if (values.isEmpty) {
    return "No data";
  }
  var minValue = values.min;
  var maxValue = values.max;
  var range = maxValue - minValue;
  if (range == 0) {
    return "All values ${minValue.toStringAsFixed(1)}";
  }
  var bucketSize = range / buckets;
  var counts = List.filled(buckets, 0);
  for (var value in values) {
    var bucketIndex = ((value - minValue) / bucketSize).floor();
    if (bucketIndex == buckets) {
      bucketIndex--;
    }
    counts[bucketIndex]++;
  }
  var maxCount = counts.max;
  var scale = width / maxCount;
  var buffer = StringBuffer();
  for (var i = 0; i < buckets; i++) {
    var bucketMin = minValue + (i * bucketSize);
    var barLength = (counts[i] * scale).round();
    buffer.writeln(
      "${bucketMin.toStringAsFixed(1).padLeft(6)}: "
      "${"█" * barLength}${counts[i].toString().padLeft(4)} "
      "(${(counts[i] / values.length * 100).toStringAsFixed(1)}%)",
    );
  }
  buffer.writeln("Total: ${values.length} $entityName  bucket=${bucketSize.toStringAsFixed(1)}");
  return buffer.toString();
}

extension WindowedList<T> on List<T> {
  List<T> getTailWindow(int window, {int offset = 0}) {
    if (offset + window > length) {
      return this;
    }
    return sublist(length - window - offset, length - offset);
  }
}
