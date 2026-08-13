/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Rank-order correspondence between two rating projects (classic Elo vs LLR).
///
/// For each shared per-division [RatingGroup], matches shooters by
/// [allPossibleMemberNumbers], ranks the intersection by rating, and reports
/// mean/median absolute rank distance, mean absolute percentile distance,
/// Spearman ρ, Kendall τ-a (full and upper-quartile), top-K overlap,
/// top-50 exclusives, and largest movers.
///
/// Filters: min stage history (arg) and lastSeen after Jan 1 of the prior year.

import "dart:math" as math;

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart";

import "base.dart";

const String kDefaultEloProjectName = "L2s Main";
const String kDefaultLlrProjectName = "L2s Main LLR";
const int kDefaultMinHistory = 30;
const List<int> kTopKSizes = [10, 50, 100];
const int kLargestMoversCount = 10;
/// Top fraction of the matched intersection treated as "upper quartile".
const double kUpperQuartileFraction = 0.25;
const int kExclusiveTopK = 50;
const int kExclusiveReportCount = 10;

class RatingProjectCorrespondenceCommand extends DbOneoffCommand {
  RatingProjectCorrespondenceCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "RPC";

  @override
  final String title = "Rating Project Correspondence";

  @override
  String? get description =>
      "Compare rank order between L2s Main (Elo) and L2s Main LLR per division: "
      "rank MAE/median, percentile distance, Spearman ρ, Kendall τ, top-K overlap.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Min history",
          required: false,
          defaultValue: kDefaultMinHistory,
          description:
              "Minimum stage history on both sides (Elo length; LLR lengthInStages). Use 0 for no filter.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final minHistory = arguments
            .firstWhereOrNull((a) => a.argument.label == "Min history")
            ?.getAs<int>() ??
        kDefaultMinHistory;
    await _run(
      db,
      console,
      eloProjectName: kDefaultEloProjectName,
      llrProjectName: kDefaultLlrProjectName,
      minHistory: minHistory,
    );
  }
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String eloProjectName,
  required String llrProjectName,
  required int minHistory,
}) async {
  final eloProject = await db.getRatingProjectByName(eloProjectName);
  if (eloProject == null) {
    console.print("Rating project not found: $eloProjectName");
    return;
  }
  final llrProject = await db.getRatingProjectByName(llrProjectName);
  if (llrProject == null) {
    console.print("Rating project not found: $llrProjectName");
    return;
  }

  if (!eloProject.dbGroups.isLoaded) {
    await eloProject.dbGroups.load();
  }
  if (!llrProject.dbGroups.isLoaded) {
    await llrProject.dbGroups.load();
  }

  final llrAlgorithm = llrProject.settings.algorithm;
  if (llrAlgorithm is! LatentLogRater) {
    console.print(
      "Project $llrProjectName is not a Latent Log project "
      "(needed for calculateAgedRating).",
    );
    return;
  }
  final llrRater = llrAlgorithm;

  final activeSince = DateTime(DateTime.now().year - 1, 1, 1);

  final eloByUuid = {for (final g in eloProject.groups) g.uuid: g};
  final divisionGroups = llrProject.groups
      .where((g) => g.divisionNames.length == 1)
      .sorted((a, b) => a.sortOrder.compareTo(b.sortOrder));

  final buf = StringBuffer()
    ..writeln("=== Rating Project Correspondence ===")
    ..writeln("A (Elo):  $eloProjectName")
    ..writeln("B (LLR):  $llrProjectName")
    ..writeln("Identity: allPossibleMemberNumbers index (normalized)")
    ..writeln(
      "Ranks: within matched intersection, by rating descending "
      "(Elo: rating; LLR: calculateAgedRating)",
    )
    ..writeln(
      "Min history: $minHistory stages "
      "(Elo: length; LLR: lengthInStages; both sides)",
    )
    ..writeln(
      "Active since: ${activeSince.year}-01-01 (lastSeen after Jan 1 of prior year)",
    )
    ..writeln("Groups: per-division only (divisionNames.length == 1)")
    ..writeln(
      "Upper quartile: top ${(kUpperQuartileFraction * 100).round()}% by Elo or LLR "
      "rank (union), re-ranked within cohort",
    )
    ..writeln("")
    ;

  if (divisionGroups.isEmpty) {
    buf.writeln("No per-division groups found on $llrProjectName.");
    console.print(buf.toString());
    return;
  }

  for (final llrGroup in divisionGroups) {
    final eloGroup = eloByUuid[llrGroup.uuid];
    if (eloGroup == null) {
      buf.writeln("--- ${llrGroup.uiLabel} ---");
      buf.writeln("  No matching group uuid on $eloProjectName (${llrGroup.uuid}).");
      buf.writeln("");
      continue;
    }

    final eloRes = eloProject.getRatingsSync(eloGroup);
    final llrRes = llrProject.getRatingsSync(llrGroup);
    if (eloRes.isErr() || llrRes.isErr()) {
      buf.writeln("--- ${llrGroup.uiLabel} ---");
      buf.writeln("  Failed to load ratings.");
      buf.writeln("");
      continue;
    }

    var eloRatings = eloRes.unwrap();
    var llrRatings = llrRes.unwrap();
    final eloTotal = eloRatings.length;
    final llrTotal = llrRatings.length;

    if (minHistory > 0) {
      // Elo (byStage) stores one event per stage in cachedLength.
      // LLR stores one event per match in cachedLength; stages live in lengthInStages.
      eloRatings = eloRatings.where((r) => r.length >= minHistory).toList();
      llrRatings = llrRatings
          .where((r) => LatentLogRating.getLengthInStages(r) >= minHistory)
          .toList();
    }
    eloRatings =
        eloRatings.where((r) => r.lastSeen.isAfter(activeSince)).toList();
    llrRatings =
        llrRatings.where((r) => r.lastSeen.isAfter(activeSince)).toList();

    final pairs = _matchRatings(eloRatings, llrRatings, llrRater);
    final stats = _computeStats(pairs);

    buf.writeln("--- ${llrGroup.uiLabel} ---");
    buf.writeln(
      "  Roster: Elo $eloTotal → ${eloRatings.length} after filter; "
      "LLR $llrTotal → ${llrRatings.length} after filter; "
      "matched ${pairs.length}",
    );

    if (stats == null) {
      buf.writeln("  Too few matched shooters for rank stats (need ≥ 3).");
      buf.writeln("");
      continue;
    }

    buf.writeln(
      "  Rank MAE=${stats.meanAbsRankDiff.toStringAsFixed(2)}  "
      "median=${stats.medianAbsRankDiff.toStringAsFixed(1)}  "
      "pctMAE=${(stats.meanAbsPercentileDiff * 100).toStringAsFixed(2)}%",
    );
    buf.writeln(
      "  Spearman ρ=${stats.spearman.toStringAsFixed(4)}  "
      "Kendall τ=${stats.kendall.toStringAsFixed(4)}",
    );
    if (stats.upperQuartileN >= 3) {
      buf.writeln(
        "  Upper quartile (top ${(kUpperQuartileFraction * 100).round()}% by Elo or LLR rank, "
        "n=${stats.upperQuartileN}):  "
        "Spearman ρ=${stats.upperQuartileSpearman.toStringAsFixed(4)}  "
        "Kendall τ=${stats.upperQuartileKendall.toStringAsFixed(4)}",
      );
      if (stats.upperQuartileLargestMovers.isNotEmpty) {
        buf.writeln(
          "  Upper-quartile largest movers (Elo rank → LLR rank):",
        );
        for (final m in stats.upperQuartileLargestMovers) {
          final sign = m.llrRank < m.eloRank
              ? "↑"
              : (m.llrRank > m.eloRank ? "↓" : "=");
          buf.writeln(
            "    ${m.absDiff.toString().padLeft(4)} $sign  "
            "#${m.eloRank} → #${m.llrRank}  "
            "${m.name}  (${m.memberNumber})",
          );
        }
      }
    }
    else {
      buf.writeln(
        "  Upper quartile: too few shooters for rank stats "
        "(n=${stats.upperQuartileN}, need ≥ 3).",
      );
    }

    final topKParts = <String>[];
    for (final k in kTopKSizes) {
      final overlap = stats.topKOverlap[k];
      if (overlap == null) {
        continue;
      }
      topKParts.add(
        "top$k=${overlap.shared}/$k (${_pct(overlap.shared, k)})",
      );
    }
    if (topKParts.isNotEmpty) {
      buf.writeln("  Top-K overlap: ${topKParts.join("  ")}");
    }

    if (stats.eloOnlyTop50.isNotEmpty || stats.llrOnlyTop50.isNotEmpty) {
      buf.writeln(
        "  Top-$kExclusiveTopK exclusives (best $kExclusiveReportCount each):",
      );
      if (stats.eloOnlyTop50.isEmpty) {
        buf.writeln("    Elo-only: (none)");
      }
      else {
        buf.writeln("    Elo-only (in Elo top $kExclusiveTopK, not LLR):");
        for (final m in stats.eloOnlyTop50) {
          buf.writeln(
            "      Elo #${m.eloRank} / LLR #${m.llrRank}  "
            "${m.name}  (${m.memberNumber})",
          );
        }
      }
      if (stats.llrOnlyTop50.isEmpty) {
        buf.writeln("    LLR-only: (none)");
      }
      else {
        buf.writeln("    LLR-only (in LLR top $kExclusiveTopK, not Elo):");
        for (final m in stats.llrOnlyTop50) {
          buf.writeln(
            "      LLR #${m.llrRank} / Elo #${m.eloRank}  "
            "${m.name}  (${m.memberNumber})",
          );
        }
      }
    }

    buf.writeln("  Largest movers (Elo rank → LLR rank):");
    for (final m in stats.largestMovers) {
      final sign = m.llrRank < m.eloRank ? "↑" : (m.llrRank > m.eloRank ? "↓" : "=");
      buf.writeln(
        "    ${m.absDiff.toString().padLeft(4)} $sign  "
        "#${m.eloRank} → #${m.llrRank}  "
        "${m.name}  (${m.memberNumber})",
      );
    }
    buf.writeln("");
  }

  console.print(buf.toString());
}

