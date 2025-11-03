/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
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
    for(var pointer in matchPointers) {
      var dbMatchRes = await pointer.getDbMatch(db);
      if(dbMatchRes.isErr()) {
        console.print("Error getting match: ${dbMatchRes.unwrapErr()}");
        continue;
      }
      var dbMatch = dbMatchRes.unwrap();
      var matchRes = await dbMatch.hydrate(useCache: true);
      if(matchRes.isErr()) {
        console.print("Error hydrating match: ${matchRes.unwrapErr()}");
        continue;
      }
      var match = matchRes.unwrap();
      matchProgressBar.tick("Processing match: ${dbMatch.eventName}");
      for(var division in divisions) {
        var scores = match.getScoresFromFilters(FilterSet.forDivision(uspsaSport, division));
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
          /// to a map of relative stage scores that generated those hit factors.
          Map<int, List<RelativeStageScore>> stageHitFactors = {};
          for(var competitorScore in stageScores) {
            var stageScore = competitorScore[stage];
            if(stageScore == null || stageScore.isDnf || stageScore.score.hitFactor == 0) {
              continue;
            }
            totalStageScores += 1;
            var hitFactor = stageScore.score.hitFactor;
            var hitFactorInt = (hitFactor * 10000).round();
            stageHitFactors.addToList(hitFactorInt, stageScore);
          }

          // Any entry in stageHitFactors with more than one score is a tie.
          for(var entry in stageHitFactors.entries) {
            if(entry.value.length > 1) {
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
        }
      }
    }

    matchProgressBar.complete();
    console.print("Total stage scores: $totalStageScores");
    console.print("Stage ties with same hits: $stageTiesWithSameHits");
    console.print("Stage ties with different hits: $stageTiesWithDifferentHits");
  }

  @override
  String get key => "TIES";
  @override
  String get title => "Ties";
}
