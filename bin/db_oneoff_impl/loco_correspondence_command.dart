/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Rank-order correspondence between per-division LO/CO ratings and combined LOCO.
///
/// Within [L2s Main LLR], matches shooters by normalized allPossibleMemberNumbers
/// and ranks the intersection (same people vs each other — not the full LOCO
/// published list). Reports the same correspondence metrics as RPC, plus mean
/// absolute aged-rating gap (same LLR scale). Also reports LO vs CO duals.
///
/// Combined-pool fairness (does LOCO penalize LO or CO?):
/// - Signed (LOCO − single-div) aged-rating shifts, overall / dual / single-only
/// - LOCO top-K composition by affiliation vs pool base rates
/// - Counterfactual invites: top N LOCO vs top N/2 LO + top N/2 CO
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

const String kDefaultLlrProjectName = "L2s Main LLR";
const String kLoGroupUuid = "uspsa-limited-optics";
const String kCoGroupUuid = "uspsa-carryoptics";
const String kLoCoGroupUuid = "uspsa-lo-co";
const int kDefaultMinHistory = 30;
const int kDefaultInviteN = 324;
const List<int> kTopKSizes = [10, 50, 100];
const List<int> kCompositionTopKSizes = [50, 100, 324];
const int kLargestMoversCount = 10;
const double kUpperQuartileFraction = 0.25;
const int kExclusiveTopK = 50;
const int kExclusiveReportCount = 10;
const int kCounterfactualSampleCount = 10;

class LocoCorrespondenceCommand extends DbOneoffCommand {
  LocoCorrespondenceCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "LCC";

  @override
  final String title = "LO/CO vs LOCO Correspondence";

  @override
  String? get description =>
      "LO/CO vs LOCO rank correspondence, signed level shifts, top-K affiliation, "
      "and counterfactual combined vs split invites.";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Min history",
          required: false,
          defaultValue: kDefaultMinHistory,
          description:
              "Minimum LLR lengthInStages on both sides. Use 0 for no filter.",
        ),
        IntMenuArgument(
          label: "Invite N",
          required: false,
          defaultValue: kDefaultInviteN,
          description:
              "Counterfactual pool size: top N from LOCO vs top N/2 LO + top N/2 CO.",
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final minHistory = arguments
            .firstWhereOrNull((a) => a.argument.label == "Min history")
            ?.getAs<int>() ??
        kDefaultMinHistory;
    final inviteN = arguments
            .firstWhereOrNull((a) => a.argument.label == "Invite N")
            ?.getAs<int>() ??
        kDefaultInviteN;
    await _run(
      db,
      console,
      projectName: kDefaultLlrProjectName,
      minHistory: minHistory,
      inviteN: inviteN,
    );
  }
}

