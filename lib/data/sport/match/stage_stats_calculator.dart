/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/stage_scoring.dart';
import 'package:shooting_sports_analyst/util.dart';

class StageStats {
  MatchStage stage;
  Map<String, double> eventsPer100;

  StageStats(this.stage, {this.eventsPer100 = const {}});

  @override
  String toString() {
    var buf = StringBuffer("${stageNameToString()}:\n");

    buf.write(toStringWithoutStageName());

    return buf.toString();
  }

  String stageNameToString() {
    return "Hit stats for stage ${stage.stageId}: ${stage.name}";
  }

  String toStringWithoutStageName([String indent = "\t"]) {
    var buf = StringBuffer();
    for(var e in eventsPer100.keys.toList()) {
      if(eventsPer100[e] == 0) continue;

      buf.write("$indent$e: ${eventsPer100[e]!.toStringAsFixed(2)}\n");
    }

    return buf.toString();
  }

  List<Widget> hitsToRows() {
    return [
      for(var e in eventsPer100.keys.toList())
        Row(mainAxisSize: MainAxisSize.max, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(e),
          Text(eventsPer100[e]!.toStringAsFixed(2)),
        ]),
    ];
  }
}

class MatchStatsCalculator {
  ShootingMatch match;

  Map<MatchStage, StageStats> stageStats = {};
  late StageStats averageStats;

  MatchStatsCalculator(this.match) {
    _calculateStats();
  }

  void _calculateStats() {
    for(var stage in match.stages) {
      Map<String, int> eventCounts = {};
      for(var shooter in match.shooters) {
        var stageScore = shooter.scores[stage];
        if(stageScore != null) {
          for(var event in stageScore.targetEvents.keys) {
            eventCounts.incrementBy(event.shortDisplayName, stageScore.targetEvents[event]!);
          }
        }
      }

      int totalEvents = eventCounts.values.sum;
      double divisor = totalEvents / 100;

      if(divisor == 0) continue;

      Map<String, double> per100 = {};
      for(var event in eventCounts.keys) {
        per100[event] = eventCounts[event]! / divisor;
      }

      stageStats[stage] = StageStats(stage, eventsPer100: per100);
    }

    // Compute weighted average of each stage's hits by MatchStage.minRounds

    Map<String, double> weightedSums = {};
    double totalWeight = 0.0;
    int totalRounds = 0;

    for (var stage in match.stages) {
      var stats = stageStats[stage];
      if (stats == null) continue;
      double weight = stage.minRounds.toDouble();
      totalWeight += weight;
      totalRounds += stage.minRounds;

      for (var event in stats.eventsPer100.keys) {
        weightedSums[event] = (weightedSums[event] ?? 0.0) + stats.eventsPer100[event]! * weight;
      }
    }

    Map<String, double> avgPer100 = {};
    if (totalWeight > 0) {
      for (var event in weightedSums.keys) {
        avgPer100[event] = weightedSums[event]! / totalWeight;
      }
    }

    averageStats = StageStats(
      MatchStage(
        stageId: -1,
        name: "Weighted Average",
        minRounds: 0,
        scoring: match.stages.isNotEmpty ? match.stages.first.scoring : PointsScoring(),
        maxPoints: totalRounds,
      ),
      eventsPer100: avgPer100,
    );

  }

  @override
  String toString() {
    var buf = StringBuffer("");
    buf.write("Match stats for ${match}\n");
    for(var s in stageStats.values) {
      buf.write(s);
    }
    buf.write("Average stats:\n");
    buf.write(averageStats);
    return buf.toString();
  }
}
