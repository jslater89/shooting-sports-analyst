/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';

/// Calculates fantasy scores for a match.
///
/// T is an enum or sealed class that implementations should use as keys for
/// a map of scoring categories to points per category in [FantasyScore].
///
/// See [USPSAFantasyScoringCalculator] for an example implementation.
abstract interface class FantasyScoringCalculator<T> {
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
  Map<MatchEntry, FantasyScore<T>> calculateFantasyScores(ShootingMatch match, {
    bool byDivision = true,
    List<MatchEntry>? entries,
  });
}

/// A score for a shooter in a fantasy league.
///
/// T is an enum or sealed class that implementations should use as keys for
/// the scoring categories map.
class FantasyScore<T> {
  double get points => scoringCategories.values.sum;
  final Map<T, double> scoringCategories;

  FantasyScore(this.scoringCategories);

  String get tooltip {
    var buffer = StringBuffer();

    for(var category in scoringCategories.entries) {
      buffer.write("${category.key}: ${category.value.toStringAsFixed(2)}\n");
    }

    return buffer.toString().substring(0, buffer.length - 1);
  }

  @override
  String toString() {
    return("$points");
  }
}
