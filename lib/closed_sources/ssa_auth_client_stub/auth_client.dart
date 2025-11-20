import 'package:shooting_sports_analyst/server/auth/auth_provider.dart';

class SSAPublicAuthClient extends TokenAuthProvider<SSASession> {
  @override
  Future<Map<String, String>> getHeaders(SSASession session, {required String method, required String path, required List<int> bodyBytes}) {
    // TODO: implement getHeaders
    throw UnimplementedError();
  }

  @override
  Future<AuthResult<SSASession>> getSession() {
    // TODO: implement getSession
    throw UnimplementedError();
  }

  @override
  Future<bool> isAuthenticated() {
    // TODO: implement isAuthenticated
    throw UnimplementedError();
  }

  @override
  Future<AuthResult<SSASession>> refreshSession(SSASession currentSession) {
    // TODO: implement refreshSession
    throw UnimplementedError();
  }
}

class SSASession implements Session {
}