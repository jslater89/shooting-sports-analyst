import 'package:uspsa_result_viewer/data/match/practical_match.dart' as old;
import 'package:uspsa_result_viewer/data/match/score.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/uspsa.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

extension MatchTranslator on ShootingMatch {
  static ShootingMatch shootingMatchFrom(old.PracticalMatch match) {
    List<MatchStage> stages = [];
    for(var oldStage in match.stages) {
      stages.add(MatchStage(
        stageId: oldStage.internalId,
        name: oldStage.name,
        scoring: _stageScoringFrom(oldStage.type),
        classifierNumber: oldStage.classifierNumber,
        classifier: oldStage.classifier,
        maxPoints: oldStage.maxPoints,
        minRounds: oldStage.minRounds,
      ));
    }

    List<MatchEntry> shooters = [];
    for(var shooter in match.shooters) {
      var stageScores = <MatchStage, RawScore>{};
      var powerFactor = uspsaSport.powerFactors.lookupByName(shooter.powerFactor.displayString())!;

      for (var entry in shooter.stageScores.entries) {
        var oldStage = entry.key;
        var oldScore = entry.value;

        var newStage = stages.firstWhere((element) => element.stageId == oldStage.internalId);
        var newScore = RawScore(
          scoring: newStage.scoring,
          rawTime: oldScore.time,

          scoringEvents: {
            if(oldScore.a > 0) powerFactor.targetEvents.lookupByName("A")!: oldScore.a,
            if(oldScore.c > 0) powerFactor.targetEvents.lookupByName("C")!: oldScore.c,
            if(oldScore.d > 0) powerFactor.targetEvents.lookupByName("D")!: oldScore.d,
            if(oldScore.m > 0) powerFactor.targetEvents.lookupByName("M")!: oldScore.m,
            if(oldScore.ns > 0) powerFactor.targetEvents.lookupByName("NS")!: oldScore.ns,
          },
          penaltyEvents: {
            if(oldScore.penaltyCount > 0) powerFactor.penaltyEvents.lookupByName("Procedural")!: oldScore.penaltyCount,
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

      shooters.add(newShooter);
    }

    var newMatch = ShootingMatch(
      sport: uspsaSport,
      eventName: match.name ?? "(unnamed match)",
      rawDate: match.rawDate ?? "",
      date: match.date ?? DateTime(0),
      stages: stages,
      shooters: shooters,
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