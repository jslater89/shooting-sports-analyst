/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/util.dart';

enum ScoreFunctionType {
  allOrNothing,
  linearMarginOfVictory;

  String get uiLabel {
    switch(this) {
      case ScoreFunctionType.allOrNothing:
        return "All or nothing";
      case ScoreFunctionType.linearMarginOfVictory:
        return "Linear margin of victory";
    }
  }
}

sealed class Glicko2ScoreFunction {
  const Glicko2ScoreFunction();
  double calculateScore(double shooterRatio, double opponentRatio);
}

/// A score function that gives a score of 1.0 for a win, 0.0 for a loss, and 0.5 for a tie.
class AllOrNothingScoreFunction extends Glicko2ScoreFunction {
  const AllOrNothingScoreFunction();

  @override
  double calculateScore(double shooterRatio, double opponentRatio) {
    if(shooterRatio == opponentRatio) return 0.5;
    if(shooterRatio > opponentRatio) return 1.0;
    return 0.0;
  }
}

/// A score function that gives a score between 0 and 1 based on the margin of victory.
class LinearMarginOfVictoryScoreFunction extends Glicko2ScoreFunction {
  final double perfectVictoryDifference;

  const LinearMarginOfVictoryScoreFunction({this.perfectVictoryDifference = 0.25});

  @override
  double calculateScore(double shooterRatio, double opponentRatio) {
    // The loser's score is always expressed in terms of the winner's; scale
    // the range based on the winner's ratio.
    var higherRatio = max(shooterRatio, opponentRatio);
    var topOfRange = opponentRatio + (perfectVictoryDifference * higherRatio);
    var bottomOfRange = opponentRatio - (perfectVictoryDifference * higherRatio);
    return lerpAroundCenter(
      value: shooterRatio,
      center: opponentRatio,
      rangeMin: bottomOfRange,
      rangeMax: topOfRange,
      minOut: 0.0,
      centerOut: 0.5,
      maxOut: 1.0,
    );
  }
}
