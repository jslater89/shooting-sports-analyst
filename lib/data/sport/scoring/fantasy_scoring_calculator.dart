/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

/// A calculator that can calculate fantasy scores for a given match.
///
/// [pointsAvailable] is a map of scoring categories to their double weights,
/// which individual fantasy leagues can use to adjust the relative importance
/// of each category.
abstract class FantasyScoringCalculator {
  const FantasyScoringCalculator();

  /// Calculate fantasy scores for a match, given a map of [stats] and a map of [pointsAvailable]
  /// per category.
  ///
  /// [pointsAvailable] weights scores. Defaults to 100 for finish percentage
  /// and stage/accuracy/raw time wins, 75 for top 10% finishes, 50 for top 25% finishes.
  ///
  /// [FantasyScoringCategory.penalties] and [FantasyScoringCategory.divisionParticipationPenalty]
  /// are special cases. For penalties, the value in this map is the points deducted per penalty.
  /// For division participation penalty, the value in this map is the weight applied to the total
  /// penalty (between 0 for off and 1 for full strength).
  Map<MatchEntry, FantasyScore> calculateFantasyScores({
    required Map<MatchEntry, DbFantasyStats> stats,
    FantasyPointsAvailable pointsAvailable = FantasyScoringCategory.defaultCategoryPoints,
  });

  /// Calculate the fantasy stats for a match, given a shooting match and some informatino
  /// about which competitor or map of competitors to include.
  ///
  /// If [byDivision] is true (the default behavior), stats are calculated
  /// with reference to the division of the match entry—e.g. in the USPSA
  /// calculator, a Limited shooter will only compete for percent finish, raw time
  /// wins, and accuracy wins with other Limited shooters. If [byDivision] is false,
  /// every competitor included in the calculation will be scored together.
  ///
  /// If [entries] is provided, stats are calculated with respect to those entries
  /// only. By providing [entries] and setting [byDivision] to false, it is possible
  /// to calculate fantasy stats for an arbitrary subset of competitors in a match.
  Map<MatchEntry, DbFantasyStats> calculateFantasyStats(ShootingMatch match, {
    bool byDivision = true,
    List<MatchEntry>? entries,
  });

  FantasyScore calculateFantasyScore({
    required DbFantasyStats stats,
    FantasyPointsAvailable pointsAvailable = FantasyScoringCategory.defaultCategoryPoints,
  }) {
    FantasyScore score = FantasyScore(activeCategories: scoringCategories);

    if(scoringCategories.contains(FantasyScoringCategory.finishPercentage)) {
      score.finishPercentage = stats.finishPercentage * pointsAvailable.finishPercentage;
    }

    if(scoringCategories.contains(FantasyScoringCategory.stageWins)) {
      score.stageWins = (pointsAvailable.stageWins / stats.stageCount) * stats.stageWins;
      score.stageWinsCount = stats.stageWins;
    }

    if(scoringCategories.contains(FantasyScoringCategory.stageTop10Percents)) {
      score.stageTop10Percents = (pointsAvailable.stageTop10Percents / stats.stageCount) * stats.stageTop10Percents;
      score.stageTop10PercentsCount = stats.stageTop10Percents;
    }

    if(scoringCategories.contains(FantasyScoringCategory.stageTop25Percents)) {
      score.stageTop25Percents = (pointsAvailable.stageTop25Percents / stats.stageCount) * stats.stageTop25Percents;
      score.stageTop25PercentsCount = stats.stageTop25Percents;
    }

    if(scoringCategories.contains(FantasyScoringCategory.rawTimeWins)) {
      score.rawTimeWins = (pointsAvailable.rawTimeWins / stats.stageCount) * stats.rawTimeWins;
      score.rawTimeWinsCount = stats.rawTimeWins;
    }

    if(scoringCategories.contains(FantasyScoringCategory.rawTimeTop10Percents)) {
      score.rawTimeTop10Percents = (pointsAvailable.rawTimeTop10Percents / stats.stageCount) * stats.rawTimeTop10Percents;
      score.rawTimeTop10PercentsCount = stats.rawTimeTop10Percents;
    }

    if(scoringCategories.contains(FantasyScoringCategory.rawTimeTop25Percents)) {
      score.rawTimeTop25Percents = (pointsAvailable.rawTimeTop25Percents / stats.stageCount) * stats.rawTimeTop25Percents;
      score.rawTimeTop25PercentsCount = stats.rawTimeTop25Percents;
    }

    if(scoringCategories.contains(FantasyScoringCategory.accuracyWins)) {
      score.accuracyWins = (pointsAvailable.accuracyWins / stats.stageCount) * stats.accuracyWins;
      score.accuracyWinsCount = stats.accuracyWins;
    }

    if(scoringCategories.contains(FantasyScoringCategory.accuracyTop10Percents)) {
      score.accuracyTop10Percents = (pointsAvailable.accuracyTop10Percents / stats.stageCount) * stats.accuracyTop10Percents;
      score.accuracyTop10PercentsCount = stats.accuracyTop10Percents;
    }

    if(scoringCategories.contains(FantasyScoringCategory.accuracyTop25Percents)) {
      score.accuracyTop25Percents = (pointsAvailable.accuracyTop25Percents / stats.stageCount) * stats.accuracyTop25Percents;
      score.accuracyTop25PercentsCount = stats.accuracyTop25Percents;
    }

    if(scoringCategories.contains(FantasyScoringCategory.penalties)) {
      score.penalties = pointsAvailable.penalties * stats.penalties;
      score.penaltiesCount = stats.penalties;
    }

    if(scoringCategories.contains(FantasyScoringCategory.divisionParticipationPenalty)) {
      var runningScore = score.points;
      var actualScore = runningScore * stats.divisionParticipationPenalty;
      score.divisionParticipationPenalty = (actualScore - runningScore);
    }

    return score;
  }