Future<void> _run(
  AnalystDatabase db,
  Console console, {
  required String projectName,
  required int minHistory,
  required int inviteN,
}) async {
  final project = await db.getRatingProjectByName(projectName);
  if (project == null) {
    console.print("Rating project not found: $projectName");
    return;
  }
  if (!project.dbGroups.isLoaded) {
    await project.dbGroups.load();
  }

  final algorithm = project.settings.algorithm;
  if (algorithm is! LatentLogRater) {
    console.print(
      "Project $projectName is not a Latent Log project "
      "(needed for calculateAgedRating / lengthInStages).",
    );
    return;
  }
  final rater = algorithm;

  RatingGroup? groupByUuid(String uuid) =>
      project.groups.firstWhereOrNull((g) => g.uuid == uuid);

  final loGroup = groupByUuid(kLoGroupUuid);
  final coGroup = groupByUuid(kCoGroupUuid);
  final locoGroup = groupByUuid(kLoCoGroupUuid);
  if (loGroup == null || coGroup == null || locoGroup == null) {
    console.print(
      "Missing groups on $projectName "
      "(need $kLoGroupUuid, $kCoGroupUuid, $kLoCoGroupUuid).",
    );
    return;
  }

  final activeSince = DateTime(DateTime.now().year - 1, 1, 1);

  List<DbShooterRating>? loadFiltered(RatingGroup group) {
    final res = project.getRatingsSync(group);
    if (res.isErr()) {
      return null;
    }
    var ratings = res.unwrap();
    if (minHistory > 0) {
      ratings = ratings
          .where((r) => LatentLogRating.getLengthInStages(r) >= minHistory)
          .toList();
    }
    return ratings.where((r) => r.lastSeen.isAfter(activeSince)).toList();
  }

  final loRatings = loadFiltered(loGroup);
  final coRatings = loadFiltered(coGroup);
  final locoRatings = loadFiltered(locoGroup);
  if (loRatings == null || coRatings == null || locoRatings == null) {
    console.print("Failed to load ratings for LO, CO, or LOCO.");
    return;
  }

  final loRes = project.getRatingsSync(loGroup);
  final coRes = project.getRatingsSync(coGroup);
  final locoRes = project.getRatingsSync(locoGroup);
  final loTotal = loRes.isOk() ? loRes.unwrap().length : 0;
  final coTotal = coRes.isOk() ? coRes.unwrap().length : 0;
  final locoTotal = locoRes.isOk() ? locoRes.unwrap().length : 0;

  final loKeys = _keySet(loRatings);
  final coKeys = _keySet(coRatings);
  final idIndex = _PersonIdIndex();
  // Seed IDs from all three rosters so duals share a person id across groups.
  for (final r in [...loRatings, ...coRatings, ...locoRatings]) {
    idIndex.idFor(r);
  }

  final buf = StringBuffer()
    ..writeln("=== LO/CO vs LOCO Correspondence ===")
    ..writeln("Project: $projectName")
    ..writeln("Identity: allPossibleMemberNumbers index (normalized)")
    ..writeln(
      "Ranks: within matched intersection, by calculateAgedRating descending "
      "(same people vs each other; CO-only names excluded from LO↔LOCO ranks)",
    )
    ..writeln(
      "Min history: $minHistory stages (LLR lengthInStages, both sides)",
    )
    ..writeln(
      "Active since: ${activeSince.year}-01-01 (lastSeen after Jan 1 of prior year)",
    )
    ..writeln(
      "Upper quartile: top ${(kUpperQuartileFraction * 100).round()}% by A or B "
      "rank (union), re-ranked within cohort",
    )
    ..writeln(
      "Rosters after filter: LO ${loRatings.length}/$loTotal  "
      "CO ${coRatings.length}/$coTotal  "
      "LOCO ${locoRatings.length}/$locoTotal",
    )
    ..writeln("Invite N (counterfactual): $inviteN")
    ..writeln("");

  _writeComparison(
    buf,
    title: "LO vs LOCO",
    labelA: "LO",
    labelB: "LOCO",
    ratingsA: loRatings,
    ratingsB: locoRatings,
    rater: rater,
  );
  _writeComparison(
    buf,
    title: "CO vs LOCO",
    labelA: "CO",
    labelB: "LOCO",
    ratingsA: coRatings,
    ratingsB: locoRatings,
    rater: rater,
  );
  _writeComparison(
    buf,
    title: "LO vs CO (dual-division shooters)",
    labelA: "LO",
    labelB: "CO",
    ratingsA: loRatings,
    ratingsB: coRatings,
    rater: rater,
  );

  _writeCombinedPoolFairness(
    buf,
    loRatings: loRatings,
    coRatings: coRatings,
    locoRatings: locoRatings,
    loKeys: loKeys,
    coKeys: coKeys,
    rater: rater,
    idIndex: idIndex,
    inviteN: inviteN,
  );

  console.print(buf.toString());
}

