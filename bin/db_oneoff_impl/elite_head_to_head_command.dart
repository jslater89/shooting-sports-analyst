/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Elite head-to-head accuracy of raw rating numbers (Elo vs LLR).
///
/// For each per-division group, take the top 25% by current headline rating
/// (Elo [rating], LLR [calculateAgedRating]), then for every co-appearance in
/// a project match ask whether the higher pre-match rating correctly predicted
/// the higher match ratio.
///
/// Uncertainty is a minimal deadband only — not the match prediction stack:
/// - Elo σ = [EloShooterRating.standardError] (treated as 1SD of rating)
/// - LLR σ = √variance (log-rating 1SD; geometric in ratio space, additive here)
/// - Pair z = ΔR / √(σ_a² + σ_b²); |z| < 1 is a toss-up
///
/// Reports hard accuracy (all / excluding toss-ups) and soft mean P(actual
/// winner) overall and in the toss-up band.
///
/// Menu: H2H

import "dart:math" as math;

import "package:collection/collection.dart";
import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/math/distribution_tools.dart";
import "package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart";
import "package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";

import "base.dart";

const String kDefaultEloProjectName = "L2s Main";
const String kDefaultLlrProjectName = "L2s Main LLR";
const int kDefaultMinHistory = 30;
const double kTopFraction = 0.25;
const double kTossUpZ = 1.0;

class EliteHeadToHeadCommand extends DbOneoffCommand {
  EliteHeadToHeadCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "H2H";

  @override
  final String title = "Elite H2H Raw Rating Accuracy";

  @override
  String? get description =>
      "Top-25% per division: how often pre-match Elo / LLR raw ratings pick "
      "the H2H winner (hard + toss-up soft).";

