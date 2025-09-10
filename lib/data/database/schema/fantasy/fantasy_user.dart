/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';

part 'fantasy_user.g.dart';

@collection
class FantasyUser {
  Id id = Isar.autoIncrement;

  /// The username of the user.
  String username;

  /// The hashed password of the user.
  String hashedPassword;

  /// The salt used to hash the password.
  String passwordSalt;

  /// The email of the user.
  String email;

  /// The teams the user is managing.
  @Backlink(to: 'manager')
  final memberOf = IsarLinks<Team>();

  /// The leagues the user is commissioner of.
  @Backlink(to: 'commissioner')
  final commissionerOf = IsarLinks<League>();

  FantasyUser({
    required this.username,
    required this.hashedPassword,
    required this.passwordSalt,
    required this.email,
  });
}