void _writeCombinedPoolFairness(
  StringBuffer buf, {
  required List<DbShooterRating> loRatings,
  required List<DbShooterRating> coRatings,
  required List<DbShooterRating> locoRatings,
  required Set<String> loKeys,
  required Set<String> coKeys,
  required LatentLogRater rater,
  required _PersonIdIndex idIndex,
  required int inviteN,
}) {
  buf.writeln("=== Combined-pool fairness (does LOCO penalize LO or CO?) ===");
  buf.writeln(
    "Affiliation: LO-only / CO-only / dual = present in filtered LO and/or CO rosters.",
  );
  buf.writeln(
    "Signed shift: LOCO agedRating − single-division agedRating "
    "(negative = lower on LOCO than on the single-div list).",
  );
  buf.writeln("");

  final loLocoPairs = _matchRatings(loRatings, locoRatings, rater);
  final coLocoPairs = _matchRatings(coRatings, locoRatings, rater);

  _writeSignedShifts(
    buf,
    title: "Signed level shift: LO → LOCO",
    singleLabel: "LO",
    pairs: loLocoPairs,
    otherKeys: coKeys,
    dualLabel: "dual (also in CO)",
    singleOnlyLabel: "LO-only",
  );
  _writeSignedShifts(
    buf,
    title: "Signed level shift: CO → LOCO",
    singleLabel: "CO",
    pairs: coLocoPairs,
    otherKeys: loKeys,
    dualLabel: "dual (also in LO)",
    singleOnlyLabel: "CO-only",
  );

  final locoSorted = [
    for (final r in locoRatings)
      _RankedPerson(
        rating: r,
        personId: idIndex.idFor(r),
        sortRating: _agedRating(rater, r),
        affiliation: _affiliation(r, loKeys, coKeys),
      ),
  ]..sort((a, b) => b.sortRating.compareTo(a.sortRating));

  final poolCounts = _countAffiliations(locoSorted.map((p) => p.affiliation));
  buf.writeln("--- LOCO pool base rates (filtered) ---");
  buf.writeln(
    "  n=${locoSorted.length}  "
    "LO-only=${poolCounts.loOnly} (${_pct(poolCounts.loOnly, locoSorted.length)})  "
    "CO-only=${poolCounts.coOnly} (${_pct(poolCounts.coOnly, locoSorted.length)})  "
    "dual=${poolCounts.dual} (${_pct(poolCounts.dual, locoSorted.length)})  "
    "neither=${poolCounts.neither} (${_pct(poolCounts.neither, locoSorted.length)})",
  );
  buf.writeln("");

  buf.writeln("--- LOCO top-K composition vs pool base rates ---");
  final compositionKs = {
    ...kCompositionTopKSizes,
    if (inviteN > 0) inviteN,
  }.toList()
    ..sort();
  for (final k in compositionKs) {
    if (locoSorted.length < k) {
      continue;
    }
    final top = locoSorted.take(k).toList();
    final c = _countAffiliations(top.map((p) => p.affiliation));
    buf.writeln(
      "  Top $k: "
      "LO-only=${c.loOnly} (${_pct(c.loOnly, k)}; pool ${_pct(poolCounts.loOnly, locoSorted.length)})  "
      "CO-only=${c.coOnly} (${_pct(c.coOnly, k)}; pool ${_pct(poolCounts.coOnly, locoSorted.length)})  "
      "dual=${c.dual} (${_pct(c.dual, k)}; pool ${_pct(poolCounts.dual, locoSorted.length)})",
    );
  }
  buf.writeln(
    "  (Over/under vs pool: LO-only or CO-only share in top-K vs share in full LOCO pool.)",
  );
  buf.writeln("");

  _writeCounterfactualInvites(
    buf,
    loRatings: loRatings,
    coRatings: coRatings,
    locoSorted: locoSorted,
    loKeys: loKeys,
    coKeys: coKeys,
    rater: rater,
    idIndex: idIndex,
    inviteN: inviteN,
  );
}

void _writeSignedShifts(
  StringBuffer buf, {
  required String title,
  required String singleLabel,
  required List<_MatchedPair> pairs,
  required Set<String> otherKeys,
  required String dualLabel,
  required String singleOnlyLabel,
}) {
  buf.writeln("--- $title ---");
  if (pairs.isEmpty) {
    buf.writeln("  No matched pairs.");
    buf.writeln("");
    return;
  }

  final allDeltas = <double>[];
  final dualDeltas = <double>[];
  final singleOnlyDeltas = <double>[];
  for (final p in pairs) {
    final delta = p.sortB - p.sortA;
    allDeltas.add(delta);
    if (_keysOverlap(p.ratingA, otherKeys)) {
      dualDeltas.add(delta);
    }
    else {
      singleOnlyDeltas.add(delta);
    }
  }

  void line(String label, List<double> deltas) {
    if (deltas.isEmpty) {
      buf.writeln("  $label: n=0");
      return;
    }
    final sorted = [...deltas]..sort();
    buf.writeln(
      "  $label: n=${deltas.length}  "
      "mean=${deltas.average.toStringAsFixed(4)}  "
      "median=${_median(sorted).toStringAsFixed(4)}  "
      "pctDown=${_pct(deltas.where((d) => d < 0).length, deltas.length)}  "
      "pctUp=${_pct(deltas.where((d) => d > 0).length, deltas.length)}",
    );
  }

  line("All $singleLabel∩LOCO", allDeltas);
  line(dualLabel, dualDeltas);
  line(singleOnlyLabel, singleOnlyDeltas);
  buf.writeln("");
}

