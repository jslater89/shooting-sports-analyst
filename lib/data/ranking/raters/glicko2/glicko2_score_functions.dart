/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/util.dart';

enum ScoreFunctionType {
  allOrNothing,
  linearMarginOfVictory,
  logisticMarginOfVictory;

  String get uiLabel {
    switch(this) {
      case ScoreFunctionType.allOrNothing:
        return "All or nothing";
      case ScoreFunctionType.linearMarginOfVictory:
        return "Linear margin of victory";
      case ScoreFunctionType.logisticMarginOfVictory:
        return "Logistic margin of victory";
    }
  }
}

sealed class Glicko2ScoreFunction {
  const Glicko2ScoreFunction();
  double calculateScore(double shooterRatio, double opponentRatio);

  /// Whether the score function is reversible, i.e. can generate a margin
  /// of victory from an expected score and a winner's score in ratio space.
  bool get reversible => false;

  /// Whether the score function is only reversible in the linear region of
  /// the expected score function.
  bool get onlyReversibleInLinearE => true;
  double calculateVictoryMargin(double expectedScore, double winnerRatio);
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

  double calculateVictoryMargin(double expectedScore, double winnerRatio) {
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

  @override
  bool get reversible => true;

  @override
  bool get onlyReversibleInLinearE => true;

  /// Reverse the score function, taking a loser's expected score and a winner's ratio and returning
  /// the margin of victory for the winner.
  @override
  double calculateVictoryMargin(double expectedScore, double winnerRatio) {
    var topOfOutput = winnerRatio + (perfectVictoryDifference * winnerRatio);
    var bottomOfOutput = winnerRatio - (perfectVictoryDifference * winnerRatio);
    var centerOfOutput = (topOfOutput + bottomOfOutput) / 2;

    // This outputs the expected score for the loser.
    var output = lerpAroundCenter(
      value: expectedScore,
      center: 0.5,
      rangeMin: 0.0,
      rangeMax: 1.0,
      minOut: bottomOfOutput,
      centerOut: centerOfOutput,
      maxOut: topOfOutput,
    );

    // So to get the margin of victory for the winner, we need to subtract the expected score from the winner's ratio.
    return winnerRatio - output;
  }
}

/// A score function that maps ratio differences through a logistic (sigmoid) curve,
/// giving strong signal for modest wins while asymptotically approaching 0/1 for
/// large margins. Because both this and Glicko's E function are logistic, their
/// composition when reversing is approximately linear in rating difference,
/// allowing the reverse path to remain well-behaved outside E's normal linear region.
class LogisticMarginOfVictoryScoreFunction extends Glicko2ScoreFunction {
  /// Controls how quickly the score saturates as the ratio difference grows.
  /// Higher values mean faster saturation (more "all or nothing"-like);
  /// lower values spread the curve out over a wider ratio range.
  final double steepness;

  const LogisticMarginOfVictoryScoreFunction({this.steepness = 8.0});

  @override
  double calculateScore(double shooterRatio, double opponentRatio) {
    var higherRatio = max(shooterRatio, opponentRatio);
    if(higherRatio == 0) return 0.5;
    var normalizedDelta = (shooterRatio - opponentRatio) / higherRatio;
    return 1.0 / (1.0 + exp(-steepness * normalizedDelta));
  }

  @override
  bool get reversible => true;

  @override
  bool get onlyReversibleInLinearE => false;

  /// Reverse the score function, taking a loser's expected score and a winner's
  /// ratio and returning the margin of victory for the winner.
  ///
  /// This is the logit (inverse sigmoid): given a score s, the normalized delta
  /// is ln(s / (1 - s)) / k, and the margin is the un-normalized absolute difference.
  @override
  double calculateVictoryMargin(double expectedScore, double winnerRatio) {
    var clampedScore = expectedScore.clamp(1e-10, 1.0 - 1e-10);
    var logit = log(clampedScore / (1.0 - clampedScore));
    return -winnerRatio * logit / steepness;
  }
}
