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
  final predictionGamePlayers = IsarLinks<PredictionGamePlayer>();

  final roles = IsarLinks<Role>();
  @Enumerated(EnumType.value, 'permissionName')
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

  /// An alternate display name for the user, if desired. (Since
  /// username is the primary identifier, username cannot be edited.)
  String? displayName;

  /// The username of the user.
  @Index()
  String username;

  @ignore
  String get guaranteedDisplayName => displayName ?? username;

  /// The email address of the user.
  @Index()
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
  /// The session information for Patreon OAuth authentication, if available.
  PatreonOauthSession? patreonInfo;

  User({
    required this.username,
    this.displayName,
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
  String lastPatreonTierId = "";
  String lastPatreonTierName = "";
  DateTime expiresAt = practicalShootingZeroDate;
  DateTime nextTierCheck = practicalShootingZeroDate;

  /// Zero-arg constructor for Isar. Use [create] to initialize.
  PatreonOauthSession();

  /// Create a new Patreon OAuth se`ssion.
  PatreonOauthSession.create({
    required this.lastPatreonTierId,
    required this.lastPatreonTierName,
    required this.expiresAt,
    required this.nextTierCheck,
  });

  @ignore
  bool get isValid => expiresAt.isAfter(DateTime.now());
}