  @override
  List<MenuArgument> get arguments => [
        IntMenuArgument(
          label: "Min history",
          required: false,
          defaultValue: kDefaultMinHistory,
          description:
              "Minimum stage history (Elo length; LLR lengthInStages). Use 0 for no filter.",
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

  final eloAlgo = eloProject.settings.algorithm;
  if (eloAlgo is! MultiplayerPercentEloRater) {
    console.print("Project $eloProjectName is not multiplayer Elo.");
    return;
  }
  final llrAlgo = llrProject.settings.algorithm;
  if (llrAlgo is! LatentLogRater) {
    console.print("Project $llrProjectName is not Latent Log.");
    return;
  }

  if (!eloProject.dbGroups.isLoaded) {
    await eloProject.dbGroups.load();
  }
  if (!llrProject.dbGroups.isLoaded) {
    await llrProject.dbGroups.load();
  }

  EloShooterRating.errorScale = eloAlgo.scale;

  final activeSince = DateTime(DateTime.now().year - 1, 1, 1);
  final eloByUuid = {for (final g in eloProject.groups) g.uuid: g};
  final divisionGroups = llrProject.groups
      .where((g) => g.divisionNames.length == 1)
      .sorted((a, b) => a.sortOrder.compareTo(b.sortOrder));

  final buf = StringBuffer()
    ..writeln("=== Elite H2H Raw Rating Accuracy ===")
    ..writeln("Elo:  $eloProjectName")
    ..writeln("LLR:  $llrProjectName")
    ..writeln(
      "Elite: top ${(kTopFraction * 100).round()}% by current headline rating (own system)",
    )
    ..writeln("Outcome: higher match ratio wins; equal ratios skipped")
    ..writeln("Pre-match: ratingForEvent(beforeMatch); LLR aged to match date")
    ..writeln(
      "Deadband: |z| < $kTossUpZ with z = ΔR / √(σ_a²+σ_b²); "
      "Elo σ=standardError, LLR σ=√variance (no sport/prediction noise)",
    )
    ..writeln(
      "Min history: $minHistory stages; active since ${activeSince.year}-01-01",
    )
    ..writeln(
      "Soft: mean model P(actual winner); Elo logistic, LLR Φ(ΔR/√(Va+Vb))",
    )
    ..writeln(
      "Intersection also: all-pairs hard%; Brier/log loss on P(A beats B)",
    )
    ..writeln("");

  if (divisionGroups.isEmpty) {
    buf.writeln("No per-division groups found.");
    console.print(buf.toString());
    return;
  }

  final matchPointers = [...eloProject.matchPointers]
    ..sort((a, b) => (a.date ?? DateTime(1970)).compareTo(b.date ?? DateTime(1970)));

  for (final llrGroup in divisionGroups) {
    final eloGroup = eloByUuid[llrGroup.uuid];
    if (eloGroup == null) {
      buf.writeln("--- ${llrGroup.uiLabel} ---");
      buf.writeln("  No matching Elo group (${llrGroup.uuid}).");
      buf.writeln("");
      continue;
    }

    console.print("Preparing elite set: ${llrGroup.uiLabel}");

    final eloRes = eloProject.getRatingsSync(eloGroup);
    final llrRes = llrProject.getRatingsSync(llrGroup);
    if (eloRes.isErr() || llrRes.isErr()) {
      buf.writeln("--- ${llrGroup.uiLabel} ---");
      buf.writeln("  Failed to load ratings.");
      buf.writeln("");
      continue;
    }

    var eloDb = eloRes.unwrap();
    var llrDb = llrRes.unwrap();
    if (minHistory > 0) {
      eloDb = eloDb.where((r) => r.length >= minHistory).toList();
      llrDb = llrDb
          .where((r) => LatentLogRating.getLengthInStages(r) >= minHistory)
          .toList();
    }
    eloDb = eloDb.where((r) => r.lastSeen.isAfter(activeSince)).toList();
    llrDb = llrDb.where((r) => r.lastSeen.isAfter(activeSince)).toList();

    final eloWrapped = eloDb.map((r) => EloShooterRating.wrapDbRating(r)).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    final llrWrapped = <LatentLogRating>[];
    for (final r in llrDb) {
      llrWrapped.add(LatentLogRating.wrapDbRatingWithSettings(llrAlgo, r));
    }
    llrWrapped.sort(
      (a, b) => b.calculateAgedRating().compareTo(a.calculateAgedRating()),
    );

    final eloTopN = math.max(1, (eloWrapped.length * kTopFraction).ceil());
    final llrTopN = math.max(1, (llrWrapped.length * kTopFraction).ceil());
    final eloElite = eloWrapped.take(eloTopN).toList();
    final llrElite = llrWrapped.take(llrTopN).toList();

    final eloIndex = _buildShooterIndex(eloElite);
    final llrIndex = _buildShooterIndex(llrElite);

    final eloStats = _SystemStats(label: "Elo");
    final llrStats = _SystemStats(label: "LLR");
    final bothStats = _PairedStats();

    final progress = LabeledProgressBar(
      maxValue: matchPointers.length,
      initialLabel: "${llrGroup.uiLabel}: matches",
      canHaveErrors: true,
    );

    for (final ptr in matchPointers) {
      progress.tick(ptr.name);
      final matchRes = await ptr.getDbMatch(db, downloadIfMissing: false);
      if (matchRes.isErr()) {
        continue;
      }
      final dbMatch = matchRes.unwrap();
      if (dbMatch.shootersStoredSeparately) {
        await dbMatch.shooterLinks.load();
      }
      final hydrated = await dbMatch.hydrate();
      if (hydrated.isErr()) {
        continue;
      }
      final match = hydrated.unwrap();
      final scores = match.getScoresFromFilters(llrGroup.filters);
      if (scores.length < 2) {
        continue;
      }

      final eloInMatch = <_CompetitorSnap>[];
      final llrInMatch = <_CompetitorSnap>[];
      final seenElo = <int>{};
      final seenLlr = <int>{};

      for (final entry in scores.entries) {
        final shooter = entry.key;
        final score = entry.value;
        if (shooter.dq || score.ratio <= 0) {
          continue;
        }

        final eloHit = _lookupShooter(eloIndex, shooter);
        if (eloHit is EloShooterRating && seenElo.add(eloHit.wrappedRating.id)) {
          final snap = _eloSnap(eloHit, match, score.ratio, eloAlgo);
          if (snap != null) {
            eloInMatch.add(snap);
          }
        }

        final llrHit = _lookupShooter(llrIndex, shooter);
        if (llrHit is LatentLogRating && seenLlr.add(llrHit.wrappedRating.id)) {
          final snap = _llrSnap(llrHit, match, score.ratio, llrAlgo);
          if (snap != null) {
            llrInMatch.add(snap);
          }
        }
      }

      _accumulatePairs(eloInMatch, eloStats, eloMode: true, eloAlgo: eloAlgo);
      _accumulatePairs(llrInMatch, llrStats, eloMode: false, eloAlgo: eloAlgo);

      final eloByKey = <String, _CompetitorSnap>{};
      for (final s in eloInMatch) {
        for (final k in s.numberKeys) {
          eloByKey.putIfAbsent(k, () => s);
        }
      }
      final intersectionPeople = <(_CompetitorSnap, _CompetitorSnap)>[];
      final usedLlrIds = <int>{};
      for (final llr in llrInMatch) {
        _CompetitorSnap? elo;
        for (final k in llr.numberKeys) {
          elo = eloByKey[k];
          if (elo != null) {
            break;
          }
        }
        if (elo == null || !usedLlrIds.add(llr.id)) {
          continue;
        }
        intersectionPeople.add((elo, llr));
      }
      _accumulateIntersection(intersectionPeople, bothStats, eloAlgo: eloAlgo);
    }

    progress.complete();

    buf.writeln("--- ${llrGroup.uiLabel} ---");
    buf.writeln(
      "  Elite: Elo top $eloTopN / ${eloWrapped.length}; "
      "LLR top $llrTopN / ${llrWrapped.length}",
    );
    _writeSystemStats(buf, eloStats);
    _writeSystemStats(buf, llrStats);
    _writePairedStats(buf, bothStats);
    buf.writeln("");
  }

  console.print(buf.toString());
}

void _writeSystemStats(StringBuffer buf, _SystemStats s) {
  buf.writeln("  ${s.label} (own top ${(kTopFraction * 100).round()}% H2Hs):");
  if (s.all.n == 0) {
    buf.writeln("    No scored pairs.");
    return;
  }
  buf.writeln(
    "    All:      n=${s.all.n}  hard=${_pct(s.all.hardCorrect, s.all.n)}  "
    "softP(win)=${s.all.meanSoft.toStringAsFixed(3)}",
  );
  buf.writeln(
    "    Clear (|z|≥$kTossUpZ): n=${s.clear.n}  "
    "hard=${_pct(s.clear.hardCorrect, s.clear.n)}  "
    "softP(win)=${s.clear.meanSoft.toStringAsFixed(3)}",
  );
  buf.writeln(
    "    Toss-up (|z|<$kTossUpZ): n=${s.tossUp.n}  "
    "hard=${_pct(s.tossUp.hardCorrect, s.tossUp.n)}  "
    "softP(win)=${s.tossUp.meanSoft.toStringAsFixed(3)}",
  );
}

void _writePairedStats(StringBuffer buf, _PairedStats s) {
  buf.writeln("  Intersection (both elites, same H2Hs):");
  if (s.n == 0) {
    buf.writeln("    No scored pairs.");
    return;
  }
  buf.writeln(
    "    All-pairs hard: n=${s.n}  "
    "Elo=${_pct(s.eloHardCorrect, s.n)}  "
    "LLR=${_pct(s.llrHardCorrect, s.n)}",
  );
  buf.writeln(
    "    Clear hard: "
    "Elo=${_pct(s.eloClearCorrect, s.eloClearN)} (n=${s.eloClearN})  "
    "LLR=${_pct(s.llrClearCorrect, s.llrClearN)} (n=${s.llrClearN})",
  );
  buf.writeln(
    "    softP(win): "
    "Elo=${(s.eloSoftSum / s.n).toStringAsFixed(3)}  "
    "LLR=${(s.llrSoftSum / s.n).toStringAsFixed(3)}",
  );
  buf.writeln(
    "    Brier (↓ better): "
    "Elo=${(s.eloBrierSum / s.n).toStringAsFixed(4)}  "
    "LLR=${(s.llrBrierSum / s.n).toStringAsFixed(4)}  "
    "LogLoss (↓ better): "
    "Elo=${(s.eloLogLossSum / s.n).toStringAsFixed(4)}  "
    "LLR=${(s.llrLogLossSum / s.n).toStringAsFixed(4)}",
  );
}

void _accumulatePairs(
  List<_CompetitorSnap> field,
  _SystemStats stats, {
  required bool eloMode,
  required MultiplayerPercentEloRater eloAlgo,
}) {
  for (var i = 0; i < field.length; i++) {
    for (var j = i + 1; j < field.length; j++) {
      final a = field[i];
      final b = field[j];
      if (a.ratio == b.ratio) {
        continue;
      }
      final aWon = a.ratio > b.ratio;
      final pred = eloMode ? _eloPredict(a, b, eloAlgo) : _llrPredict(a, b);
      final favoriteIsA = pred.delta >= 0;
      final hardCorrect = favoriteIsA == aWon;
      final soft = aWon ? pred.pABeatsB : (1.0 - pred.pABeatsB);
      stats.all.add(hardCorrect: hardCorrect, soft: soft);
      if (pred.absZ < kTossUpZ) {
        stats.tossUp.add(hardCorrect: hardCorrect, soft: soft);
      }
      else {
        stats.clear.add(hardCorrect: hardCorrect, soft: soft);
      }
    }
  }
}

void _accumulateIntersection(
  List<(_CompetitorSnap, _CompetitorSnap)> people,
  _PairedStats bothStats, {
  required MultiplayerPercentEloRater eloAlgo,
}) {
  for (var i = 0; i < people.length; i++) {
    for (var j = i + 1; j < people.length; j++) {
      final (eloA, llrA) = people[i];
      final (eloB, llrB) = people[j];
      if (eloA.ratio == eloB.ratio) {
        continue;
      }
      final aWon = eloA.ratio > eloB.ratio;

      final eloPred = _eloPredict(eloA, eloB, eloAlgo);
      final llrPred = _llrPredict(llrA, llrB);

      bothStats.n++;

      final eloHard = (eloPred.delta >= 0) == aWon;
      final llrHard = (llrPred.delta >= 0) == aWon;
      if (eloHard) {
        bothStats.eloHardCorrect++;
      }
      if (llrHard) {
        bothStats.llrHardCorrect++;
      }

      final eloPA = eloPred.pABeatsB;
      final llrPA = llrPred.pABeatsB;
      bothStats.eloSoftSum += aWon ? eloPA : (1.0 - eloPA);
      bothStats.llrSoftSum += aWon ? llrPA : (1.0 - llrPA);
      bothStats.eloBrierSum += _brier(eloPA, aWon);
      bothStats.llrBrierSum += _brier(llrPA, aWon);
      bothStats.eloLogLossSum += _logLoss(eloPA, aWon);
      bothStats.llrLogLossSum += _logLoss(llrPA, aWon);

      if (eloPred.absZ >= kTossUpZ) {
        bothStats.eloClearN++;
        if (eloHard) {
          bothStats.eloClearCorrect++;
        }
      }
      if (llrPred.absZ >= kTossUpZ) {
        bothStats.llrClearN++;
        if (llrHard) {
          bothStats.llrClearCorrect++;
        }
      }
    }
  }
}

_PredResult _eloPredict(
  _CompetitorSnap a,
  _CompetitorSnap b,
  MultiplayerPercentEloRater algo,
) {
  final delta = a.rating - b.rating;
  final sig2 = a.sigma * a.sigma + b.sigma * b.sigma;
  final absZ = sig2 > 0 ? delta.abs() / math.sqrt(sig2) : double.infinity;
  final p = 1.0 /
      (1.0 + math.pow(algo.probabilityBase, (b.rating - a.rating) / algo.scale));
  return _PredResult(delta: delta, absZ: absZ, pABeatsB: p.toDouble());
}

_PredResult _llrPredict(_CompetitorSnap a, _CompetitorSnap b) {
  final delta = a.rating - b.rating;
  final sig2 = a.sigma * a.sigma + b.sigma * b.sigma;
  final denom = sig2 > 0 ? math.sqrt(sig2) : 1e-12;
  final absZ = delta.abs() / denom;
  final p = stdNormal.cdf(delta / denom).toDouble().clamp(0.0, 1.0);
  return _PredResult(delta: delta, absZ: absZ, pABeatsB: p);
}

_CompetitorSnap? _eloSnap(
  EloShooterRating rating,
  ShootingMatch match,
  double ratio,
  MultiplayerPercentEloRater algo,
) {
  final events = AnalystDatabase().getRatingEventsByMatchIdsSync(
    rating.wrappedRating,
    matchIds: match.sourceIds,
  );
  if (events.isEmpty) {
    return null;
  }
  // Earliest stage event's oldRating is the pre-match rating (byStage Elo).
  final earliest = events.reduce(
    (a, b) => a.dateAndStageNumber <= b.dateAndStageNumber ? a : b,
  );
  final pre = earliest.oldRating;
  return _CompetitorSnap(
    id: rating.wrappedRating.id,
    rating: pre,
    sigma: math.max(rating.standardError, 1e-6),
    ratio: ratio,
    numberKeys: _numberKeys(rating).toList(),
  );
}

_CompetitorSnap? _llrSnap(
  LatentLogRating rating,
  ShootingMatch match,
  double ratio,
  LatentLogRater algo,
) {
  final dbEvents = AnalystDatabase().getRatingEventsByMatchIdsSync(
    rating.wrappedRating,
    matchIds: match.sourceIds,
  );
  if (dbEvents.isEmpty) {
    return null;
  }
  final earliest = dbEvents.reduce(
    (a, b) => a.dateAndStageNumber <= b.dateAndStageNumber ? a : b,
  );
  final event = rating.wrapEvent(earliest);
  final priorSeen = _priorSeenDate(rating, match) ?? rating.firstSeen;
  final aged = LatentLogRating.calculateAgedRatingStatic(
    rating: event.oldRating,
    asOfDate: match.date,
    settings: algo.settings,
    lastSeen: priorSeen,
  );
  return _CompetitorSnap(
    id: rating.wrappedRating.id,
    rating: aged,
    sigma: math.sqrt(math.max(event.oldVariance, 1e-12)),
    ratio: ratio,
    numberKeys: _numberKeys(rating).toList(),
  );
}

DateTime? _priorSeenDate(ShooterRating rating, ShootingMatch match) {
  final prior = AnalystDatabase().getRatingEventsForSync(
    rating.wrappedRating,
    before: match.date,
    limit: 1,
  );
  return prior.firstOrNull?.date;
}

Map<String, ShooterRating> _buildShooterIndex(List<ShooterRating> ratings) {
  final index = <String, ShooterRating>{};
  for (final r in ratings) {
    for (final k in _numberKeys(r)) {
      index.putIfAbsent(k, () => r);
    }
  }
  return index;
}

ShooterRating? _lookupShooter(Map<String, ShooterRating> index, MatchEntry entry) {
  for (final raw in [
    entry.memberNumber,
    entry.originalMemberNumber,
    ...entry.knownMemberNumbers,
  ]) {
    final t = raw.trim();
    if (t.isEmpty || t == "(invalid)") {
      continue;
    }
    final hit = index[ShooterDeduplicator.normalizeNumberBasic(t)];
    if (hit != null) {
      return hit;
    }
  }
  return null;
}

Iterable<String> _numberKeys(Shooter rating) sync* {
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

String _pct(int num, int den) {
  if (den == 0) {
    return "n/a";
  }
  return "${(100.0 * num / den).toStringAsFixed(1)}%";
}

/// Brier score for P(A beats B) with outcome [aWon].
double _brier(double pABeatsB, bool aWon) {
  final y = aWon ? 1.0 : 0.0;
  final err = pABeatsB - y;
  return err * err;
}

/// Binary log loss for P(A beats B) with outcome [aWon].
double _logLoss(double pABeatsB, bool aWon) {
  final p = pABeatsB.clamp(1e-15, 1.0 - 1e-15);
  if (aWon) {
    return -math.log(p);
  }
  return -math.log(1.0 - p);
}

class _CompetitorSnap {
  final int id;
  final double rating;
  final double sigma;
  final double ratio;
  final List<String> numberKeys;

  _CompetitorSnap({
    required this.id,
    required this.rating,
    required this.sigma,
    required this.ratio,
    required this.numberKeys,
  });
}

class _PredResult {
  final double delta;
  final double absZ;
  final double pABeatsB;

  _PredResult({
    required this.delta,
    required this.absZ,
    required this.pABeatsB,
  });
}

class _Bucket {
  int n = 0;
  int hardCorrect = 0;
  double softSum = 0;

  void add({required bool hardCorrect, required double soft}) {
    n++;
    if (hardCorrect) {
      this.hardCorrect++;
    }
    softSum += soft;
  }

  double get meanSoft => n == 0 ? double.nan : softSum / n;
}

class _SystemStats {
  final String label;
  final all = _Bucket();
  final clear = _Bucket();
  final tossUp = _Bucket();

  _SystemStats({required this.label});
}

class _PairedStats {
  int n = 0;
  int eloHardCorrect = 0;
  int llrHardCorrect = 0;
  int eloClearN = 0;
  int eloClearCorrect = 0;
  int llrClearN = 0;
  int llrClearCorrect = 0;
  double eloSoftSum = 0;
  double llrSoftSum = 0;
  double eloBrierSum = 0;
  double llrBrierSum = 0;
  double eloLogLossSum = 0;
  double llrLogLossSum = 0;
}
