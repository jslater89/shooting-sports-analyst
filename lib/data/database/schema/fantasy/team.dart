/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/fantasy_user.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';

part 'team.g.dart';

@collection
class Team {
  Id id = Isar.autoIncrement;

  String name;

  /// The manager of the team.
  final manager = IsarLink<FantasyUser>();

  @Backlink(to: 'teams')
  final league = IsarLink<League>();

  /// The players on this team.
  final players = IsarLinks<FantasyPlayer>();

  /// Pending roster assignments for this team.
  ///
  /// Whenever a month starts, the assignments in this list will be
  /// copied to a [MonthlyRoster] object tied to the [LeagueMonth],
  /// and those assignments will be used for scoring.
  ///
  /// This list will _not_ be cleared: think of it as the assignments
  /// on the team's roster settings page.
  final rosterAssignments = IsarLinks<RosterAssignment>();

  Team({
    required this.name,
  });
}
