/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';

SSALogger _log = SSALogger("ScoreChangeCalculator");

class MatchScoreChange {
  RelativeMatchScore oldScore;
  RelativeMatchScore newScore;

  double get ratioChange => newScore.ratio - oldScore.ratio;
  int get placeChange => oldScore.place - newScore.place;

  MatchScoreChange({required this.oldScore, required this.newScore});

  Map<MatchStage, StageScoreChange> stageScoreChanges = {};
}

class StageScoreChange {
  RelativeStageScore? oldScore;
  RelativeStageScore newScore;

  StageScoreChange({required this.oldScore, required this.newScore});

  double get ratioChange => oldScore == null ? 0 : newScore.ratio - oldScore!.ratio;
  int get placeChange => oldScore == null ? 0 : oldScore!.place - newScore.place;
}

Map<MatchEntry, MatchScoreChange> calculateScoreChanges(Map<MatchEntry, RelativeMatchScore> oldScores, Map<MatchEntry, RelativeMatchScore> newScores) {
  var changes = <MatchEntry, MatchScoreChange>{};
  for(var entry in newScores.keys) {
    var oldEntry = oldScores.keys.firstWhereOrNull((e) => e.entryId == entry.entryId);

    if(oldEntry == null) {
      _log.w("Failed to find an old entry for ${entry.getName(suffixes: false)} (${entry.entryId})");
      continue;
    }

    var oldScore = oldScores[oldEntry];
    var newScore = newScores[entry]!;

    if(oldScore == null) {
      _log.w("Failed to find an old score for ${entry.getName(suffixes: false)} (${entry.entryId})");
      continue;
    }

    var change = MatchScoreChange(oldScore: oldScore, newScore: newScore);
    for(var stage in oldScore.stageScores.keys) {
      var newStage = newScore.stageScores.keys.firstWhereOrNull((s) => s.stageId == stage.stageId);

      if(newStage == null) {
        // Observed when using the forward/back timewarp buttons from before a match to during a match.
        continue;
      }
      var oldStageScore = oldScore.stageScores[stage];
      var newStageScore = newScore.stageScores[newStage];

      // If the new score is not null, and it is newer than the old score, and the scores
      // have different times or hits, then it counts as a change.
      if(newStageScore != null 
          && newStageScore.score.modified != null 
          && (oldStageScore == null || newStageScore.score.modified!.isAfter(oldStageScore.score.modified ?? DateTime(0)))
          && !newStageScore.score.equivalentTo(oldStageScore?.score)
      ) {
        change.stageScoreChanges[stage] = StageScoreChange(oldScore: oldStageScore, newScore: newStageScore);
      }
    }

    if(change.stageScoreChanges.isNotEmpty) {
      changes[entry] = change;
    }
  }

  return changes;
}