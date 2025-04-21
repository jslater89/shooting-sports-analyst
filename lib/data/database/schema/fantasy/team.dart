/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';

part 'team.g.dart';

@collection
class Team {
  Id id = Isar.autoIncrement;

  String name;

  @Backlink(to: 'teams')
  final league = IsarLink<League>();

  /// The players on this team.
  final players = IsarLinks<FantasyPlayer>();

  /// The roster assignments for this team.
  final rosterAssignments = IsarLinks<RosterAssignment>();

  Team({
    required this.name,
  });
}
