/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/api/auth/auth_provider.dart';
import 'package:shooting_sports_analyst/util.dart';

class SSAPublicAuthClient extends TokenAuthProvider<SSASession> {
  @override
  Future<Map<String, String>> getHeaders(SSASession session, {required String method, required String path, required List<int> bodyBytes}) {
    return Future.value({});
  }

  @override
  Result<SSASession, AuthError> getCurrentSession() {
    return Result.err(AuthError.unauthenticated);
  }

  @override
  Future<AuthResult<SSASession>> getSession() {
    return Future.value(Result.err(AuthError.unauthenticated));
  }

  @override
  Future<bool> isAuthenticated() {
    return Future.value(false);
  }

  @override
  Future<AuthResult<SSASession>> refreshSession(SSASession currentSession) {
    return Future.value(Result.err(AuthError.unauthenticated));
  }
}

class SSASession implements Session {
}