  /// The scoring categories that are used by this calculator.
  List<FantasyScoringCategory> get scoringCategories => FantasyScoringCategory.values;
}

class FantasyPointsAvailable {
  final double finishPercentage;
  final double stageWins;
  final double stageTop10Percents;
  final double stageTop25Percents;
  final double rawTimeWins;
  final double rawTimeTop10Percents;
  final double rawTimeTop25Percents;
  final double accuracyWins;
  final double accuracyTop10Percents;
  final double accuracyTop25Percents;
  final double penalties;
  final double divisionParticipationPenalty;

  const FantasyPointsAvailable({
    this.finishPercentage = 100,
    this.stageWins = 100,
    this.stageTop10Percents = 75,
    this.stageTop25Percents = 50,
    this.rawTimeWins = 100,
    this.rawTimeTop10Percents = 75,
    this.rawTimeTop25Percents = 50,
    this.accuracyWins = 100,
    this.accuracyTop10Percents = 75,
    this.accuracyTop25Percents = 50,
    this.penalties = -5,
    this.divisionParticipationPenalty = 1,
  });
}

/// A score for a competitor in a fantasy league.
///
/// It contains two maps: one for the calculated scores, and one for the counts of
/// underlying stats that generated those scores.
class FantasyScore {
  double finishPercentage = 0;

  double stageWins = 0;
  int stageWinsCount = 0;
  double stageTop10Percents = 0;
  int stageTop10PercentsCount = 0;
  double stageTop25Percents = 0;
  int stageTop25PercentsCount = 0;
  double rawTimeWins = 0;
  int rawTimeWinsCount = 0;
  double rawTimeTop10Percents = 0;
  int rawTimeTop10PercentsCount = 0;
  double rawTimeTop25Percents = 0;
  int rawTimeTop25PercentsCount = 0;
  double accuracyWins = 0;
  int accuracyWinsCount = 0;
  double accuracyTop10Percents = 0;
  int accuracyTop10PercentsCount = 0;
  double accuracyTop25Percents = 0;
  int accuracyTop25PercentsCount = 0;
  double penalties = 0;
  int penaltiesCount = 0;
  double divisionParticipationPenalty = 0;

  List<FantasyScoringCategory> activeCategories = [];

