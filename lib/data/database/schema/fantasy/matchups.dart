/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';

part 'matchups.g.dart';

@collection
class Matchup {
  Id id = Isar.autoIncrement;

  @Backlink(to: 'matchups')
  final month = IsarLink<LeagueMonth>();

  final homeRoster = IsarLink<MonthlyRoster>();
  final awayRoster = IsarLink<MonthlyRoster>();

  bool? homeWins;
  double? marginOfVictory;

  bool get completed => homeWins != null;

  Matchup({
    this.homeWins,
    this.marginOfVictory,
  });
}

@embedded
class SlotScore {
  int slotIndex;
  String dbScore;

  double get points => score.points;

  FantasyScore? _cachedScore;
  @ignore
  FantasyScore get score {
    if(_cachedScore == null) {
      _cachedScore = FantasyScore.fromJson(dbScore);
    }
    return _cachedScore!;
  }

  set score(FantasyScore value) {
    _cachedScore = value;
    dbScore = value.toJson();
  }

  SlotScore({
    this.slotIndex = 0,
    this.dbScore = "",
  });

  SlotScore.fromFantasyScore(this.slotIndex, FantasyScore score) : dbScore = score.toJson(), _cachedScore = score;
}