void _writeCounterfactualInvites(
  StringBuffer buf, {
  required List<DbShooterRating> loRatings,
  required List<DbShooterRating> coRatings,
  required List<_RankedPerson> locoSorted,
  required Set<String> loKeys,
  required Set<String> coKeys,
  required LatentLogRater rater,
  required _PersonIdIndex idIndex,
  required int inviteN,
}) {
  buf.writeln("--- Counterfactual invites: top $inviteN LOCO vs split ---");
  if (inviteN <= 0) {
    buf.writeln("  Invite N must be positive.");
    buf.writeln("");
    return;
  }

  final half = inviteN ~/ 2;
  if (locoSorted.length < inviteN || loRatings.length < half || coRatings.length < half) {
    buf.writeln(
      "  Not enough roster depth "
      "(need LOCO≥$inviteN, LO≥$half, CO≥$half).",
    );
    buf.writeln("");
    return;
  }

  final loSorted = [
    for (final r in loRatings)
      _RankedPerson(
        rating: r,
        personId: idIndex.idFor(r),
        sortRating: _agedRating(rater, r),
        affiliation: _Affiliation.loOnly, // unused for set ops
      ),
  ]..sort((a, b) => b.sortRating.compareTo(a.sortRating));
  final coSorted = [
    for (final r in coRatings)
      _RankedPerson(
        rating: r,
        personId: idIndex.idFor(r),
        sortRating: _agedRating(rater, r),
        affiliation: _Affiliation.coOnly,
      ),
  ]..sort((a, b) => b.sortRating.compareTo(a.sortRating));

  final locoTop = locoSorted.take(inviteN).toList();
  final locoIds = locoTop.map((p) => p.personId).toSet();
  final splitLo = loSorted.take(half).toList();
  final splitCo = coSorted.take(half).toList();
  final splitIds = {...splitLo.map((p) => p.personId), ...splitCo.map((p) => p.personId)};
  final dualInSplit = splitLo.map((p) => p.personId).toSet().intersection(
        splitCo.map((p) => p.personId).toSet(),
      );

  final shared = locoIds.intersection(splitIds);
  final locoOnlyIds = locoIds.difference(splitIds);
  final splitOnlyIds = splitIds.difference(locoIds);

  final locoOnlyPeople = locoTop.where((p) => locoOnlyIds.contains(p.personId)).toList();
  final splitOnlyLo = splitLo.where((p) => splitOnlyIds.contains(p.personId)).toList();
  final splitOnlyCo = splitCo.where((p) => splitOnlyIds.contains(p.personId)).toList();

  final locoOnlyAff = _countAffiliations(locoOnlyPeople.map((p) => p.affiliation));

  buf.writeln(
    "  Split construction: top $half LO ∪ top $half CO "
    "(union size=${splitIds.length}; duals in both tops=${dualInSplit.length})",
  );
  buf.writeln(
    "  Overlap with LOCO top $inviteN: shared=${shared.length}  "
    "Jaccard=${_pct(shared.length, locoIds.union(splitIds).length)}  "
    "LOCO-only=${locoOnlyIds.length}  split-only=${splitOnlyIds.length}",
  );
  buf.writeln(
    "  LOCO-only (invited by LOCO, not by split): "
    "LO-only=${locoOnlyAff.loOnly}  CO-only=${locoOnlyAff.coOnly}  "
    "dual=${locoOnlyAff.dual}  neither=${locoOnlyAff.neither}",
  );
  buf.writeln(
    "  Split-only (invited by split, not by LOCO): "
    "from LO top=$half → ${splitOnlyLo.length} unique; "
    "from CO top=$half → ${splitOnlyCo.length} unique",
  );

  if (locoOnlyPeople.isNotEmpty) {
    buf.writeln("  Sample LOCO-only (best $kCounterfactualSampleCount by LOCO):");
    for (final p in locoOnlyPeople.take(kCounterfactualSampleCount)) {
      buf.writeln(
        "    #${locoSorted.indexOf(p) + 1}  ${p.affiliation.label}  "
        "${p.rating.name}  (${p.rating.memberNumber})  "
        "LOCO=${p.sortRating.toStringAsFixed(3)}",
      );
    }
  }
  if (splitOnlyLo.isNotEmpty || splitOnlyCo.isNotEmpty) {
    buf.writeln("  Sample split-only:");
    for (final p in splitOnlyLo.take(kCounterfactualSampleCount ~/ 2)) {
      buf.writeln(
        "    LO list  ${p.rating.name}  (${p.rating.memberNumber})  "
        "LO=${p.sortRating.toStringAsFixed(3)}",
      );
    }
    for (final p in splitOnlyCo.take(kCounterfactualSampleCount ~/ 2)) {
      buf.writeln(
        "    CO list  ${p.rating.name}  (${p.rating.memberNumber})  "
        "CO=${p.sortRating.toStringAsFixed(3)}",
      );
    }
  }
  buf.writeln("");
}

