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
  const USPSAFantasyScoringCalculator();

  // TODO: it may be possible to lift some of this to the base class
  // But some of it is still USPSA-specific, participation penalty in particular
  @override
  Map<MatchEntry, FantasyStats> calculateFantasyStats(ShootingMatch match, {
    bool byDivision = true,
    List<MatchEntry>? entries,
  }) {
    Map<MatchEntry, FantasyStats> fantasyStats = {};

    // Calculate participation penalty ratios.
    //
    // A division gets full points if it has at least 25 shooters and at least 1 GM,
    // is bigger than any division with at least 25 shooters and at least 1 GM,
    // and has at least 1 GM per 50 shooters. If no division is otherwise eligible,
    // the largest division is eligible for full points, and all others receive
    // the participation penalty.
    //
    // Otherwise, it gets a penalty of (sum of other components) * (proportion of smallest
    // division eligible for full points).
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
          fantasyStats: fantasyStats,
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
        fantasyStats: fantasyStats,
      );
    }
    else {
      throw ArgumentError("byDivision must be true or entries must be provided");
    }

    return fantasyStats;
  }

  void _calculate({
    required ShootingMatch match,
    required Map<MatchEntry, RelativeMatchScore> scores,
    required double participationPenalty,
    required Map<MatchEntry, FantasyStats> fantasyStats,
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
      var stats = FantasyStats(stageCount: stageCount);

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
      stats.doubleStats[FantasyScoringCategory.finishPercentage] = score.ratio;

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
          stats.integerStats.increment(FantasyScoringCategory.stageWins);
        }
        else if(stageScore.percentage >= 90) {
          stats.integerStats.increment(FantasyScoringCategory.stageTop10Percents);
        }
        else if(stageScore.percentage >= 75) {
          stats.integerStats.increment(FantasyScoringCategory.stageTop25Percents);
        }

        double timePercentage = lowTime / stageScore.score.finalTime * 100;
        if(stageScore.score.finalTime == lowTime) {
        // if(timePercentage >= 95) {
          stats.integerStats.increment(FantasyScoringCategory.rawTimeWins);
        }
        else if(timePercentage >= 90) {
          stats.integerStats.increment(FantasyScoringCategory.rawTimeTop10Percents);
        }
        else if(timePercentage >= 75) {
          stats.integerStats.increment(FantasyScoringCategory.rawTimeTop25Percents);
        }

        int stagePoints = _getStagePoints(stageScore.score);
        double accuracyPercentage = stagePoints / highScore * 100;
        if(stagePoints == highScore) {
        //if(accuracyPercentage >= 95) {
          stats.integerStats.increment(FantasyScoringCategory.accuracyWins);
        }
        else if(accuracyPercentage >= 90) {
          stats.integerStats.increment(FantasyScoringCategory.accuracyTop10Percents);
        }
        else if(accuracyPercentage >= 75) {
          stats.integerStats.increment(FantasyScoringCategory.accuracyTop25Percents);
        }

        for(var hit in stageScore.score.targetEvents.keys) {
          if(hit.matches("M") || hit.matches("NS")) {
            var count = stageScore.score.targetEvents[hit]!;
            if(count > 0) {
              penaltyCount += count;
            }
          }
        }

        penaltyCount += stageScore.score.penaltyEventCount;
      }

      // Points for procedurals/other non-hit penalties.
      stats.integerStats.incrementBy(FantasyScoringCategory.penalties, penaltyCount);

      if(participationPenalty < 1) {
        stats.doubleStats[FantasyScoringCategory.divisionParticipationPenalty] = participationPenalty;
      }
      else {
        stats.doubleStats[FantasyScoringCategory.divisionParticipationPenalty] = 1;
      }

      fantasyStats[shooter] = stats;
    }
  }

  /// This calculates the value of a shooter's positive scoring hits only, assuming minor
  /// scoring.
  int _getStagePoints(RawScore score) {
    return score.getTotalPoints(countPenalties: false, includeTargetPenalties: false);
  }

  @override
  Map<MatchEntry, FantasyScore> calculateFantasyScores({
    required Map<MatchEntry, FantasyStats> stats,
    Map<FantasyScoringCategory, double> pointsAvailable = FantasyScoringCategory.defaultCategoryPoints,
  }) {
    Map<MatchEntry, FantasyScore> fantasyScores = {};

    for(var entry in stats.keys) {
      var fantasyStats = stats[entry]!;
      Map<FantasyScoringCategory, double> scoreMap = {};
      Map<FantasyScoringCategory, int> countMap = {};

      // Stage percentage
      var finishPoints = pointsAvailable[FantasyScoringCategory.finishPercentage]!;
      scoreMap[FantasyScoringCategory.finishPercentage] = fantasyStats.doubleStats[FantasyScoringCategory.finishPercentage]! * finishPoints;
      countMap[FantasyScoringCategory.finishPercentage] = 1;

      // Stage wins
      var stageWinPoints = pointsAvailable[FantasyScoringCategory.stageWins]!;
      int count = fantasyStats.integerStats[FantasyScoringCategory.stageWins] ?? 0;
      scoreMap[FantasyScoringCategory.stageWins] = (stageWinPoints / fantasyStats.stageCount) * count;
      countMap[FantasyScoringCategory.stageWins] = count;

      // Stage top 10%
      var stageTop10Points = pointsAvailable[FantasyScoringCategory.stageTop10Percents]!;
      count = fantasyStats.integerStats[FantasyScoringCategory.stageTop10Percents] ?? 0;
      scoreMap[FantasyScoringCategory.stageTop10Percents] = (stageTop10Points / fantasyStats.stageCount) * count;
      countMap[FantasyScoringCategory.stageTop10Percents] = count;

      // Stage top 25%
      var stageTop25Points = pointsAvailable[FantasyScoringCategory.stageTop25Percents]!;
      count = fantasyStats.integerStats[FantasyScoringCategory.stageTop25Percents] ?? 0;
      scoreMap[FantasyScoringCategory.stageTop25Percents] = (stageTop25Points / fantasyStats.stageCount) * count;
      countMap[FantasyScoringCategory.stageTop25Percents] = count;

      // Raw time wins
      var rawTimeWinPoints = pointsAvailable[FantasyScoringCategory.rawTimeWins]!;
      count = fantasyStats.integerStats[FantasyScoringCategory.rawTimeWins] ?? 0;
      scoreMap[FantasyScoringCategory.rawTimeWins] = (rawTimeWinPoints / fantasyStats.stageCount) * count;
      countMap[FantasyScoringCategory.rawTimeWins] = count;

      // Raw time top 10%
      var rawTimeTop10Points = pointsAvailable[FantasyScoringCategory.rawTimeTop10Percents]!;
      count = fantasyStats.integerStats[FantasyScoringCategory.rawTimeTop10Percents] ?? 0;
      scoreMap[FantasyScoringCategory.rawTimeTop10Percents] = (rawTimeTop10Points / fantasyStats.stageCount) * count;
      countMap[FantasyScoringCategory.rawTimeTop10Percents] = count;

      // Raw time top 25%
      var rawTimeTop25Points = pointsAvailable[FantasyScoringCategory.rawTimeTop25Percents]!;
      count = fantasyStats.integerStats[FantasyScoringCategory.rawTimeTop25Percents] ?? 0;
      scoreMap[FantasyScoringCategory.rawTimeTop25Percents] = (rawTimeTop25Points / fantasyStats.stageCount) * count;
      countMap[FantasyScoringCategory.rawTimeTop25Percents] = count;

      // Accuracy wins
      var accuracyWinPoints = pointsAvailable[FantasyScoringCategory.accuracyWins]!;
      count = fantasyStats.integerStats[FantasyScoringCategory.accuracyWins] ?? 0;
      scoreMap[FantasyScoringCategory.accuracyWins] = (accuracyWinPoints / fantasyStats.stageCount) * count;
      countMap[FantasyScoringCategory.accuracyWins] = count;

      // Accuracy top 10%
      var accuracyTop10Points = pointsAvailable[FantasyScoringCategory.accuracyTop10Percents]!;
      count = fantasyStats.integerStats[FantasyScoringCategory.accuracyTop10Percents] ?? 0;
      scoreMap[FantasyScoringCategory.accuracyTop10Percents] = (accuracyTop10Points / fantasyStats.stageCount) * count;
      countMap[FantasyScoringCategory.accuracyTop10Percents] = count;

      // Accuracy top 25%
      var accuracyTop25Points = pointsAvailable[FantasyScoringCategory.accuracyTop25Percents]!;
      count = fantasyStats.integerStats[FantasyScoringCategory.accuracyTop25Percents] ?? 0;
      scoreMap[FantasyScoringCategory.accuracyTop25Percents] = (accuracyTop25Points / fantasyStats.stageCount) * count;
      countMap[FantasyScoringCategory.accuracyTop25Percents] = count;

      // Penalties
      var penaltyCount = fantasyStats.integerStats[FantasyScoringCategory.penalties] ?? 0;
      var pointsPerPenalty = pointsAvailable[FantasyScoringCategory.penalties]!;
      scoreMap[FantasyScoringCategory.penalties] = penaltyCount * pointsPerPenalty;
      countMap[FantasyScoringCategory.penalties] = penaltyCount;

      // Division participation penalty
      var divisionParticipationPenalty = fantasyStats.doubleStats[FantasyScoringCategory.divisionParticipationPenalty]!;
      if(divisionParticipationPenalty < 1) {
        var runningScore = scoreMap.values.sum;
        var actualScore = runningScore * divisionParticipationPenalty;
        scoreMap[FantasyScoringCategory.divisionParticipationPenalty] = (actualScore - runningScore);
      }
      else {
        scoreMap[FantasyScoringCategory.divisionParticipationPenalty] = 0;
      }

      fantasyScores[entry] = FantasyScore(scoreMap, counts: countMap);
    }

    return fantasyScores;

  }
}
