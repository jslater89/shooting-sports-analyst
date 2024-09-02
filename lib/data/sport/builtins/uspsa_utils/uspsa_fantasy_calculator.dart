import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

class USPSAFantasyScoringCalculator implements FantasyScoringCalculator<USPSAFantasyScoringCategory> {
  const USPSAFantasyScoringCalculator();

  @override
  Map<MatchEntry, FantasyScore<USPSAFantasyScoringCategory>> calculateFantasyScores(ShootingMatch match) {
    int stageCount = match.stages.length;

    // Calculate participation penalty ratios, based on the rules in [USPSAFantasyScoringCategory.divisionParticipationPenalty].
    Map<Division, double> participationPenaltyRatios = {};
    Map<Division, bool> eligible = {};
    Map<Division, int> shooterCounts = {};
    Map<Division, int> gmCounts = {};
    for(var division in match.sport.divisions.values) {
      shooterCounts[division] = 0;
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

    for(var division in match.sport.divisions.values) {
      if(eligible[division] == true) {
        participationPenaltyRatios[division] = 1;
      }
      else {
        participationPenaltyRatios[division] = min(1, shooterCounts[division]! / shooterCounts[smallestEligibleDivision]!);
      }
    }

    Map<MatchEntry, FantasyScore<USPSAFantasyScoringCategory>> fantasyScores = {};
    int availablePoints = match.stages.map((e) => e.maxPoints).sum;
    for(var division in match.sport.divisions.values) {
      var participationPenalty = participationPenaltyRatios[division]!;
      var shooters = match.filterShooters(divisions: [division]);
      var scores = match.getScores(shooters: shooters);

      Map<MatchStage, double> lowTimes = {};
      Map<MatchStage, int> highPoints = {};

      for(var stage in match.stages) {
        lowTimes[stage] = double.infinity;
        highPoints[stage] = 0;
      }

      for(var stage in match.stages) {
        for(var score in scores.values) {
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
        var scoreMap = <USPSAFantasyScoringCategory, double>{};
        for(var category in USPSAFantasyScoringCategory.values) {
          scoreMap[category] = 0;
        }
        var score = scores[shooter]!;

        int totalPoints = 0;
        int penaltyCount = 0;

        // Points for finish percentage.
          scoreMap[USPSAFantasyScoringCategory.finishPercentage] = score.percentage;

        for(var stage in match.stages) {
          var stageScore = score.stageScores[stage];
          if(stageScore == null) {
            continue;
          }
          int highScore = highPoints[stage]!;
          double lowTime = lowTimes[stage]!;

          // Points for stage wins, top 10%, and top 25%.
          if(stageScore.place == 1) {
            scoreMap.incrementBy(USPSAFantasyScoringCategory.stageWins, 100 / stageCount);
          }
          else if(stageScore.percentage >= 90) {
            scoreMap.incrementBy(USPSAFantasyScoringCategory.stageTop10Percents, 75 / stageCount);
          }
          else if(stageScore.percentage >= 75) {
            scoreMap.incrementBy(USPSAFantasyScoringCategory.stageTop25Percents, 50 / stageCount);
          }

          double timePercentage = lowTime / stageScore.score.finalTime * 100;
          if(stageScore.score.finalTime == lowTime) {
            scoreMap.incrementBy(USPSAFantasyScoringCategory.rawTimeWins, 100 / stageCount);
          }
          else if(timePercentage >= 90) {
            scoreMap.incrementBy(USPSAFantasyScoringCategory.rawTimeTop10Percents, 75 / stageCount);
          }
          else if(timePercentage >= 75) {
            scoreMap.incrementBy(USPSAFantasyScoringCategory.rawTimeTop25Percents, 50 / stageCount);
          }

          int stagePoints = _getStagePoints(stageScore.score);
          double accuracyPercentage = stagePoints / highScore * 100;
          if(stagePoints == highScore) {
            scoreMap.incrementBy(USPSAFantasyScoringCategory.accuracyWins, 100 / stageCount);
          }
          else if(accuracyPercentage >= 90) {
            scoreMap.incrementBy(USPSAFantasyScoringCategory.accuracyTop10Percents, 75 / stageCount);
          }
          else if(accuracyPercentage >= 75) {
            scoreMap.incrementBy(USPSAFantasyScoringCategory.accuracyTop25Percents, 50 / stageCount);
          }

          for(var hit in stageScore.score.targetEvents.keys) {
            if(hit.matches("M") || hit.matches("NS")) {
              penaltyCount += stageScore.score.targetEvents[hit]!;
            }
          }

          penaltyCount += stageScore.score.penaltyEvents.values.sum;
        }

        // Points for penalties.
        scoreMap[USPSAFantasyScoringCategory.penalties] = -5.0 * penaltyCount;

        double runningScore = scoreMap.values.sum;

        if(participationPenalty < 1) {
          var actualScore = runningScore * participationPenalty;
          scoreMap[USPSAFantasyScoringCategory.divisionParticipationPenalty] = actualScore - runningScore;
        }
        else {
          scoreMap[USPSAFantasyScoringCategory.divisionParticipationPenalty] = 0;
        }

        fantasyScores[shooter] = FantasyScore(scoreMap);
      }
    }

    return fantasyScores;
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

/// USPSA fantasy scoring categories. A full scoring positive category should be worth 100 points.
enum USPSAFantasyScoringCategory {
  /// Points equal to finish percentage.
  finishPercentage,

  // Points for stage wins, top 10%, and top 25% finishes. No double dipping.
  // If a shooter wins, they aren't eligible for top 10% or top 25% points.

  /// 100/N points per stage win, where N is the number of stages.
  stageWins,
  /// 75/N points per stage top 10 finish, where N is the number of stages.
  stageTop10Percents,
  /// 50/N points per stage top 25 finish, where N is the number of stages.
  stageTop25Percents,

  // Points for raw time champs. Same double dipping rules as stage scores.

  /// 100/N points per stage raw time win, where N is the number of stages.
  rawTimeWins,

  /// 75/N points per stage raw time top 10 finish, where N is the number of stages.
  rawTimeTop10Percents,

  /// 50/N points per stage raw time top 25 finish, where N is the number of stages.
  rawTimeTop25Percents,

  // Points for accuracy. Same double dipping rules as stage scores.

  /// 100/N points per stage accuracy win, where N is the number of stages.
  accuracyWins,

  /// 75/N points per stage accuracy top 10 finish, where N is the number of stages.
  accuracyTop10Percents,

  /// 50/N points per stage accuracy top 25 finish, where N is the number of stages.
  accuracyTop25Percents,

  /// -5 points per miss, no-shoot, or procedural.
  penalties,

  /// A negative number to account for division participation, which is calculated
  /// as a percentage of the sum of the other components.
  /// 
  /// If a division is the largest, or if it has at least 25 shooters and at least 1
  /// GM, plus at least 1 GM per 50 shooters total, it gets no penalty.
  /// 
  /// Otherwise, it gets a penalty of (sum of other components) * (proportion of smallest
  /// division eligible for full points).
  divisionParticipationPenalty;

  @override
  String toString() {
    return switch(this) {
      USPSAFantasyScoringCategory.finishPercentage => "Finish Percentage",
      USPSAFantasyScoringCategory.stageWins => "Stage Wins",
      USPSAFantasyScoringCategory.stageTop10Percents => "Stage Top 10%",
      USPSAFantasyScoringCategory.stageTop25Percents => "Stage Top 25%",
      USPSAFantasyScoringCategory.rawTimeWins => "Raw Time Wins",
      USPSAFantasyScoringCategory.rawTimeTop10Percents => "Raw Time Top 10%",
      USPSAFantasyScoringCategory.rawTimeTop25Percents => "Raw Time Top 25%",
      USPSAFantasyScoringCategory.accuracyWins => "Accuracy Wins",
      USPSAFantasyScoringCategory.accuracyTop10Percents => "Accuracy Top 10%",
      USPSAFantasyScoringCategory.accuracyTop25Percents => "Accuracy Top 25%",
      USPSAFantasyScoringCategory.penalties => "Penalties",
      USPSAFantasyScoringCategory.divisionParticipationPenalty => "Division Participation Penalty",
    };
  }
}