void _writeComparison(
  StringBuffer buf, {
  required String title,
  required String labelA,
  required String labelB,
  required List<DbShooterRating> ratingsA,
  required List<DbShooterRating> ratingsB,
  required LatentLogRater rater,
}) {
  final pairs = _matchRatings(ratingsA, ratingsB, rater);
  final stats = _computeStats(pairs);

  buf.writeln("--- $title ---");
  buf.writeln(
    "  Roster: $labelA ${ratingsA.length}; $labelB ${ratingsB.length}; "
    "matched ${pairs.length}",
  );

  if (stats == null) {
    buf.writeln("  Too few matched shooters for rank stats (need ≥ 3).");
    buf.writeln("");
    return;
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
  buf.writeln(
    "  |Δ aged rating| mean=${stats.meanAbsRatingDiff.toStringAsFixed(4)}  "
    "median=${stats.medianAbsRatingDiff.toStringAsFixed(4)}",
  );

  if (stats.upperQuartileN >= 3) {
    buf.writeln(
      "  Upper quartile (top ${(kUpperQuartileFraction * 100).round()}% by $labelA or $labelB rank, "
      "n=${stats.upperQuartileN}):  "
      "Spearman ρ=${stats.upperQuartileSpearman.toStringAsFixed(4)}  "
      "Kendall τ=${stats.upperQuartileKendall.toStringAsFixed(4)}",
    );
    if (stats.upperQuartileLargestMovers.isNotEmpty) {
      buf.writeln(
        "  Upper-quartile largest movers ($labelA rank → $labelB rank):",
      );
      for (final m in stats.upperQuartileLargestMovers) {
        buf.writeln(_moverLine(m));
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
    topKParts.add("top$k=${overlap.shared}/$k (${_pct(overlap.shared, k)})");
  }
  if (topKParts.isNotEmpty) {
    buf.writeln("  Top-K overlap: ${topKParts.join("  ")}");
  }

  if (stats.aOnlyTop50.isNotEmpty || stats.bOnlyTop50.isNotEmpty) {
    buf.writeln(
      "  Top-$kExclusiveTopK exclusives (best $kExclusiveReportCount each):",
    );
    if (stats.aOnlyTop50.isEmpty) {
      buf.writeln("    $labelA-only: (none)");
    }
    else {
      buf.writeln("    $labelA-only (in $labelA top $kExclusiveTopK, not $labelB):");
      for (final m in stats.aOnlyTop50) {
        buf.writeln(
          "      $labelA #${m.rankA} / $labelB #${m.rankB}  "
          "${m.name}  (${m.memberNumber})",
        );
      }
    }
    if (stats.bOnlyTop50.isEmpty) {
      buf.writeln("    $labelB-only: (none)");
    }
    else {
      buf.writeln("    $labelB-only (in $labelB top $kExclusiveTopK, not $labelA):");
      for (final m in stats.bOnlyTop50) {
        buf.writeln(
          "      $labelB #${m.rankB} / $labelA #${m.rankA}  "
          "${m.name}  (${m.memberNumber})",
        );
      }
    }
  }

  buf.writeln("  Largest movers ($labelA rank → $labelB rank):");
  for (final m in stats.largestMovers) {
    buf.writeln(_moverLine(m));
  }
  buf.writeln("");
}

String _moverLine(_Mover m) {
  final sign = m.rankB < m.rankA ? "↑" : (m.rankB > m.rankA ? "↓" : "=");
  return "    ${m.absDiff.toString().padLeft(4)} $sign  "
      "#${m.rankA} → #${m.rankB}  "
      "${m.name}  (${m.memberNumber})";
}

Set<String> _keySet(List<DbShooterRating> ratings) {
  final keys = <String>{};
  for (final r in ratings) {
    keys.addAll(_numberKeys(r));
  }
  return keys;
}

bool _keysOverlap(DbShooterRating rating, Set<String> keys) {
  for (final k in _numberKeys(rating)) {
    if (keys.contains(k)) {
      return true;
    }
  }
  return false;
}

_Affiliation _affiliation(
  DbShooterRating rating,
  Set<String> loKeys,
  Set<String> coKeys,
) {
  final inLo = _keysOverlap(rating, loKeys);
  final inCo = _keysOverlap(rating, coKeys);
  if (inLo && inCo) {
    return _Affiliation.dual;
  }
  if (inLo) {
    return _Affiliation.loOnly;
  }
  if (inCo) {
    return _Affiliation.coOnly;
  }
  return _Affiliation.neither;
}

_AffiliationCounts _countAffiliations(Iterable<_Affiliation> values) {
  var loOnly = 0;
  var coOnly = 0;
  var dual = 0;
  var neither = 0;
  for (final a in values) {
    switch (a) {
      case _Affiliation.loOnly:
        loOnly++;
      case _Affiliation.coOnly:
        coOnly++;
      case _Affiliation.dual:
        dual++;
      case _Affiliation.neither:
        neither++;
    }
  }
  return _AffiliationCounts(
    loOnly: loOnly,
    coOnly: coOnly,
    dual: dual,
    neither: neither,
  );
}

List<_MatchedPair> _matchRatings(
  List<DbShooterRating> ratingsA,
  List<DbShooterRating> ratingsB,
  LatentLogRater rater,
) {
  final index = <String, DbShooterRating>{};
  for (final r in ratingsA) {
    for (final key in _numberKeys(r)) {
      index.putIfAbsent(key, () => r);
    }
  }

  final usedAIds = <int>{};
  final pairs = <_MatchedPair>[];
  for (final b in ratingsB) {
    DbShooterRating? a;
    for (final key in _numberKeys(b)) {
      final hit = index[key];
      if (hit != null) {
        a = hit;
        break;
      }
    }
    if (a == null || !usedAIds.add(a.id)) {
      continue;
    }
    pairs.add(
      _MatchedPair(
        ratingA: a,
        ratingB: b,
        sortA: _agedRating(rater, a),
        sortB: _agedRating(rater, b),
      ),
    );
  }
  return pairs;
}

double _agedRating(LatentLogRater rater, DbShooterRating rating) {
  return LatentLogRating.wrapDbRatingWithSettings(rater, rating).calculateAgedRating();
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

  final aSorted = [...pairs]..sort((a, b) => b.sortA.compareTo(a.sortA));
  final bSorted = [...pairs]..sort((a, b) => b.sortB.compareTo(a.sortB));

  final rankAByPair = <_MatchedPair, int>{};
  final rankBByPair = <_MatchedPair, int>{};
  for (var i = 0; i < n; i++) {
    rankAByPair[aSorted[i]] = i + 1;
    rankBByPair[bSorted[i]] = i + 1;
  }

  final absDiffs = <double>[];
  final absPctDiffs = <double>[];
  final absRatingDiffs = <double>[];
  final ranksA = <double>[];
  final ranksB = <double>[];
  final movers = <_Mover>[];

  for (final pair in pairs) {
    final ra = rankAByPair[pair]!;
    final rb = rankBByPair[pair]!;
    final abs = (ra - rb).abs().toDouble();
    absDiffs.add(abs);
    absPctDiffs.add(abs / n);
    absRatingDiffs.add((pair.sortA - pair.sortB).abs());
    ranksA.add(ra.toDouble());
    ranksB.add(rb.toDouble());
    movers.add(
      _Mover(
        name: pair.ratingA.name,
        memberNumber: pair.ratingA.memberNumber,
        rankA: ra,
        rankB: rb,
        absDiff: (ra - rb).abs(),
      ),
    );
  }

  absDiffs.sort();
  absRatingDiffs.sort();
  movers.sort((a, b) {
    final byDiff = b.absDiff.compareTo(a.absDiff);
    if (byDiff != 0) {
      return byDiff;
    }
    return a.rankA.compareTo(b.rankA);
  });

  final topKOverlap = <int, ({int shared})>{};
  for (final k in kTopKSizes) {
    if (n < k) {
      continue;
    }
    final aTop = aSorted.take(k).toSet();
    final bTop = bSorted.take(k).toSet();
    topKOverlap[k] = (shared: aTop.intersection(bTop).length);
  }

  final qCount = math.max(1, (n * kUpperQuartileFraction).ceil());
  final upperCohort = pairs
      .where((p) => rankAByPair[p]! <= qCount || rankBByPair[p]! <= qCount)
      .toList();
  var upperSpearman = double.nan;
  var upperKendall = double.nan;
  if (upperCohort.length >= 3) {
    final aUpperSorted = [...upperCohort]..sort((a, b) => b.sortA.compareTo(a.sortA));
    final bUpperSorted = [...upperCohort]..sort((a, b) => b.sortB.compareTo(a.sortB));
    final aLocalRank = <_MatchedPair, int>{};
    final bLocalRank = <_MatchedPair, int>{};
    for (var i = 0; i < upperCohort.length; i++) {
      aLocalRank[aUpperSorted[i]] = i + 1;
      bLocalRank[bUpperSorted[i]] = i + 1;
    }
    final aLocal = <double>[];
    final bLocal = <double>[];
    for (final p in upperCohort) {
      aLocal.add(aLocalRank[p]!.toDouble());
      bLocal.add(bLocalRank[p]!.toDouble());
    }
    upperSpearman = _spearman(aLocal, bLocal);
    upperKendall = _kendallTauA(aLocal, bLocal);
  }

  final upperMovers = upperCohort.map((p) {
    final ra = rankAByPair[p]!;
    final rb = rankBByPair[p]!;
    return _Mover(
      name: p.ratingA.name,
      memberNumber: p.ratingA.memberNumber,
      rankA: ra,
      rankB: rb,
      absDiff: (ra - rb).abs(),
    );
  }).toList()
    ..sort((a, b) {
      final byDiff = b.absDiff.compareTo(a.absDiff);
      if (byDiff != 0) {
        return byDiff;
      }
      return a.rankA.compareTo(b.rankA);
    });

  final exclusiveK = math.min(kExclusiveTopK, n);
  final aTopSet = aSorted.take(exclusiveK).toSet();
  final bTopSet = bSorted.take(exclusiveK).toSet();
  final aOnly = aTopSet.difference(bTopSet).map((p) {
    return _Mover(
      name: p.ratingA.name,
      memberNumber: p.ratingA.memberNumber,
      rankA: rankAByPair[p]!,
      rankB: rankBByPair[p]!,
      absDiff: (rankAByPair[p]! - rankBByPair[p]!).abs(),
    );
  }).toList()
    ..sort((a, b) => a.rankA.compareTo(b.rankA));
  final bOnly = bTopSet.difference(aTopSet).map((p) {
    return _Mover(
      name: p.ratingA.name,
      memberNumber: p.ratingA.memberNumber,
      rankA: rankAByPair[p]!,
      rankB: rankBByPair[p]!,
      absDiff: (rankAByPair[p]! - rankBByPair[p]!).abs(),
    );
  }).toList()
    ..sort((a, b) => a.rankB.compareTo(b.rankB));

  return _GroupStats(
    n: n,
    meanAbsRankDiff: absDiffs.average,
    medianAbsRankDiff: _median(absDiffs),
    meanAbsPercentileDiff: absPctDiffs.average,
    meanAbsRatingDiff: absRatingDiffs.average,
    medianAbsRatingDiff: _median(absRatingDiffs),
    spearman: _spearman(ranksA, ranksB),
    kendall: _kendallTauA(ranksA, ranksB),
    upperQuartileN: upperCohort.length,
    upperQuartileSpearman: upperSpearman,
    upperQuartileKendall: upperKendall,
    upperQuartileLargestMovers: upperMovers
        .take(math.min(kLargestMoversCount, upperMovers.length))
        .toList(),
    topKOverlap: topKOverlap,
    aOnlyTop50: aOnly.take(math.min(kExclusiveReportCount, aOnly.length)).toList(),
    bOnlyTop50: bOnly.take(math.min(kExclusiveReportCount, bOnly.length)).toList(),
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
  final DbShooterRating ratingA;
  final DbShooterRating ratingB;
  final double sortA;
  final double sortB;

  _MatchedPair({
    required this.ratingA,
    required this.ratingB,
    required this.sortA,
    required this.sortB,
  });
}

class _Mover {
  final String name;
  final String memberNumber;
  final int rankA;
  final int rankB;
  final int absDiff;

  _Mover({
    required this.name,
    required this.memberNumber,
    required this.rankA,
    required this.rankB,
    required this.absDiff,
  });
}

class _GroupStats {
  final int n;
  final double meanAbsRankDiff;
  final double medianAbsRankDiff;
  final double meanAbsPercentileDiff;
  final double meanAbsRatingDiff;
  final double medianAbsRatingDiff;
  final double spearman;
  final double kendall;
  final int upperQuartileN;
  final double upperQuartileSpearman;
  final double upperQuartileKendall;
  final List<_Mover> upperQuartileLargestMovers;
  final Map<int, ({int shared})> topKOverlap;
  final List<_Mover> aOnlyTop50;
  final List<_Mover> bOnlyTop50;
  final List<_Mover> largestMovers;

  _GroupStats({
    required this.n,
    required this.meanAbsRankDiff,
    required this.medianAbsRankDiff,
    required this.meanAbsPercentileDiff,
    required this.meanAbsRatingDiff,
    required this.medianAbsRatingDiff,
    required this.spearman,
    required this.kendall,
    required this.upperQuartileN,
    required this.upperQuartileSpearman,
    required this.upperQuartileKendall,
    required this.upperQuartileLargestMovers,
    required this.topKOverlap,
    required this.aOnlyTop50,
    required this.bOnlyTop50,
    required this.largestMovers,
  });
}

enum _Affiliation {
  loOnly,
  coOnly,
  dual,
  neither;

  String get label => switch (this) {
        _Affiliation.loOnly => "LO-only",
        _Affiliation.coOnly => "CO-only",
        _Affiliation.dual => "dual",
        _Affiliation.neither => "neither",
      };
}

class _AffiliationCounts {
  final int loOnly;
  final int coOnly;
  final int dual;
  final int neither;

  const _AffiliationCounts({
    required this.loOnly,
    required this.coOnly,
    required this.dual,
    required this.neither,
  });
}

class _RankedPerson {
  final DbShooterRating rating;
  final int personId;
  final double sortRating;
  final _Affiliation affiliation;

  _RankedPerson({
    required this.rating,
    required this.personId,
    required this.sortRating,
    required this.affiliation,
  });
}

/// Stable person IDs across LO / CO / LOCO rows via shared number keys.
class _PersonIdIndex {
  final Map<String, int> _keyToId = {};
  final Map<int, int> _redirect = {};
  var _nextId = 0;

  int _root(int id) {
    var cur = id;
    while (_redirect.containsKey(cur)) {
      cur = _redirect[cur]!;
    }
    return cur;
  }

  int idFor(DbShooterRating rating) {
    final keys = _numberKeys(rating).toList();
    if (keys.isEmpty) {
      return _nextId++;
    }

    final found = <int>{};
    for (final k in keys) {
      final existing = _keyToId[k];
      if (existing != null) {
        found.add(_root(existing));
      }
    }

    late final int id;
    if (found.isEmpty) {
      id = _nextId++;
    }
    else {
      id = found.first;
      for (final other in found.skip(1)) {
        if (other != id) {
          _redirect[other] = id;
        }
      }
    }

    for (final k in keys) {
      _keyToId[k] = id;
    }
    return id;
  }
}
