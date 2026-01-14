/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/fantasy_user.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/permission.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/role.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'user.g.dart';

/// A user on a Shooting Sports Analyst server.
///
/// This is used to authenticate
@collection
class User {
  Id get id => username.stableHash;

  final fantasyUser = IsarLink<FantasyUser>();
  final predictionGamePlayer = IsarLink<PredictionGamePlayer>();

  final roles = IsarLinks<Role>();
  @enumerated
  List<Permission> standalonePermissions = [];

  @ignore
  Set<Permission> get permissions {
    return roles.map((role) => role.permissions).flattened.toSet().union(standalonePermissions.toSet());
  }

  bool hasPermission(Permission p) {
    return permissions.any((permission) {
      return p == permission || p == Permission.siteAdmin;
    });
  }

  String username;

  String? email;

  /// Local players can be at most password authenticated.
  bool isLocal;

  /// The authentication methods that can identify the user.
  @enumerated
  List<AuthMethod> availableAuthMethods;

  @ignore
  bool get isPasswordAuthenticated => availableAuthMethods.contains(AuthMethod.password);
  /// Hashed password, if available.
  String? hashedPassword;

  @ignore
  bool get isPrivateKeyAuthenticated => availableAuthMethods.contains(AuthMethod.privateKey);
  /// Public key corresponding to the user's private key, if available.
  String? publicKey;

  @ignore
  bool get isPatreonOauthAuthenticated => availableAuthMethods.contains(AuthMethod.patreonOauth);
  PatreonOauthSession? patreonOauthSession;

  User({
    required this.username,
    this.email,
    required this.isLocal,
    required this.availableAuthMethods,
  });
}

enum AuthMethod {
  password,
  privateKey,
  patreonOauth;
}

@embedded
class PatreonOauthSession {
  String accessToken = "";
  String refreshToken = "";
  DateTime expiresAt = practicalShootingZeroDate;

  @ignore
  bool get isValid => expiresAt.isAfter(DateTime.now());
}