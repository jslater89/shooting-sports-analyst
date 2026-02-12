/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/user.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'session.g.dart';

@collection
class Session {
  Id get id => sessionId.stableHash;

  /// A cryptographically secure random string used to identify the
  /// session.
  @Index()
  String sessionId;

  /// The resolved user for this session.
  final user = IsarLink<User>();

  /// The auth identity name for this session.
  @Index()
  String? identityName;

  /// The method of authentication used to create this session.
  @enumerated
  AuthMethod authMethod;

  /// The access token for the session, for password and
  /// Patreon OAuth sauthentication.
  String? accessToken;

  /// The refresh token for the session, for Patreon OAuth authentication.
  String? refreshToken;

  /// The session key for the session, for private key authentication.
  String? sessionKey;

  /// The JWT ID for this session, for private key authentication.
  @Index()
  String? jti;

  int counter = -1;
  int inFlightMask = 0;

  DateTime created;

  /// The expiration date of the session.
  @Index()
  DateTime expires;

  @ignore
  bool get isValid => expires.isAfter(DateTime.now());

  Session({
    required this.sessionId,
    required this.authMethod,
    required this.created,
    required this.expires,
    this.sessionKey,
    this.jti,
    this.accessToken,
    this.refreshToken,
    this.identityName,
    this.counter = -1,
    this.inFlightMask = 0,
  });
}
