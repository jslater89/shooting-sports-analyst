/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/match/practical_match.dart' as old;
import 'package:shooting_sports_analyst/data/match/score.dart';
import 'package:shooting_sports_analyst/data/match/shooter.dart' as oldS;
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("MatchTranslator");

extension MatchTranslator on ShootingMatch {
  static ShootingMatch shootingMatchFrom(old.PracticalMatch match) {
    List<MatchStage> newStages = [];
    for(var oldStage in match.stages) {
      newStages.add(MatchStage(
        stageId: oldStage.internalId,
        name: oldStage.name,
        scoring: _stageScoringFrom(oldStage.type),
        classifierNumber: oldStage.classifierNumber,
        classifier: oldStage.classifier,
        maxPoints: oldStage.maxPoints,
        minRounds: oldStage.minRounds,
      ));
    }

    List<MatchEntry> newShooters = [];
    for(var shooter in match.shooters) {
      var stageScores = <MatchStage, RawScore>{};
      PowerFactor powerFactor;
      try {
        powerFactor = uspsaSport.powerFactors.lookupByName(shooter.powerFactor.displayString()) ?? uspsaSport.powerFactors.lookupByName("subminor")!;
      } catch(e) {
        _log.e("Bad power factor: ${shooter.powerFactor.displayString()}");
        rethrow;
      }

      for (var entry in shooter.stageScores.entries) {
        var oldStage = entry.key;
        var oldScore = entry.value;

        var newStage = newStages.firstWhere((element) => element.stageId == oldStage.internalId);
        var newScore = RawScore(
          scoring: newStage.scoring,
          rawTime: oldScore.time,

          targetEvents: {
            if(oldScore.a > 0) powerFactor.targetEvents.lookupByName("A")!: oldScore.a,
            if(oldScore.c > 0) powerFactor.targetEvents.lookupByName("C")!: oldScore.c,
            if(oldScore.d > 0) powerFactor.targetEvents.lookupByName("D")!: oldScore.d,
            if(oldScore.m > 0) powerFactor.targetEvents.lookupByName("M")!: oldScore.m,
            if(oldScore.ns > 0) powerFactor.targetEvents.lookupByName("NS")!: oldScore.ns,
          },
          penaltyEvents: {
            if(oldScore.tenPointPenaltyCount > 0) powerFactor.penaltyEvents.lookupByName("Procedural")!: oldScore.tenPointPenaltyCount,
            if(oldScore.lateShot > 0) powerFactor.penaltyEvents.lookupByName("Overtime shot")!: oldScore.lateShot,
          }
        );

        stageScores[newStage] = newScore;
      }

      var newShooter = MatchEntry(
        entryId: shooter.internalId,
        firstName: shooter.firstName,
        lastName: shooter.lastName,
        memberNumber: shooter.memberNumber,
        powerFactor: powerFactor,
        classification: uspsaSport.classifications.lookupByName(shooter.classification!.displayString()),
        division: uspsaSport.divisions.lookupByName(shooter.division!.displayString()),
        dq: shooter.dq,
        female: shooter.female,
        reentry: shooter.reentry,
        scores: stageScores,
      );

      newShooters.add(newShooter);
    }

    var newMatch = ShootingMatch(
      sport: uspsaSport,
      name: match.name ?? "(unnamed match)",
      rawDate: match.rawDate ?? "",
      date: match.date ?? DateTime(0),
      stages: newStages,
      shooters: newShooters,
      level: uspsaSport.eventLevels.lookupByName((match.level ?? old.MatchLevel.I).name)!,
      sourceIds: [
        match.practiscoreId,
        if(match.practiscoreIdShort != null) match.practiscoreIdShort!,
      ]
    );

    return newMatch;
  }

  static StageScoring _stageScoringFrom(Scoring type) {
    switch(type) {
      case Scoring.comstock:
        return const HitFactorScoring();
      case Scoring.virginia:
        return const HitFactorScoring();
      case Scoring.fixedTime:
        return const PointsScoring(highScoreBest: true);
      case Scoring.chrono:
        return const IgnoredScoring();
      case Scoring.unknown:
        return const IgnoredScoring();
    }
  }
}