/// Match Elo ratings to LLR ratings by normalized allPossibleMemberNumbers.
List<_MatchedPair> _matchRatings(
  List<DbShooterRating> eloRatings,
  List<DbShooterRating> llrRatings,
  LatentLogRater llrRater,
) {
  final index = <String, DbShooterRating>{};
  for (final r in eloRatings) {
    for (final key in _numberKeys(r)) {
      index.putIfAbsent(key, () => r);
    }
  }

  final usedEloIds = <int>{};
  final pairs = <_MatchedPair>[];
  for (final llr in llrRatings) {
    DbShooterRating? elo;
    for (final key in _numberKeys(llr)) {
      final hit = index[key];
      if (hit != null) {
        elo = hit;
        break;
      }
    }
    if (elo == null) {
      continue;
    }
    if (usedEloIds.contains(elo.id)) {
      continue;
    }
    usedEloIds.add(elo.id);
    final wrapped = LatentLogRating.wrapDbRatingWithSettings(llrRater, llr);
    pairs.add(
      _MatchedPair(
        elo: elo,
        llr: llr,
        llrSortRating: wrapped.calculateAgedRating(),
      ),
    );
  }
  return pairs;
}

Iterable<String> _numberKeys(DbShooterRating rating) sync* {
  final seen = <String>{};
  for (final raw in [
    rating.memberNumber,
    ...rating.knownMemberNumbers,
    ...rating.allPossibleMemberNumbers,
  ]) {
    final t = raw.trim();
    if (t.isEmpty || t == "(invalid)") {
      continue;
    }
    final key = ShooterDeduplicator.normalizeNumberBasic(t);
    if (key.isEmpty || !seen.add(key)) {
      continue;
    }
    yield key;
  }
}

