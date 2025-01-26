/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';

abstract interface class FantasyScoringCalculator<T> {
  Map<MatchEntry, FantasyScore<T>> calculateFantasyScores(ShootingMatch match);
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