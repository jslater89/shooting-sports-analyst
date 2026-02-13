/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class TiesCommand extends DbOneoffCommand {
  TiesCommand(super.db);

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var project = await db.getRatingProjectByName("L2s Main");
    if(project == null) {
      console.print("Project not found");
      return;
    }
    var divisions = uspsaSport.divisions.values.toList();
    var matchPointers = project.matchPointers;
    console.print("Found ${matchPointers.length} matches");
    LabeledProgressBar matchProgressBar = LabeledProgressBar(maxValue: matchPointers.length, canHaveErrors: true);
    int stageTiesWithSameHits = 0;
    int stageTiesWithDifferentHits = 0;
    int totalStageScores = 0;

    /// Per-competitor-count tracking for "given n competitors, what are the odds of a tie?"
    /// Maps competitor count -> _TieStats
    Map<int, _TieStats> hitFactorTiesByN = {};
    Map<int, _TieStats> rawTimeTiesByN = {};
    Map<Division, List<int>> participantsByDivision = {};

    for(var pointer in matchPointers) {
      var dbMatchRes = await pointer.getDbMatch(db);
      if(dbMatchRes.isErr()) {
        console.print("Error getting match: ${dbMatchRes.unwrapErr()}");
        continue;
      }
      var dbMatch = dbMatchRes.unwrap();
      var matchRes = dbMatch.hydrateSync(useCache: true);
      if(matchRes.isErr()) {
        console.print("Error hydrating match: ${matchRes.unwrapErr()}");
        continue;
      }
      var match = matchRes.unwrap();
      matchProgressBar.tick("Processing match: ${dbMatch.eventName}");
      for(var division in divisions) {
        var scores = match.getScoresFromFilters(FilterSet.forDivision(uspsaSport, division));
        if(scores.isNotEmpty) {
          participantsByDivision.putIfAbsent(division, () => []);
          participantsByDivision[division]!.add(scores.length);
        }
        List<Map<MatchStage, RelativeStageScore>> stageScores = [];
        for(var score in scores.values) {
          for(var stage in match.stages) {
            var stageScore = score.stageScores[stage];
            if(stageScore == null) {
              continue;
            }
            stageScores.add({stage: stageScore});
          }
        }
        for(var stage in match.stages) {
          if(stage.scoring is PointsScoring) {
            continue;
          }
          /// A map of hit factors multiplied by 10000 (i.e., a double rounded to 4 decimal places)
          /// to a list of relative stage scores that generated those hit factors.
          Map<int, List<RelativeStageScore>> stageHitFactors = {};
          /// A map of raw times multiplied by 100 (i.e., centiseconds) to a list of
          /// relative stage scores with that raw time.
          Map<int, List<RelativeStageScore>> stageRawTimes = {};
          int competitorsOnStage = 0;
          for(var competitorScore in stageScores) {
            var stageScore = competitorScore[stage];
            if(stageScore == null || stageScore.isDnf || stageScore.score.hitFactor == 0) {
              continue;
            }
            competitorsOnStage += 1;
            totalStageScores += 1;
            var hitFactor = stageScore.score.hitFactor;
            var hitFactorInt = (hitFactor * 10000).round();
            stageHitFactors.addToList(hitFactorInt, stageScore);

            var rawTimeCentis = (stageScore.score.rawTime * 100).round();
            stageRawTimes.addToList(rawTimeCentis, stageScore);
          }

          if(competitorsOnStage < 2) {
            continue;
          }

          // Check for hit factor ties
          bool hasHfTie = false;
          for(var entry in stageHitFactors.entries) {
            if(entry.value.length > 1) {
              hasHfTie = true;
              var firstEntry = entry.value.first;
              var remainingEntries = entry.value.skip(1).toList();
              bool sameTimes = true;
              for(var remainingEntry in remainingEntries) {
                if(remainingEntry.score.finalTime != firstEntry.score.finalTime) {
                  sameTimes = false;
                  break;
                }
              }
              if(sameTimes) {
                stageTiesWithSameHits += 1;
              }
              else {
                stageTiesWithDifferentHits += 1;
              }
            }
          }

          // Check for raw time ties
          bool hasRawTimeTie = stageRawTimes.entries.any((e) => e.value.length > 1);

          // Record per-n stats
          hitFactorTiesByN.putIfAbsent(competitorsOnStage, () => _TieStats());
          hitFactorTiesByN[competitorsOnStage]!.totalStages += 1;
          if(hasHfTie) {
            hitFactorTiesByN[competitorsOnStage]!.stagesWithTie += 1;
          }

          rawTimeTiesByN.putIfAbsent(competitorsOnStage, () => _TieStats());
          rawTimeTiesByN[competitorsOnStage]!.totalStages += 1;
          if(hasRawTimeTie) {
            rawTimeTiesByN[competitorsOnStage]!.stagesWithTie += 1;
          }
        }
      }
    }

    matchProgressBar.complete();
    console.print("Total stage scores: $totalStageScores");
    console.print("Stage HF ties with same hits: $stageTiesWithSameHits");
    console.print("Stage HF ties with different hits: $stageTiesWithDifferentHits");

    console.print("");
    console.print("=== Participants by Division ===");
    _printDivisionStats(console, participantsByDivision);

    console.print("");
    console.print("=== Hit Factor Tie Probability by Competitor Count ===");
    console.print("(Given n competitors on a stage, how often does at least one HF tie occur?)");
    _printTieTable(console, hitFactorTiesByN);

    console.print("");
    console.print("=== Raw Time Tie Probability by Competitor Count ===");
    console.print("(Given n competitors on a stage, how often does at least one raw time tie occur?)");
    _printTieTable(console, rawTimeTiesByN);
  }

  void _printDivisionStats(Console console, Map<Division, List<int>> participantsByDivision) {
    var divisionsByMedian = [...participantsByDivision.entries]
      ..sort((a, b) => _median(b.value).compareTo(_median(a.value)));

    console.print(
      "${"Division".padRight(20)}  "
      "${"Matches".padLeft(8)}  "
      "${"Mean".padLeft(8)}  "
      "${"Median".padLeft(8)}  "
      "${"StdDev".padLeft(8)}  "
      "${"Min".padLeft(6)}  "
      "${"Max".padLeft(6)}",
    );
    console.print(
      "${"-" * 20}  ${"-" * 8}  ${"-" * 8}  ${"-" * 8}  ${"-" * 8}  ${"-" * 6}  ${"-" * 6}",
    );
    for(var entry in divisionsByMedian) {
      var name = entry.key.name;
      var counts = entry.value;
      if(counts.isEmpty) continue;

      var mean = counts.reduce((a, b) => a + b) / counts.length;
      var median = _median(counts);
      var stddev = _stddev(counts, mean);
      var minVal = counts.reduce(min);
      var maxVal = counts.reduce(max);

      console.print(
        "${name.padRight(20)}  "
        "${counts.length.toString().padLeft(8)}  "
        "${mean.toStringAsFixed(1).padLeft(8)}  "
        "${median.toStringAsFixed(1).padLeft(8)}  "
        "${stddev.toStringAsFixed(1).padLeft(8)}  "
        "${minVal.toString().padLeft(6)}  "
        "${maxVal.toString().padLeft(6)}",
      );
    }
  }

  double _median(List<int> values) {
    var sorted = [...values]..sort();
    if(sorted.length % 2 == 1) {
      return sorted[sorted.length ~/ 2].toDouble();
    }
    else {
      return (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2.0;
    }
  }

  double _stddev(List<int> values, double mean) {
    var sumSquaredDiffs = values.fold<double>(0.0, (sum, v) => sum + (v - mean) * (v - mean));
    return sqrt(sumSquaredDiffs / values.length);
  }

  void _printTieTable(Console console, Map<int, _TieStats> statsByN, {int bucketSize = 10}) {
    // Aggregate into buckets
    Map<int, _TieStats> buckets = {};
    for(var entry in statsByN.entries) {
      var bucketKey = (entry.key ~/ bucketSize) * bucketSize;
      buckets.putIfAbsent(bucketKey, () => _TieStats());
      buckets[bucketKey]!.totalStages += entry.value.totalStages;
      buckets[bucketKey]!.stagesWithTie += entry.value.stagesWithTie;
    }

    var sortedKeys = [...buckets.keys]..sort();
    console.print("${"N".padLeft(11)}  ${"Stages".padLeft(8)}  ${"w/ Tie".padLeft(8)}  ${"Probability".padLeft(12)}");
    console.print("${"-" * 11}  ${"-" * 8}  ${"-" * 8}  ${"-" * 12}");
    for(var bucketStart in sortedKeys) {
      var stats = buckets[bucketStart]!;
      var bucketEnd = bucketStart + bucketSize - 1;
      var label = "$bucketStart-$bucketEnd";
      var probability = stats.totalStages > 0
          ? (stats.stagesWithTie / stats.totalStages * 100).toStringAsFixed(2)
          : "0.00";
      console.print(
        "${label.padLeft(11)}  "
        "${stats.totalStages.toString().padLeft(8)}  "
        "${stats.stagesWithTie.toString().padLeft(8)}  "
        "${probability.padLeft(11)}%",
      );
    }
  }

  @override
  String get key => "TIES";
  @override
  String get title => "Ties";
}

class _TieStats {
  int totalStages = 0;
  int stagesWithTie = 0;
}