  Map<FantasyScoringCategory, double> get categoryScores => {
    FantasyScoringCategory.finishPercentage: finishPercentage,
    FantasyScoringCategory.stageWins: stageWins,
    FantasyScoringCategory.stageTop10Percents: stageTop10Percents,
    FantasyScoringCategory.stageTop25Percents: stageTop25Percents,
    FantasyScoringCategory.rawTimeWins: rawTimeWins,
    FantasyScoringCategory.rawTimeTop10Percents: rawTimeTop10Percents,
    FantasyScoringCategory.rawTimeTop25Percents: rawTimeTop25Percents,
    FantasyScoringCategory.accuracyWins: accuracyWins,
    FantasyScoringCategory.accuracyTop10Percents: accuracyTop10Percents,
    FantasyScoringCategory.accuracyTop25Percents: accuracyTop25Percents,
    FantasyScoringCategory.penalties: penalties,
    FantasyScoringCategory.divisionParticipationPenalty: divisionParticipationPenalty,
  };

  double get points =>
    finishPercentage +
    stageWins +
    stageTop10Percents +
    stageTop25Percents +
    rawTimeWins +
    rawTimeTop10Percents +
    rawTimeTop25Percents +
    accuracyWins +
    accuracyTop10Percents +
    accuracyTop25Percents +
    penalties +
    divisionParticipationPenalty;

  FantasyScore({
    this.finishPercentage = 0,
    this.stageWins = 0,
    this.stageWinsCount = 0,
    this.stageTop10Percents = 0,
    this.stageTop10PercentsCount = 0,
    this.stageTop25Percents = 0,
    this.stageTop25PercentsCount = 0,
    this.rawTimeWins = 0,
    this.rawTimeWinsCount = 0,
    this.rawTimeTop10Percents = 0,
    this.rawTimeTop10PercentsCount = 0,
    this.rawTimeTop25Percents = 0,
    this.rawTimeTop25PercentsCount = 0,
    this.accuracyWins = 0,
    this.accuracyWinsCount = 0,
    this.accuracyTop10Percents = 0,
    this.accuracyTop10PercentsCount = 0,
    this.accuracyTop25Percents = 0,
    this.accuracyTop25PercentsCount = 0,
    this.penalties = 0,
    this.penaltiesCount = 0,
    this.divisionParticipationPenalty = 0,
    required this.activeCategories,
  });

