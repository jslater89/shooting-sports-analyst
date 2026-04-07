/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_fetch_options.dart";
import "package:shooting_sports_analyst/data/source/hitfacto_rs/hitfacto_rs_models.dart";
import "package:shooting_sports_analyst/data/source/match_source_error.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("HitfactoRsMatchConverter");

class HitfactoRsMatchConverter {
  static StageScoring _stageScoringFromApi(String scoringType) {
    final u = scoringType.toLowerCase();
    if (u == "comstock" || u == "virginia") {
      return const HitFactorScoring();
    }
    if (u == "fixed" || u.contains("fixed")) {
      return const PointsScoring();
    }
    return const IgnoredScoring();
  }

  static Division? _lookupDivision(
    Sport sport,
    String apiDivision, {
    required bool fuzzy,
  }) {
    if (!sport.hasDivisions) {
      return null;
    }
    final stripped = apiDivision.replaceAll("_", "").toLowerCase();
    var d = sport.divisions.values.lookupByName(stripped, fallback: false);
    d ??= sport.divisions.values.lookupByName(apiDivision, fallback: false);
    if (d == null && fuzzy) {
      d = sport.divisions.values.lookupByName(stripped, fallback: true);
    }
    return d;
  }

  static Result<ShootingMatch, MatchSourceError> toShootingMatch({
    required HitfactoRsMatchDetail detail,
    required List<HitfactoRsResultRow> resultRows,
    HitfactoRsMatchFetchOptions? options,
    required List<String> sourceIds,
    required String sourceCode,
  }) {
    final sport = options?.parseAsSport ?? uspsaSport;

    final stageByNumber = <int, MatchStage>{};
    for (final s in detail.stages) {
      stageByNumber[s.stageNumber] = MatchStage(
        stageId: s.stageNumber,
        name: s.stageName,
        scoring: _stageScoringFromApi(s.scoringType),
        minRounds: 0,
        maxPoints: s.totalPoints,
        classifier: s.isClassifier,
        classifierNumber: s.classifierCode ?? "",
        sourceId: "${s.id}",
      );
    }

    final ignoreUnknown = options?.ignoreUnknownDivisions ?? false;
    final fuzzy = options?.fuzzyHitFactorDivisionMatching ?? false;

    final byIdentity = <int, List<HitfactoRsResultRow>>{};
    for (final r in resultRows) {
      byIdentity.addToList(r.identityId, r);
    }

    final sortedIds = byIdentity.keys.toList()..sort();
    final shooters = <String, MatchEntry>{};
    int nextEntryId = 1;
    for (final int identityId in sortedIds) {
      final rows = byIdentity[identityId]!;
      final sample = rows.first;
      Division? division = _lookupDivision(
        sport,
        sample.division,
        fuzzy: fuzzy,
      );

      division ??= sport.divisions.values.lookupByName(
        sample.division.replaceAll("_", ""),
        fallback: true,
      );
      if (division == null) {
        continue;
      }
      if (ignoreUnknown) {
        final nonFallback =
            sport.divisions.values.lookupByName(
              sample.division.replaceAll("_", ""),
              fallback: false,
            ) ??
            sport.divisions.values.lookupByName(
              sample.division,
              fallback: false,
            );
        if (nonFallback == null) {
          _log.v(
            "Skipping identity $identityId unknown division ${sample.division}",
          );
          continue;
        }
      }

      final classification = sport.hasClassifications
          ? sport.classifications.values.lookupByName(
              sample.classification,
              fallback: true,
            )
          : null;

      final powerFactor = sport.powerFactors.values.lookupByName(sample.powerFactor, fallback: true);

      final idKey = "$identityId";
      shooters[idKey] = MatchEntry(
        entryId: nextEntryId++,
        firstName: sample.firstName,
        lastName: sample.lastName,
        memberNumber: sample.memberNumber,
        powerFactor: powerFactor ?? sport.defaultPowerFactor,
        scores: {},
        division: division,
        classification: classification,
        sourceId: idKey,
      );
    }

    if (shooters.isEmpty) {
      return Result.err(
        UnsupportedMatchType("No shooters after division filter"),
      );
    }

    DateTime lastUpdated = practicalShootingZeroDate;
    String rawDate;
    DateTime date;
    if (detail.matchDate != null && detail.matchDate!.isNotEmpty) {
      rawDate = detail.matchDate!;
      try {
        date = programmerYmdFormat.parse(rawDate);
      } catch (e) {
        _log.w("Bad match date $rawDate: $e");
        date = DateTime.now();
        rawDate = programmerYmdFormat.format(date);
      }
    } else {
      date = DateTime.now();
      rawDate = programmerYmdFormat.format(date);
    }

    for (final row in resultRows) {
      final idKey = "${row.identityId}";
      final shooter = shooters[idKey];
      if (shooter == null) {
        continue;
      }
      final stage = stageByNumber[row.stageNumber];
      if (stage == null) {
        _log.w("Stage ${row.stageNumber} not in match definition");
        continue;
      }

      final score = _rawScoreForRow(sport: sport, stage: stage, row: row, powerFactor: shooter.powerFactor);
      shooter.scores[stage] = score;
    }

    if (lastUpdated == practicalShootingZeroDate) {
      lastUpdated = DateTime.now();
    }

    MatchLevel? level;
    if (detail.matchLevel != null && detail.matchLevel!.isNotEmpty) {
      level = sport.eventLevels.values.lookupByName(
        detail.matchLevel!,
        fallback: true,
      );
    }

    return Result.ok(
      ShootingMatch(
        sport: sport,
        name: detail.matchName,
        rawDate: rawDate,
        date: date,
        sourceLastUpdated: lastUpdated,
        shooters: shooters.values.toList(),
        stages: stageByNumber.values.toList()
          ..sort((a, b) => a.stageId.compareTo(b.stageId)),
        sourceIds: sourceIds,
        sourceCode: sourceCode,
        level: level,
      ),
    );
  }

  static RawScore _rawScoreForRow({
    required Sport sport,
    required MatchStage stage,
    required HitfactoRsResultRow row,
    required PowerFactor powerFactor,
  }) {
    if (row.dnf) {
      return RawScore(
        scoring: stage.scoring,
        rawTime: row.timeSeconds,
        stringTimes: row.stringTimes,
        splitTimes: row.splitTimes,
        targetEvents: {},
        penaltyEvents: {},
        dq: row.stageDq,
      );
    }

    final targetEvents = <ScoringEvent, int>{};
    final penaltyEvents = <ScoringEvent, int>{};

    void addTarget(String name, int n) {
      if (n <= 0) {
        return;
      }
      final ev = powerFactor.targetEvents.lookupByName(name);
      if (ev != null) {
        targetEvents.incrementBy(ev, n);
      }
    }

    addTarget("A", row.alphas);
    if (row.bravos + row.charlies > 0) {
      addTarget("C", row.bravos + row.charlies);
    }
    addTarget("D", row.deltas);
    addTarget("M", row.misses);
    addTarget("NS", row.noShoots);

    if (row.procedurals > 0) {
      final p = powerFactor.penaltyEvents.lookupByName("Procedural");
      if (p != null) {
        penaltyEvents.incrementBy(p, row.procedurals);
      }
    }

    return RawScore(
      scoring: stage.scoring,
      rawTime: row.timeSeconds,
      targetEvents: targetEvents,
      penaltyEvents: penaltyEvents,
      stringTimes: row.stringTimes,
      splitTimes: row.splitTimes,
      dq: row.stageDq,
    );
  }
}
