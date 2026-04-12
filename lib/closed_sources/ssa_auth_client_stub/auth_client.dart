/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:typed_data";

import "package:http/http.dart" as http;
import "package:shooting_sports_analyst/api/auth/auth_provider.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("SSAPublicAuthClient");

bool _stubApiKeyConfigured() {
  try {
    final v = FlutterOrNative.configProvider.currentConfig.ssaServerStubApiKey?.trim();
    return v != null && v.isNotEmpty;
  }
  catch (_) {
    return false;
  }
}

String? _stubApiKeyValue() {
  try {
    final v = FlutterOrNative.configProvider.currentConfig.ssaServerStubApiKey?.trim();
    return v != null && v.isNotEmpty ? v : null;
  }
  catch (_) {
    return null;
  }
}

void _ignoreOpenClientCompatArgs({
  required bool allowDebugCertificates,
  String? serverX25519PubBase64,
  String? serverEd25519PubBase64,
}) {
  if (allowDebugCertificates || serverX25519PubBase64 != null || serverEd25519PubBase64 != null) {
    // Kept for constructor parity with the closed client; stub auth ignores certificates.
  }
}

/// Open stub: same policy as [SSAPublicAuthClientV2] but uses `/auth/exchange`.
class SSAPublicAuthClient extends TokenAuthProvider<SSASession> {
  SSASession? session;

  final String baseUrl;

  SSAPublicAuthClient({
    required this.baseUrl,
    bool allowDebugCertificates = false,
    String? serverX25519PubBase64,
    String? serverEd25519PubBase64,
  }) {
    _ignoreOpenClientCompatArgs(
      allowDebugCertificates: allowDebugCertificates,
      serverX25519PubBase64: serverX25519PubBase64,
      serverEd25519PubBase64: serverEd25519PubBase64,
    );
    if (!_stubApiKeyConfigured()) {
      throw Exception(
        "Open SSA auth stub: set ssaServerStubApiKey in config.toml (dev-only; matches ssa_auth_server_stub)",
      );
    }
    _log.i("Stub SSA v1 auth client: API key exchange, Bearer-only protected requests");
  }

  Future<AuthResult<SSASession>> authenticate() async {
    final stubKey = _stubApiKeyValue();
    if (stubKey == null) {
      return Result.err(AuthError.unauthenticated);
    }
    final resp = await http.post(
      Uri.parse("$baseUrl/auth/exchange"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"apiKey": stubKey}),
    );
    if (resp.statusCode != 200) {
      _log.w("Stub v1 exchange failed ${resp.statusCode}: ${resp.body}");
      return Result.err(AuthError.serverInvalid);
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final sessionId = data["sessionId"] as String?;
    final exp = data["exp"] as int?;
    if (sessionId == null || exp == null) {
      _log.w("Stub v1 exchange response missing sessionId or exp");
      return Result.err(AuthError.serverInvalid);
    }
    final rolesRaw = data["roles"] as List<dynamic>?;
    final roles = rolesRaw == null ? <String>[] : rolesRaw.map((e) => e as String).toList();
    session = SSASession.stubBearer(
      bearerToken: sessionId.trim(),
      expUnix: exp,
      roles: roles,
    );
    return Result.ok(session!);
  }

  @override
  Future<Map<String, String>> getHeaders(
    SSASession session, {
    required String method,
    required String path,
    required List<int> bodyBytes,
  }) {
    return Future.value({
      "authorization": "Bearer ${session.jwt}",
    });
  }

  @override
  Result<SSASession, AuthError> getCurrentSession() {
    final s = session;
    if (s != null && s.isValid()) {
      return Result.ok(s);
    }
    return Result.err(AuthError.unauthenticated);
  }

  @override
  Future<AuthResult<SSASession>> getSession() {
    final s = session;
    if (s != null && s.isValid()) {
      if (s.getExpiration() != null && s.getExpiration()!.isBefore(DateTime.now().add(const Duration(minutes: 3)))) {
        _log.i("Session expiring soon, reauthenticating");
        return authenticate();
      }
      return Future.value(Result.ok(s));
    }
    _log.i("Reauthenticating invalid/expired session");
    return authenticate();
  }

  @override
  Future<bool> isAuthenticated() async {
    return session != null && session!.isValid();
  }

  @override
  Future<AuthResult<SSASession>> refreshSession(SSASession currentSession) {
    return authenticate();
  }
}

/// [jwt] holds the opaque stub [sessionId] returned from `/auth/exchange` (Bearer token).
class SSASession implements Session {
  final String jwt;
  final Uint8List sessionKey;
  final int _stubExpUnix;
  final List<String> _stubRoles;
  int counter = 0;

  SSASession.stubBearer({
    required String bearerToken,
    required int expUnix,
    required List<String> roles,
  }) : jwt = bearerToken,
       sessionKey = Uint8List.fromList([1]),
       _stubExpUnix = expUnix,
       _stubRoles = [...roles];

  List<String> getRoles() {
    return [..._stubRoles];
  }

  bool hasRole(String role) {
    return _stubRoles.contains(role);
  }

  bool hasAnyRole(List<String> roles) {
    return _stubRoles.intersects(roles);
  }

  Map<String, dynamic>? getPayload() {
    return null;
  }

  DateTime? getExpiration() {
    return DateTime.fromMillisecondsSinceEpoch(_stubExpUnix * 1000);
  }

  bool isValid() {
    if (jwt.isEmpty || sessionKey.isEmpty) {
      _log.w("Presumptively invalid stub session");
      return false;
    }
    final exp = getExpiration();
    if (exp == null) {
      return false;
    }
    return exp.isAfter(DateTime.now());
  }

  @override
  String toString() {
    return "SSASession(jwt: (opaque stub token), sessionKey: (${sessionKey.length} bytes), counter: $counter, expiration: ${getExpiration()})";
  }
}
