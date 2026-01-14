import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/user.dart';

part 'session.g.dart';

@collection
class Session {
  Id id = Isar.autoIncrement;

  /// The resolved user for this session.
  final user = IsarLink<User>();

  /// The auth identity name for this session.
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
  String? jti;

  int counter = -1;
  int inFlightMask = 0;

  DateTime created;
  DateTime expires;

  Session({
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