_GroupStats? _computeStats(List<_MatchedPair> pairs) {
  final n = pairs.length;
  if (n < 3) {
    return null;
  }

  final eloSorted = [...pairs]..sort((a, b) => b.elo.rating.compareTo(a.elo.rating));
  final llrSorted = [...pairs]..sort((a, b) => b.llrSortRating.compareTo(a.llrSortRating));

  // Competition ranks from each side's rating order (1 = best).
  final eloRankByPair = <_MatchedPair, int>{};
  final llrRankByPair = <_MatchedPair, int>{};
  for (var i = 0; i < n; i++) {
    eloRankByPair[eloSorted[i]] = i + 1;
    llrRankByPair[llrSorted[i]] = i + 1;
  }

  final absDiffs = <double>[];
  final absPctDiffs = <double>[];
  final eloRanks = <double>[];
  final llrRanks = <double>[];
  final movers = <_Mover>[];

  for (final pair in pairs) {
    final ra = eloRankByPair[pair]!;
    final rb = llrRankByPair[pair]!;
    final abs = (ra - rb).abs().toDouble();
    absDiffs.add(abs);
    absPctDiffs.add(abs / n);
    eloRanks.add(ra.toDouble());
    llrRanks.add(rb.toDouble());
    movers.add(
      _Mover(
        name: pair.elo.name,
        memberNumber: pair.elo.memberNumber,
        eloRank: ra,
        llrRank: rb,
        absDiff: (ra - rb).abs(),
      ),
    );
  }

  absDiffs.sort();
  movers.sort((a, b) {
    final byDiff = b.absDiff.compareTo(a.absDiff);
    if (byDiff != 0) {
      return byDiff;
    }
    return a.eloRank.compareTo(b.eloRank);
  });

  final topKOverlap = <int, ({int shared})>{};
  for (final k in kTopKSizes) {
    if (n < k) {
      continue;
    }
    final eloTop = eloSorted.take(k).toSet();
    final llrTop = llrSorted.take(k).toSet();
    topKOverlap[k] = (shared: eloTop.intersection(llrTop).length);
  }

  // Upper quartile: anyone either system ranks in the top 25%, then
  // re-rank within that cohort so ρ/τ measure elite relative order.
  final qCount = math.max(1, (n * kUpperQuartileFraction).ceil());
  final upperCohort = pairs
      .where(
        (p) =>
            eloRankByPair[p]! <= qCount || llrRankByPair[p]! <= qCount,
      )
      .toList();
  var upperSpearman = double.nan;
  var upperKendall = double.nan;
  if (upperCohort.length >= 3) {
    final eloUpperSorted = [...upperCohort]
      ..sort((a, b) => b.elo.rating.compareTo(a.elo.rating));
    final llrUpperSorted = [...upperCohort]
      ..sort((a, b) => b.llrSortRating.compareTo(a.llrSortRating));
    final eloLocalRank = <_MatchedPair, int>{};
    final llrLocalRank = <_MatchedPair, int>{};
    for (var i = 0; i < upperCohort.length; i++) {
      eloLocalRank[eloUpperSorted[i]] = i + 1;
      llrLocalRank[llrUpperSorted[i]] = i + 1;
    }
    final eloLocal = <double>[];
    final llrLocal = <double>[];
    for (final p in upperCohort) {
      eloLocal.add(eloLocalRank[p]!.toDouble());
      llrLocal.add(llrLocalRank[p]!.toDouble());
    }
    upperSpearman = _spearman(eloLocal, llrLocal);
    upperKendall = _kendallTauA(eloLocal, llrLocal);
  }

  final upperMovers = upperCohort.map((p) {
    final ra = eloRankByPair[p]!;
    final rb = llrRankByPair[p]!;
    return _Mover(
      name: p.elo.name,
      memberNumber: p.elo.memberNumber,
      eloRank: ra,
      llrRank: rb,
      absDiff: (ra - rb).abs(),
    );
  }).toList()
    ..sort((a, b) {
      final byDiff = b.absDiff.compareTo(a.absDiff);
      if (byDiff != 0) {
        return byDiff;
      }
      return a.eloRank.compareTo(b.eloRank);
    });

  // Best exclusives within top-50 of each system.
  final exclusiveK = math.min(kExclusiveTopK, n);
  final eloTopSet = eloSorted.take(exclusiveK).toSet();
  final llrTopSet = llrSorted.take(exclusiveK).toSet();
  final eloOnly = eloTopSet.difference(llrTopSet).map((p) {
    return _Mover(
      name: p.elo.name,
      memberNumber: p.elo.memberNumber,
      eloRank: eloRankByPair[p]!,
      llrRank: llrRankByPair[p]!,
      absDiff: (eloRankByPair[p]! - llrRankByPair[p]!).abs(),
    );
  }).toList()
    ..sort((a, b) => a.eloRank.compareTo(b.eloRank));
  final llrOnly = llrTopSet.difference(eloTopSet).map((p) {
    return _Mover(
      name: p.elo.name,
      memberNumber: p.elo.memberNumber,
      eloRank: eloRankByPair[p]!,
      llrRank: llrRankByPair[p]!,
      absDiff: (eloRankByPair[p]! - llrRankByPair[p]!).abs(),
    );
  }).toList()
    ..sort((a, b) => a.llrRank.compareTo(b.llrRank));

  return _GroupStats(
    n: n,
    meanAbsRankDiff: absDiffs.average,
    medianAbsRankDiff: _median(absDiffs),
    meanAbsPercentileDiff: absPctDiffs.average,
    spearman: _spearman(eloRanks, llrRanks),
    kendall: _kendallTauA(eloRanks, llrRanks),
    upperQuartileN: upperCohort.length,
    upperQuartileSpearman: upperSpearman,
    upperQuartileKendall: upperKendall,
    upperQuartileLargestMovers: upperMovers
        .take(math.min(kLargestMoversCount, upperMovers.length))
        .toList(),
    topKOverlap: topKOverlap,
    eloOnlyTop50: eloOnly.take(math.min(kExclusiveReportCount, eloOnly.length)).toList(),
    llrOnlyTop50: llrOnly.take(math.min(kExclusiveReportCount, llrOnly.length)).toList(),
    largestMovers: movers.take(math.min(kLargestMoversCount, movers.length)).toList(),
  );
}

