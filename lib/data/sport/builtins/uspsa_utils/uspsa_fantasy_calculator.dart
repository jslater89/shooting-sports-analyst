/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

class USPSAFantasyScoringCalculator extends FantasyScoringCalculator {
  const USPSAFantasyScoringCalculator({Map<FantasyScoringCategory, double>? pointsAvailable}) : _pointsAvailable = pointsAvailable;

  final Map<FantasyScoringCategory, double>? _pointsAvailable;

  @override
  Map<FantasyScoringCategory, double> get pointsAvailable => _pointsAvailable ?? {
    FantasyScoringCategory.finishPercentage: 100,
    FantasyScoringCategory.stageWins: 100,
    FantasyScoringCategory.stageTop10Percents: 75,
    FantasyScoringCategory.stageTop25Percents: 50,
    FantasyScoringCategory.rawTimeWins: 100,
    FantasyScoringCategory.rawTimeTop10Percents: 75,
    FantasyScoringCategory.rawTimeTop25Percents: 50,
    FantasyScoringCategory.accuracyWins: 100,
    FantasyScoringCategory.accuracyTop10Percents: 75,
    FantasyScoringCategory.accuracyTop25Percents: 50,
    FantasyScoringCategory.penalties: -5,
    FantasyScoringCategory.divisionParticipationPenalty: 1,
  };

  @override
  Map<MatchEntry, FantasyScore> calculateFantasyScores(ShootingMatch match, {
    bool byDivision = true,
    List<MatchEntry>? entries,
  }) {

    // Calculate participation penalty ratios, based on the rules in [USPSAFantasyScoringCategory.divisionParticipationPenalty].
    Map<Division, double> participationPenaltyRatios = {};
    Map<Division, bool> eligible = {};
    Map<Division, int> shooterCounts = {};
    Map<Division, int> gmCounts = {};
    for(var division in match.sport.divisions.values) {
      shooterCounts[division] = 0;
      gmCounts[division] = 0;
      eligible[division] = false;
    }

    for(var entry in match.shooters) {
      if(entry.division != null) {
        shooterCounts.increment(entry.division!);
      }
      if(entry.classification != null && entry.classification!.matches("gm")) {
        gmCounts.increment(entry.division!);
      }
    }

    Division? largestDivision = null;
    for(var division in match.sport.divisions.values) {
      if(largestDivision == null || shooterCounts[division]! > shooterCounts[largestDivision]!) {
        largestDivision = division;
      }
      if(shooterCounts[division]! >= 25 && gmCounts[division]! >= 1 && shooterCounts[division]! <= gmCounts[division]! * 50) {
        eligible[division] = true;
      }
      else {
        eligible[division] = false;
      }
    }
    eligible[largestDivision!] = true;

    var smallestEligibleDivision = largestDivision;
    for(var division in match.sport.divisions.values) {
      if(eligible[division] == true && shooterCounts[division]! < shooterCounts[smallestEligibleDivision]!) {
        smallestEligibleDivision = division;
      }
    }

    Map<MatchEntry, FantasyScore> fantasyScores = {};
    if(byDivision) {
      for(var division in match.sport.divisions.values) {
        if(eligible[division] == true) {
          participationPenaltyRatios[division] = 1;
        }
        else {
          participationPenaltyRatios[division] = min(1, shooterCounts[division]! / shooterCounts[smallestEligibleDivision]!);
        }
      }

      for(var division in match.sport.divisions.values) {
        var participationPenalty = participationPenaltyRatios[division]!;
        var shooters = match.filterShooters(divisions: [division]);
        if(entries != null) {
          shooters.retainWhere((e) => entries.contains(e));
        }
        var scores = match.getScores(shooters: shooters);

        _calculate(
          match: match,
          scores: scores,
          participationPenalty: participationPenalty,
          fantasyScores: fantasyScores,
        );
      }
    }
    else if(entries != null) {
      var scores = match.getScores(shooters: entries);

      // Calculate participation penalty according to the same rules as above, using all competitors
      // in entries as the basis.
      int shooterCount = entries.length;
      int gmCount = entries.where((e) => e.classification != null && e.classification!.matches("gm")).length;
      double participationPenalty = 1;
      if(shooterCount < 25 || gmCount < 1 || shooterCount > gmCount * 50) {
        participationPenalty = min(1, shooterCount / shooterCounts[smallestEligibleDivision]!);
      }

      _calculate(
        match: match,
        scores: scores,
        participationPenalty: participationPenalty,
        fantasyScores: fantasyScores,
      );
    }
    else {
      throw ArgumentError("byDivision must be true or entries must be provided");
    }

    return fantasyScores;
  }

