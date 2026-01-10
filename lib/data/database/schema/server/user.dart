/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/fantasy_user.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';

part 'user.g.dart';

/// A user on a Shooting Sports Analyst server.
///
/// This is used to authenticate
@collection
class User {
  Id id = Isar.autoIncrement;

  final fantasyUser = IsarLink<FantasyUser>();
  final predictionGamePlayer = IsarLink<PredictionGamePlayer>();

  String username;
  String email;

  /// Local players can be at most password authenticated.
  bool isLocal;

  /// The authentication methods that can identify the user.
  @enumerated
  List<AuthMethods> availableAuthMethods;

  @ignore
  bool get isPasswordAuthenticated => availableAuthMethods.contains(AuthMethods.password);
  /// Argon2 password hash, if ava
  String? hashedPassword;

  @ignore
  bool get isPrivateKeyAuthenticated => availableAuthMethods.contains(AuthMethods.privateKey);
  /// Public key corresponding to the user's private key, if available.
  String? publicKey;

  @ignore
  bool get isPatreonOauthAuthenticated => availableAuthMethods.contains(AuthMethods.patreonOauth);
  // TODO: patreon oauth stuff

  User({
    required this.username,
    required this.email,
    required this.isLocal,
    required this.availableAuthMethods,
  });
}

enum AuthMethods {
  password,
  privateKey,
  patreonOauth,
}