/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:math';

import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
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
  Map<MatchEntry, DbFantasyStats> calculateFantasyStats(ShootingMatch match, {
    bool byDivision = true,
    List<MatchEntry>? entries,
  }) {
    Map<MatchEntry, DbFantasyStats> fantasyStats = {};

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
    required Map<MatchEntry, DbFantasyStats> fantasyStats,
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
      var stats = DbFantasyStats();
      stats.stageCount = stageCount;

      var score = scores[shooter]!;

      // int totalPoints = 0;
      int penaltyCount = 0;

      // Points for finish percentage.
      stats.finishPercentage = score.ratio;

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
          stats.stageWins += 1;
        }
        else if(stageScore.percentage >= 90) {
          stats.stageTop10Percents += 1;
        }
        else if(stageScore.percentage >= 75) {
          stats.stageTop25Percents += 1;
        }

        double timePercentage = lowTime / stageScore.score.finalTime * 100;
        if(stageScore.score.finalTime == lowTime) {
        // if(timePercentage >= 95) {
          stats.rawTimeWins += 1;
        }
        else if(timePercentage >= 90) {
          stats.rawTimeTop10Percents += 1;
        }
        else if(timePercentage >= 75) {
          stats.rawTimeTop25Percents += 1;
        }

        int stagePoints = _getStagePoints(stageScore.score);
        double accuracyPercentage = stagePoints / highScore * 100;
        if(stagePoints == highScore) {
        //if(accuracyPercentage >= 95) {
          stats.accuracyWins += 1;
        }
        else if(accuracyPercentage >= 90) {
          stats.accuracyTop10Percents += 1;
        }
        else if(accuracyPercentage >= 75) {
          stats.accuracyTop25Percents += 1;
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
      stats.penalties += penaltyCount;

      if(participationPenalty < 1) {
        stats.divisionParticipationPenalty = participationPenalty;
      }
      else {
        stats.divisionParticipationPenalty = 1;
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
    required Map<MatchEntry, DbFantasyStats> stats,
    FantasyPointsAvailable pointsAvailable = FantasyScoringCategory.defaultCategoryPoints,
  }) {
    Map<MatchEntry, FantasyScore> fantasyScores = {};

    for(var entry in stats.keys) {
      var fantasyStats = stats[entry]!;
      fantasyScores[entry] = calculateFantasyScore(stats: fantasyStats, pointsAvailable: pointsAvailable);
    }

    return fantasyScores;

  }
}