  String get tooltip {
    var buffer = StringBuffer();

    if(activeCategories.contains(FantasyScoringCategory.finishPercentage)) {
      buffer.write("Finish Percentage: ${finishPercentage.toStringAsFixed(2)}\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.stageWins)) {
      buffer.write("Stage Wins: ${stageWins.toStringAsFixed(2)} (${stageWinsCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.stageTop10Percents)) {
      buffer.write("Stage Top 10%: ${stageTop10Percents.toStringAsFixed(2)} (${stageTop10PercentsCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.stageTop25Percents)) {
      buffer.write("Stage Top 25%: ${stageTop25Percents.toStringAsFixed(2)} (${stageTop25PercentsCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.rawTimeWins)) {
      buffer.write("Raw Time Wins: ${rawTimeWins.toStringAsFixed(2)} (${rawTimeWinsCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.rawTimeTop10Percents)) {
      buffer.write("Raw Time Top 10%: ${rawTimeTop10Percents.toStringAsFixed(2)} (${rawTimeTop10PercentsCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.rawTimeTop25Percents)) {
      buffer.write("Raw Time Top 25%: ${rawTimeTop25Percents.toStringAsFixed(2)} (${rawTimeTop25PercentsCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.accuracyWins)) {
      buffer.write("Accuracy Wins: ${accuracyWins.toStringAsFixed(2)} (${accuracyWinsCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.accuracyTop10Percents)) {
      buffer.write("Accuracy Top 10%: ${accuracyTop10Percents.toStringAsFixed(2)} (${accuracyTop10PercentsCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.accuracyTop25Percents)) {
      buffer.write("Accuracy Top 25%: ${accuracyTop25Percents.toStringAsFixed(2)} (${accuracyTop25PercentsCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.penalties)) {
      buffer.write("Penalties: ${penalties.toStringAsFixed(2)} (${penaltiesCount})\n");
    }
    if(activeCategories.contains(FantasyScoringCategory.divisionParticipationPenalty)) {
      buffer.write("Division Participation Penalty: ${divisionParticipationPenalty.toStringAsFixed(2)}\n");
    }
    return buffer.toString().substring(0, buffer.length - 1);
  }

  @override
  String toString() {
    return("$points");
  }
}

enum FantasyScoringCategory {
/// Points equal to finish percentage.
  finishPercentage(isCountable: false, isRatio: true, isSpecial: false),

  // Points for stage wins, top 10%, and top 25% finishes. No double dipping.
  // If a shooter wins, they aren't eligible for top 10% or top 25% points.

  /// 100/N points per stage win, where N is the number of stages.
  stageWins(isCountable: true, isRatio: false, isSpecial: false),
  /// 75/N points per stage top 10 finish, where N is the number of stages.
  stageTop10Percents(isCountable: true, isRatio: false, isSpecial: false),
  /// 50/N points per stage top 25 finish, where N is the number of stages.
  stageTop25Percents(isCountable: true, isRatio: false, isSpecial: false),

  // Points for raw time champs. Same double dipping rules as stage scores.

  /// 100/N points per stage raw time win, where N is the number of stages.
  rawTimeWins(isCountable: true, isRatio: false, isSpecial: false),

  /// 75/N points per stage raw time top 10 finish, where N is the number of stages.
  rawTimeTop10Percents(isCountable: true, isRatio: false, isSpecial: false),

  /// 50/N points per stage raw time top 25 finish, where N is the number of stages.
  rawTimeTop25Percents(isCountable: true, isRatio: false, isSpecial: false),

  // Points for accuracy. Same double dipping rules as stage scores.

  /// 100/N points per stage accuracy win, where N is the number of stages.
  accuracyWins(isCountable: true, isRatio: false, isSpecial: false),

  /// 75/N points per stage accuracy top 10 finish, where N is the number of stages.
  accuracyTop10Percents(isCountable: true, isRatio: false, isSpecial: false),

  /// 50/N points per stage accuracy top 25 finish, where N is the number of stages.
  accuracyTop25Percents(isCountable: true, isRatio: false, isSpecial: false),

  /// -5 points per miss, no-shoot, or procedural.
  penalties(isCountable: true, isRatio: false, isSpecial: true),

  /// A negative number to account for division participation, which is calculated
  /// as a percentage of the sum of the other components.
  ///
  /// If a division is the largest, or if it has at least 25 shooters and at least 1
  /// GM, plus at least 1 GM per 50 shooters total, it gets no penalty.
  ///
  /// Otherwise, it gets a penalty of (sum of other components) * (proportion of smallest
  /// division eligible for full points).
  divisionParticipationPenalty(isCountable: false, isRatio: true, isSpecial: true);

  const FantasyScoringCategory({
    this.isCountable = false,
    this.isRatio = false,
    this.isSpecial = false,
  });

  final bool isCountable;
  final bool isRatio;
  final bool isSpecial;

  @override
  String toString() {
    return switch(this) {
      FantasyScoringCategory.finishPercentage => "Finish Percentage",
      FantasyScoringCategory.stageWins => "Stage Wins",
      FantasyScoringCategory.stageTop10Percents => "Stage Top 10%",
      FantasyScoringCategory.stageTop25Percents => "Stage Top 25%",
      FantasyScoringCategory.rawTimeWins => "Raw Time Wins",
      FantasyScoringCategory.rawTimeTop10Percents => "Raw Time Top 10%",
      FantasyScoringCategory.rawTimeTop25Percents => "Raw Time Top 25%",
      FantasyScoringCategory.accuracyWins => "Accuracy Wins",
      FantasyScoringCategory.accuracyTop10Percents => "Accuracy Top 10%",
      FantasyScoringCategory.accuracyTop25Percents => "Accuracy Top 25%",
      FantasyScoringCategory.penalties => "Penalties",
      FantasyScoringCategory.divisionParticipationPenalty => "Division Participation Penalty",
    };
  }

  static const FantasyPointsAvailable defaultCategoryPoints = FantasyPointsAvailable();
}