double _median(List<double> sorted) {
  if (sorted.isEmpty) {
    return double.nan;
  }
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

/// Spearman ρ via Pearson of midranks (ascending value → rank 1).
double _spearman(List<double> x, List<double> y) {
  if (x.length != y.length || x.length < 3) {
    return double.nan;
  }
  return _pearson(_midranks(x), _midranks(y));
}

List<double> _midranks(List<double> values) {
  final indexed = values.indexed.toList()..sort((a, b) => a.$2.compareTo(b.$2));
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
  return num / math.sqrt(dx * dy);
}

/// Kendall τ-a: (C − D) / (n choose 2). Ties counted as neither C nor D.
double _kendallTauA(List<double> x, List<double> y) {
  final n = x.length;
  if (n < 2) {
    return double.nan;
  }
  var concordant = 0;
  var discordant = 0;
  for (var i = 0; i < n - 1; i++) {
    for (var j = i + 1; j < n; j++) {
      final dx = x[i] - x[j];
      final dy = y[i] - y[j];
      if (dx == 0 || dy == 0) {
        continue;
      }
      if (dx.sign == dy.sign) {
        concordant++;
      }
      else {
        discordant++;
      }
    }
  }
  final denom = n * (n - 1) / 2.0;
  if (denom == 0) {
    return double.nan;
  }
  return (concordant - discordant) / denom;
}

String _pct(int numerator, int denominator) {
  if (denominator == 0) {
    return "n/a";
  }
  return "${(100.0 * numerator / denominator).toStringAsFixed(1)}%";
}

class _MatchedPair {
  final DbShooterRating elo;
  final DbShooterRating llr;
  /// LLR sort key from [LatentLogRating.calculateAgedRating] (today).
  final double llrSortRating;

  _MatchedPair({
    required this.elo,
    required this.llr,
    required this.llrSortRating,
  });
}

class _Mover {
  final String name;
  final String memberNumber;
  final int eloRank;
  final int llrRank;
  final int absDiff;

  _Mover({
    required this.name,
    required this.memberNumber,
    required this.eloRank,
    required this.llrRank,
    required this.absDiff,
  });
}

class _GroupStats {
  final int n;
  final double meanAbsRankDiff;
  final double medianAbsRankDiff;
  final double meanAbsPercentileDiff;
  final double spearman;
  final double kendall;
  final int upperQuartileN;
  final double upperQuartileSpearman;
  final double upperQuartileKendall;
  final List<_Mover> upperQuartileLargestMovers;
  final Map<int, ({int shared})> topKOverlap;
  final List<_Mover> eloOnlyTop50;
  final List<_Mover> llrOnlyTop50;
  final List<_Mover> largestMovers;

  _GroupStats({
    required this.n,
    required this.meanAbsRankDiff,
    required this.medianAbsRankDiff,
    required this.meanAbsPercentileDiff,
    required this.spearman,
    required this.kendall,
    required this.upperQuartileN,
    required this.upperQuartileSpearman,
    required this.upperQuartileKendall,
    required this.upperQuartileLargestMovers,
    required this.topKOverlap,
    required this.eloOnlyTop50,
    required this.llrOnlyTop50,
    required this.largestMovers,
  });
}
