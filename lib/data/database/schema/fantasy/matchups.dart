/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';

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

  int playerId;
  int monthId;

  /// A no-arg constructor for Isar. Prefer [fromDbEntities] or [fromIds].
  SlotScore({
    this.slotIndex = 0,
    this.playerId = 0,
    this.monthId = 0,
  });

  /// Create a [SlotScore] from the given player and league month.
  SlotScore.fromDbEntities({
    required FantasyPlayer player,
    required LeagueMonth month,
    required int slotIndex,
  }) : slotIndex = slotIndex, playerId = player.id, monthId = month.id;

  /// Create a [SlotScore] from the given database IDs.
  SlotScore.fromIds({
    required int playerId,
    required int monthId,
    required int slotIndex,
  }) : slotIndex = slotIndex, playerId = playerId, monthId = monthId;
}
