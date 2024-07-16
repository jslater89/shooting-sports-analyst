import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/util.dart';

class StageStats {
  MatchStage stage;
  Map<String, double> eventsPer32;

  StageStats(this.stage, {this.eventsPer32 = const {}});

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
    for(var e in eventsPer32.keys.toList()) {
      if(eventsPer32[e] == 0) continue;

      buf.write("$indent$e: ${eventsPer32[e]!.toStringAsFixed(2)}\n");
    }

    return buf.toString();
  }

  List<Widget> hitsToRows() {
    return [
      for(var e in eventsPer32.keys.toList())
        Row(mainAxisSize: MainAxisSize.max, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(e),
          Text(eventsPer32[e]!.toStringAsFixed(2)),
        ]),
    ];
  }
}

class MatchStatsCalculator {
  ShootingMatch match;

  Map<MatchStage, StageStats> stageStats = {};

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
      double divisor = totalEvents / 32;

      if(divisor == 0) continue;

      Map<String, double> per32 = {};
      for(var event in eventCounts.keys) {
        per32[event] = eventCounts[event]! / divisor;
      }

      stageStats[stage] = StageStats(stage, eventsPer32: per32);
    }
  }

  @override
  String toString() {
    var buf = StringBuffer("");
    buf.write("Match stats for ${match}\n");
    for(var s in stageStats.values) {
      buf.write(s);
    }
    return buf.toString();
  }
}