  void _calculate({
    required ShootingMatch match,
    required Map<MatchEntry, RelativeMatchScore> scores,
    required double participationPenalty,
    required Map<MatchEntry, FantasyScore> fantasyScores,
  }) {
    Map<MatchStage, double> lowTimes = {};
    Map<MatchStage, int> highPoints = {};
    int stageCount = match.stages.where((s) =>
      s.scoring is! IgnoredScoring
    ).length;

    for(var stage in match.stages) {
      lowTimes[stage] = double.infinity;
      highPoints[stage] = 0;
    }

    for(var stage in match.stages) {
      for(var score in scores.values) {
        if(score.isDnf) {
          continue;
        }
        var stageScore = score.stageScores[stage];
        if(stageScore == null) {
          continue;
        }
        if(stageScore.score.finalTime < lowTimes[stage]!) {
          lowTimes[stage] = stageScore.score.finalTime;
        }
        var points = _getStagePoints(stageScore.score);
        if(points > highPoints[stage]!) {
          highPoints[stage] = points;
        }
      }
    }

    for(var shooter in scores.keys) {
      var scoreMap = <FantasyScoringCategory, double>{};
      var countMap = <FantasyScoringCategory, int>{};
      for(var category in FantasyScoringCategory.values) {
        scoreMap[category] = 0;
        countMap[category] = 0;
      }
      var score = scores[shooter]!;

      // int totalPoints = 0;
      int penaltyCount = 0;

      // Points for finish percentage.
      var finishPointsAvailable = pointsAvailable[FantasyScoringCategory.finishPercentage] ?? FantasyScoringCategory.finishPercentage.defaultPointsAvailable;
      scoreMap[FantasyScoringCategory.finishPercentage] = score.ratio * finishPointsAvailable;

      for(var stage in match.stages) {
        var stageScore = score.stageScores[stage];
        if(stageScore == null) {
          continue;
        }
        int highScore = highPoints[stage]!;
        double lowTime = lowTimes[stage]!;

        // Points for stage wins, top 10%, and top 25%.
        if(stageScore.place == 1) {
        // if(stageScore.percentage >= 95) {
          var weight = pointsAvailable[FantasyScoringCategory.stageWins] ?? FantasyScoringCategory.stageWins.defaultPointsAvailable;
          scoreMap.incrementBy(FantasyScoringCategory.stageWins, weight / stageCount);
          countMap.incrementBy(FantasyScoringCategory.stageWins, 1);
        }
        else if(stageScore.percentage >= 90) {
          var weight = pointsAvailable[FantasyScoringCategory.stageTop10Percents] ?? FantasyScoringCategory.stageTop10Percents.defaultPointsAvailable;
          scoreMap.incrementBy(FantasyScoringCategory.stageTop10Percents, weight / stageCount);
          countMap.incrementBy(FantasyScoringCategory.stageTop10Percents, 1);
        }
        else if(stageScore.percentage >= 75) {
          var weight = pointsAvailable[FantasyScoringCategory.stageTop25Percents] ?? FantasyScoringCategory.stageTop25Percents.defaultPointsAvailable;
          scoreMap.incrementBy(FantasyScoringCategory.stageTop25Percents, weight / stageCount);
          countMap.incrementBy(FantasyScoringCategory.stageTop25Percents, 1);
        }

        double timePercentage = lowTime / stageScore.score.finalTime * 100;
        if(stageScore.score.finalTime == lowTime) {
        // if(timePercentage >= 95) {
          var weight = pointsAvailable[FantasyScoringCategory.rawTimeWins] ?? FantasyScoringCategory.rawTimeWins.defaultPointsAvailable;
          scoreMap.incrementBy(FantasyScoringCategory.rawTimeWins, weight / stageCount);
          countMap.incrementBy(FantasyScoringCategory.rawTimeWins, 1);
        }
        else if(timePercentage >= 90) {
          var weight = pointsAvailable[FantasyScoringCategory.rawTimeTop10Percents] ?? FantasyScoringCategory.rawTimeTop10Percents.defaultPointsAvailable;
          scoreMap.incrementBy(FantasyScoringCategory.rawTimeTop10Percents, weight / stageCount);
          countMap.incrementBy(FantasyScoringCategory.rawTimeTop10Percents, 1);
        }
        else if(timePercentage >= 75) {
          var weight = pointsAvailable[FantasyScoringCategory.rawTimeTop25Percents] ?? FantasyScoringCategory.rawTimeTop25Percents.defaultPointsAvailable;
          scoreMap.incrementBy(FantasyScoringCategory.rawTimeTop25Percents, weight / stageCount);
          countMap.incrementBy(FantasyScoringCategory.rawTimeTop25Percents, 1);
        }

        int stagePoints = _getStagePoints(stageScore.score);
        double accuracyPercentage = stagePoints / highScore * 100;
        if(stagePoints == highScore) {
        //if(accuracyPercentage >= 95) {
          var weight = pointsAvailable[FantasyScoringCategory.accuracyWins] ?? FantasyScoringCategory.accuracyWins.defaultPointsAvailable;
          scoreMap.incrementBy(FantasyScoringCategory.accuracyWins, weight / stageCount);
          countMap.incrementBy(FantasyScoringCategory.accuracyWins, 1);
        }
        else if(accuracyPercentage >= 90) {
          var weight = pointsAvailable[FantasyScoringCategory.accuracyTop10Percents] ?? FantasyScoringCategory.accuracyTop10Percents.defaultPointsAvailable;
          scoreMap.incrementBy(FantasyScoringCategory.accuracyTop10Percents, weight / stageCount);
          countMap.incrementBy(FantasyScoringCategory.accuracyTop10Percents, 1);
        }
        else if(accuracyPercentage >= 75) {
          var weight = pointsAvailable[FantasyScoringCategory.accuracyTop25Percents] ?? FantasyScoringCategory.accuracyTop25Percents.defaultPointsAvailable;
          scoreMap.incrementBy(FantasyScoringCategory.accuracyTop25Percents, weight / stageCount);
          countMap.incrementBy(FantasyScoringCategory.accuracyTop25Percents, 1);
        }

        for(var hit in stageScore.score.targetEvents.keys) {
          if(hit.matches("M") || hit.matches("NS")) {
            penaltyCount += stageScore.score.targetEvents[hit]!;
            countMap.incrementBy(FantasyScoringCategory.penalties, 1);
          }
        }

        penaltyCount += stageScore.score.penaltyEvents.values.sum;
      }

      // Points for penalties.
      var weight = pointsAvailable[FantasyScoringCategory.penalties] ?? FantasyScoringCategory.penalties.defaultPointsAvailable;
      scoreMap[FantasyScoringCategory.penalties] = weight * penaltyCount;
      countMap[FantasyScoringCategory.penalties] = penaltyCount;

      double runningScore = scoreMap.values.sum;

      if(participationPenalty < 1) {
        var weight = pointsAvailable[FantasyScoringCategory.divisionParticipationPenalty] ?? FantasyScoringCategory.divisionParticipationPenalty.defaultPointsAvailable;
        var actualScore = runningScore * participationPenalty;
        // To apply a weight, in this case, we want to reduce the difference (i.e. the total penalty) by
        // the weight.
        scoreMap[FantasyScoringCategory.divisionParticipationPenalty] = (actualScore - runningScore) * weight;
      }
      else {
        scoreMap[FantasyScoringCategory.divisionParticipationPenalty] = 0;
      }

      fantasyScores[shooter] = FantasyScore(scoreMap, counts: countMap);
    }
  }

  /// This calculates the value of a shooter's positive scoring hits only, assuming minor
  /// scoring.
  int _getStagePoints(RawScore score) {
    int totalPoints = 0;
    for(var hit in score.targetEvents.keys) {
      if(hit.matches("A")) {
        totalPoints += score.targetEvents[hit]! * 5;
      }
      else if(hit.matches("C")) {
        totalPoints += score.targetEvents[hit]! * 3;
      }
      else if(hit.matches("D")) {
        totalPoints += score.targetEvents[hit]! * 1;
      }
    }

    return totalPoints;
  }
}
