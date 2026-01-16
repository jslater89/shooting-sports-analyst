/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/user.dart';

part 'fantasy_user.g.dart';

/// A user of the fantasy league system, optionally linked to a server user
/// for remote play.
@collection
class FantasyUser {
  Id id = Isar.autoIncrement;

  @Backlink(to: 'fantasyUser')
  final serverUser = IsarLink<User>();

  /// The display name of the user in the fantasy league.
  ///
  /// If not set, the display name will be the same as the server user's display name.
  ///
  /// Should be set for local players.
  String? fantasyDisplayName;

  /// The hashed password of the user, if they are a local player.
  ///
  /// Should be empty if the player has a linked server user.
  String? localHashedPassword;

  /// The teams the user is managing.
  @Backlink(to: 'manager')
  final managerOf = IsarLinks<Team>();

  /// The leagues the user is commissioner of.
  @Backlink(to: 'commissioner')
  final commissionerOf = IsarLinks<League>();

  FantasyUser({
    this.fantasyDisplayName,
    this.localHashedPassword,
  });
}
