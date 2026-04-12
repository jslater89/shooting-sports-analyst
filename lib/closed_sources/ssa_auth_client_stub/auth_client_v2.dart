/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/api/auth/auth_provider.dart";
import "package:shooting_sports_analyst/util.dart";

class SSAPublicAuthClientV2 extends TokenAuthProvider<SSASessionV2> {
  SSAPublicAuthClientV2({
    required String baseUrl,
    bool allowDebugCertificates = false,
    String? serverEd25519PubBase64,
  }) {}

  Future<AuthResult<SSASessionV2>> authenticate() {
    return Future.value(Result.err(AuthError.unauthenticated));
  }

  @override
  Future<Map<String, String>> getHeaders(
    SSASessionV2 session, {
    required String method,
    required String path,
    required List<int> bodyBytes,
  }) {
    return Future.value({});
  }

  @override
  Result<SSASessionV2, AuthError> getCurrentSession() {
    return Result.err(AuthError.unauthenticated);
  }

  @override
  Future<AuthResult<SSASessionV2>> getSession() {
    return Future.value(Result.err(AuthError.unauthenticated));
  }

  @override
  Future<bool> isAuthenticated() {
    return Future.value(false);
  }

  @override
  Future<AuthResult<SSASessionV2>> refreshSession(SSASessionV2 currentSession) {
    return Future.value(Result.err(AuthError.unauthenticated));
  }
}

class SSASessionV2 implements Session {
}
