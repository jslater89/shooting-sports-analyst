/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

/// Calculates fantasy scores for a match.
///
/// [pointsAvailable] is a map of scoring categories to their double weights,
/// which individual fantasy leagues can use to adjust the relative importance
/// of each category.
abstract class FantasyScoringCalculator {
  const FantasyScoringCalculator();

  /// Calculate fantasy scores for a match.
  ///
  /// If [byDivision] is true (the default behavior), scores are calculated
  /// with reference to the division of the match entry—e.g. in the USPSA
  /// calculator, a Limited shooter will only compete for percent finish, raw time
  /// wins, and accuracy wins with other Limited shooters. If [byDivision] is false,
  /// every competitor included in the calculation will be scored together.
  ///
  /// If [entries] is provided, scores are calculated with respect to those entries
  /// only. By providing [entries] and setting [byDivision] to false, it is possible
  /// to calculate fantasy scores for an arbitrary subset of competitors in a match.
  Map<MatchEntry, FantasyScore> calculateFantasyScores(ShootingMatch match, {
    bool byDivision = true,
    List<MatchEntry>? entries,
  });

  /// The scoring categories that are used by this calculator.
  List<FantasyScoringCategory> get scoringCategories => FantasyScoringCategory.values;

  /// The points available for each scoring category. Defaults to 100 for finish percentage
  /// and stage/accuracy/raw time wins, 75 for top 10% finishes, 50 for top 25% finishes.
  ///
  /// [FantasyScoringCategory.penalties] and [FantasyScoringCategory.divisionParticipationPenalty]
  /// are special cases. For penalties, the value in this map is the points deducted per penalty.
  /// For division participation penalty, the value in this map is the weight applied to the total
  /// penalty (between 0 for off and 1 for full strength).
  Map<FantasyScoringCategory, double> get pointsAvailable;
}

/// A score for a competitor in a fantasy league.
///
/// It contains two maps: one for the calculated scores, and one for the counts of
/// underlying stats that generated those scores.
class FantasyScore {
  double get points => scoringCategories.values.sum;
  final Map<FantasyScoringCategory, double> scoringCategories;
  final Map<FantasyScoringCategory, int> counts;

  FantasyScore(this.scoringCategories, {required this.counts});

  String get tooltip {
    var buffer = StringBuffer();

    for(var category in scoringCategories.entries) {
      buffer.write("${category.key}: ${category.value.toStringAsFixed(2)}${counts[category.key] == null ? "" : " (${counts[category.key]})"}\n");
    }

    return buffer.toString().substring(0, buffer.length - 1);
  }

  @override
  String toString() {
    return("$points");
  }

  Map<String, dynamic> toJson() {
    return {
      "scores": {scoringCategories.map((key, value) => MapEntry(key.toString(), value))},
      "counts": {counts.keys.where((k) => k.isCountable).map((key) => MapEntry(key.toString(), counts[key]!))},
    };
  }

  static FantasyScore fromJson(String json) {
    var map = jsonDecode(json) as Map<String, dynamic>;
    var categoryScores = map["scores"] as Map<String, double>;
    var counts = map["counts"] as Map<String, int>;
    var score = FantasyScore(
      categoryScores.map((key, value) => MapEntry(FantasyScoringCategory.values.byName(key), value)),
      counts: counts.map((key, value) => MapEntry(FantasyScoringCategory.values.byName(key), value)),
    );
    for(var category in FantasyScoringCategory.values) {
      if(score.counts[category] == null) {
        score.counts[category] = 0;
      }
    }
    return score;
  }
}

enum FantasyScoringCategory {
/// Points equal to finish percentage.
  finishPercentage,

  // Points for stage wins, top 10%, and top 25% finishes. No double dipping.
  // If a shooter wins, they aren't eligible for top 10% or top 25% points.

  /// 100/N points per stage win, where N is the number of stages.
  stageWins,
  /// 75/N points per stage top 10 finish, where N is the number of stages.
  stageTop10Percents,
  /// 50/N points per stage top 25 finish, where N is the number of stages.
  stageTop25Percents,

  // Points for raw time champs. Same double dipping rules as stage scores.

  /// 100/N points per stage raw time win, where N is the number of stages.
  rawTimeWins,

  /// 75/N points per stage raw time top 10 finish, where N is the number of stages.
  rawTimeTop10Percents,

  /// 50/N points per stage raw time top 25 finish, where N is the number of stages.
  rawTimeTop25Percents,

  // Points for accuracy. Same double dipping rules as stage scores.

  /// 100/N points per stage accuracy win, where N is the number of stages.
  accuracyWins,

  /// 75/N points per stage accuracy top 10 finish, where N is the number of stages.
  accuracyTop10Percents,

  /// 50/N points per stage accuracy top 25 finish, where N is the number of stages.
  accuracyTop25Percents,

  /// -5 points per miss, no-shoot, or procedural.
  penalties,

  /// A negative number to account for division participation, which is calculated
  /// as a percentage of the sum of the other components.
  ///
  /// If a division is the largest, or if it has at least 25 shooters and at least 1
  /// GM, plus at least 1 GM per 50 shooters total, it gets no penalty.
  ///
  /// Otherwise, it gets a penalty of (sum of other components) * (proportion of smallest
  /// division eligible for full points).
  divisionParticipationPenalty;

  bool get isCountable => switch(this) {
    FantasyScoringCategory.finishPercentage => false,
    FantasyScoringCategory.stageWins => true,
    FantasyScoringCategory.stageTop10Percents => true,
    FantasyScoringCategory.stageTop25Percents => true,
    FantasyScoringCategory.rawTimeWins => true,
    FantasyScoringCategory.rawTimeTop10Percents => true,
    FantasyScoringCategory.rawTimeTop25Percents => true,
    FantasyScoringCategory.accuracyWins => true,
    FantasyScoringCategory.accuracyTop10Percents => true,
    FantasyScoringCategory.accuracyTop25Percents => true,
    FantasyScoringCategory.penalties => true,
    FantasyScoringCategory.divisionParticipationPenalty => false,
  };

  bool get isSpecial => switch(this) {
    FantasyScoringCategory.divisionParticipationPenalty => true,
    _ => false,
  };

  double get defaultPointsAvailable => switch(this) {
    FantasyScoringCategory.finishPercentage => 100,
    FantasyScoringCategory.stageWins => 100,
    FantasyScoringCategory.stageTop10Percents => 75,
    FantasyScoringCategory.stageTop25Percents => 50,
    FantasyScoringCategory.rawTimeWins => 100,
    FantasyScoringCategory.rawTimeTop10Percents => 75,
    FantasyScoringCategory.rawTimeTop25Percents => 50,
    FantasyScoringCategory.accuracyWins => 100,
    FantasyScoringCategory.accuracyTop10Percents => 75,
    FantasyScoringCategory.accuracyTop25Percents => 50,
    FantasyScoringCategory.penalties => -5,
    FantasyScoringCategory.divisionParticipationPenalty => 1,
  };

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
}
