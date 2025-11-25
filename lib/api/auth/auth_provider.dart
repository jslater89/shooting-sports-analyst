/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/util.dart';

typedef AuthResult<T> = Result<T, AuthError>;

enum AuthError implements ResultErr {
  /// The server is not valid.
  serverInvalid,
  /// The auth provider has not yet authenticated this client.
  unauthenticated,
  /// The client has attempted to authenticate, but was denied for
  /// unknown reasons.
  unauthorized,
  /// The client has provided invalid credentials.
  invalidCredentials,
  /// The client has provided an invalid session.
  invalidSession,
  /// The session has expired.
  sessionExpired,
  /// The session is invalid.
  sessionInvalid;

  @override
  String get message => switch(this) {
    serverInvalid => "Server invalid",
    unauthenticated => "Unauthenticated",
    unauthorized => "Unauthorized",
    invalidCredentials => "Invalid credentials",
    invalidSession => "Invalid session",
    sessionExpired => "Session expired",
    sessionInvalid => "Session invalid"
  };
}

/// An AuthProvider implements a means of authentication with a
/// server.
abstract class AuthProvider<T extends Session> {
  /// Whether this auth provider has authenticated this client.
  Future<bool> isAuthenticated();

  /// Get the current session for this auth provider, reauthenticating
  /// if necessary.
  Future<AuthResult<T>> getSession();

  /// Get the headers for a request to the given method, path, and body bytes.
  Future<Map<String, String>> getHeaders(
    T session,
    {required String method, required String path, required List<int> bodyBytes}
  );
}

/// A UserAuthProvider is an AuthProvider for user-based authentication.
abstract class UserAuthProvider<T extends Session> extends AuthProvider<T> {
  bool get supportsPasswordAuthentication;
  Future<AuthResult<T>> authenticate(String username, String password);

  bool get supportsOauthAuthentication;
  Future<AuthResult<T>> authenticateWithOauth(String username);
}

/// A TokenAuthProvider is an AuthProvider for token-based authentication.
abstract class TokenAuthProvider<T extends Session> extends AuthProvider<T> {
  Future<AuthResult<T>> getSession();
  Future<AuthResult<T>> refreshSession(T currentSession);
  AuthResult<T> getCurrentSession();
}

abstract class Session {
}