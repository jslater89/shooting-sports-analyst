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
    var oldEntry = oldScores.keys.firstWhereOrNull((e) => e.sourceId != null ? e.sourceId == entry.sourceId : e.entryId == entry.entryId);

    if(oldEntry == null) {
      _log.w("Failed to find an old entry for ${entry.getName(suffixes: false)} (${entry.sourceId} ${entry.entryId})");
      continue;
    }

    var oldScore = oldScores[oldEntry];
    var newScore = newScores[entry]!;

    if(oldScore == null) {
      _log.w("Failed to find an old score for ${entry.getName(suffixes: false)} (${entry.sourceId} ${entry.entryId})");
      continue;
    }

    var change = MatchScoreChange(oldScore: oldScore, newScore: newScore);
    var nonzeroOldScores = oldScore.stageScores.values.where((s) => !s.score.dnf);
    var nonzeroNewScores = newScore.stageScores.values.where((s) => !s.score.dnf);
    for(var stage in oldScore.stageScores.keys) {
      var newStage = newScore.stageScores.keys.firstWhereOrNull((s) => s.stageId == stage.stageId);

      if(newStage == null) {
        _log.w("Unable to locate new stage score for ${stage.name} (${stage.stageId})");
        continue;
      }
      var oldStageScore = oldScore.stageScores[stage];
      var newStageScore = newScore.stageScores[newStage];

      // If the new score is not null, and it is newer than the old score, and the scores
      // have different times or hits, then it counts as a change.

      var hasNewScore = newStageScore != null;
      var newScoreHasModifiedTime = hasNewScore && newStageScore.score.modified != null;
      var isNewer = newScoreHasModifiedTime && (oldStageScore == null || newStageScore.score.modified!.isAfter(oldStageScore.score.modified ?? DateTime(0)));
      var isDifferent = hasNewScore && !newStageScore.score.equivalentTo(oldStageScore?.score);

      if(isNewer && isDifferent) {
        change.stageScoreChanges[stage] = StageScoreChange(oldScore: oldStageScore, newScore: newStageScore);
      }
      // If the new score is nonzero, and the old score is zero, and we have new scores, but we didn't detect newer/different, then we missed it somehow.
      else if(nonzeroNewScores.contains(newStageScore) && !nonzeroOldScores.contains(oldStageScore) && nonzeroOldScores.length != nonzeroNewScores.length) {
        _log.w("Failed to detect stage score change for ${entry.name} (${entry.sourceId} ${entry.entryId}) on stage ${stage.name} (${stage.stageId})");
        _log.i("New score: $hasNewScore, new score has modified time: $newScoreHasModifiedTime, is newer: $isNewer, is different: $isDifferent");
      }
    }

    if(change.stageScoreChanges.isNotEmpty) {
      changes[entry] = change;
    }
    if(nonzeroNewScores.isNotEmpty && nonzeroOldScores.length != nonzeroOldScores.length) {
      _log.vv("Nonzero stages scores for ${entry.name} (new/old): ${nonzeroNewScores.length}/${nonzeroOldScores.length}");
    }
  }

  return changes;
}