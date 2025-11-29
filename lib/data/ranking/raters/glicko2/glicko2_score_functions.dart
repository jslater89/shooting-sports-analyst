/// The classical Glicko-2 score function: 1 for a head-to-head win, 0 for a loss, 0.5 for a draw.
double allOrNothingScoreFunction(double shooterRatio, double opponentRatio) {
  if(shooterRatio == opponentRatio) return 0.5;
  if(shooterRatio > opponentRatio) return 1.0;
  return 0.0;
}

/// A score function that gives a score between 0 and 1 based on the margin of victory.
///
/// [perfectVictoryDifference] is the difference in ratio between the shooter and the opponent
/// that results in a perfect victory score of 1.0 (or a perfect loss score of 0.0).
///
/// A tie returns 0.5.
double linearMarginOfVictoryScoreFunction(double shooterRatio, double opponentRatio, {double perfectVictoryDifference = 0.25}) {
  var margin = shooterRatio - opponentRatio;
  if(margin >= perfectVictoryDifference) return 1.0;
  if(margin <= -perfectVictoryDifference) return 0.0;
  return 0.5 + margin / (2 * perfectVictoryDifference);
}