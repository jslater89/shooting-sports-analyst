// Shared dev-only stub auth: API key exchange, opaque Bearer sessions, no HMAC/replay.
// Used identically for "v1" and "v2" HTTP paths and for both branches of dispatching middleware.
import "dart:convert";
import "dart:io";
import "dart:math";
import "dart:typed_data";

import "package:shelf_plus/shelf_plus.dart";
import "package:shooting_sports_analyst/server/auth/auth_identity.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:toml/toml.dart";

final _log = SSALogger("StubSsaAuth");

/// In-memory sessions (Bearer [sessionId]) keyed by session id.
class _StubSessionRecord {
  final List<String> roles;
  final String? identityName;
  final DateTime expiresAt;

  _StubSessionRecord({
    required this.roles,
    required this.identityName,
    required this.expiresAt,
  });
}

class StubApiKeyEntry {
  final String secret;
  final List<String> roles;
  final String? identityName;

  StubApiKeyEntry({
    required this.secret,
    required this.roles,
    this.identityName,
  });
}

abstract final class StubSsaAuthShared {
  static final Map<String, AuthIdentity> identities = {};
  static final List<StubApiKeyEntry> _apiKeys = [];
  static final Map<String, _StubSessionRecord> _sessions = {};
  static final Random _rng = Random.secure();
  static bool _loadedKeys = false;

  static List<String> knownRoles = ["admin", "uploader", "viewer"];

  static Future<void> loadIdentitiesAndApiKeysOnce() async {
    if (_loadedKeys) {
      return;
    }
    _loadedKeys = true;

    final identityPath = Platform.environment["SSA_AUTH_IDENTITY_PATH"] ?? "db/auth_identities.toml";
    final identityFile = File(identityPath);
    if (!identityFile.existsSync()) {
      identityFile.createSync(recursive: true);
    }
    final identityDoc = await TomlDocument.load(identityPath);
    final identityMap = identityDoc.toMap();
    if (identityMap.containsKey("identities")) {
      final list = identityMap["identities"] as List<dynamic>;
      for (final item in list) {
        final id = AuthIdentity.fromToml(item as Map<String, dynamic>);
        identities[id.identityName] = id;
      }
    }

    _apiKeys.clear();
    final single = Platform.environment["SSA_AUTH_STUB_API_KEY"]?.trim();
    if (single != null && single.isNotEmpty) {
      final rolesJson = Platform.environment["SSA_AUTH_STUB_API_ROLES"] ?? '["admin","uploader"]';
      List<String> roles;
      try {
        roles = (jsonDecode(rolesJson) as List<dynamic>).map((e) => e as String).toList();
      }
      catch (_) {
        roles = ["admin", "uploader"];
      }
      _apiKeys.add(StubApiKeyEntry(secret: single, roles: roles, identityName: Platform.environment["SSA_AUTH_STUB_IDENTITY_NAME"]));
    }

    final keysPath = Platform.environment["SSA_AUTH_STUB_API_KEYS_PATH"] ?? "db/stub_api_keys.toml";
    final keysFile = File(keysPath);
    if (keysFile.existsSync()) {
      final doc = await TomlDocument.load(keysPath);
      final root = doc.toMap();
      if (root.containsKey("api_keys")) {
        final rows = root["api_keys"] as List<dynamic>;
        for (final row in rows) {
          final m = row as Map<String, dynamic>;
          final secret = m["secret"] as String?;
          if (secret == null || secret.isEmpty) {
            continue;
          }
          final rolesRaw = m["roles"] as List<dynamic>? ?? [];
          final roles = rolesRaw.map((e) => e as String).toList();
          final identityName = m["identity_name"] as String?;
          _apiKeys.add(StubApiKeyEntry(secret: secret, roles: roles, identityName: identityName));
        }
      }
    }

    _log.i("Stub SSA auth: ${identities.length} identities, ${_apiKeys.length} API key(s) from env/TOML");
  }

  static StubApiKeyEntry? _matchApiKey(String key) {
    for (final e in _apiKeys) {
      if (e.secret == key) {
        return e;
      }
    }
    return null;
  }

  static Future<Response> handleChallenge(Request req) async {
    await loadIdentitiesAndApiKeysOnce();
    final challenge = base64.encode(Uint8List(32));
    return Response.ok(
      jsonEncode({
        "challenge": challenge,
        "serverEphPub": challenge,
        "signature": "stub",
      }),
      headers: {"content-type": "application/json"},
    );
  }

  static Future<Response> handleExchange(Request req) async {
    await loadIdentitiesAndApiKeysOnce();
    if (_apiKeys.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({
          "error": "stub auth: configure SSA_AUTH_STUB_API_KEY or db/stub_api_keys.toml (see db/stub_api_keys.example.toml)",
        }),
        headers: {"content-type": "application/json"},
      );
    }
    try {
      final bodyStr = await req.readAsString();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      final apiKey = body["apiKey"] as String?;
      if (apiKey == null || apiKey.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "missing apiKey"}),
          headers: {"content-type": "application/json"},
        );
      }
      final match = _matchApiKey(apiKey);
      if (match == null) {
        return Response.unauthorized(
          jsonEncode({"error": "invalid api key"}),
          headers: {"content-type": "application/json"},
        );
      }

      final sessionBytes = Uint8List.fromList(List.generate(32, (_) => _rng.nextInt(256)));
      final sessionId = base64Url.encode(sessionBytes).replaceAll("=", "");
      final expInt = DateTime.now().add(Duration(minutes: 15)).millisecondsSinceEpoch ~/ 1000;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(expInt * 1000);

      _sessions[sessionId] = _StubSessionRecord(
        roles: [...match.roles],
        identityName: match.identityName,
        expiresAt: expiresAt,
      );

      final responseBody = <String, dynamic>{
        "sessionId": sessionId,
        "exp": expInt,
        "roles": [...match.roles],
      };
      if (match.identityName != null) {
        responseBody["identityName"] = match.identityName;
      }

      return Response.ok(
        jsonEncode(responseBody),
        headers: {"content-type": "application/json"},
      );
    }
    catch (e, st) {
      _log.e("Stub exchange error", error: e, stackTrace: st);
      return Response.badRequest(
        body: jsonEncode({"error": "invalid request body"}),
        headers: {"content-type": "application/json"},
      );
    }
  }

  static String? _bearerToken(Request req) {
    final auth = req.headers["authorization"] ?? "";
    if (auth.length < 7) {
      return null;
    }
    if (!auth.toLowerCase().startsWith("bearer ")) {
      return null;
    }
    return auth.substring(7).trim();
  }

  /// Same validation for v1-shaped JWT tokens and v2 opaque session ids: lookup Bearer in session map.
  static Future<Response> handleProtected(Request req, Handler innerHandler) async {
    await loadIdentitiesAndApiKeysOnce();
    final token = _bearerToken(req);
    if (token == null || token.isEmpty) {
      return Response.unauthorized(
        jsonEncode({"error": "missing bearer token"}),
        headers: {"content-type": "application/json"},
      );
    }

    _sessions.removeWhere((_, v) => v.expiresAt.isBefore(DateTime.now()));
    final rec = _sessions[token];
    if (rec == null) {
      return Response.unauthorized(
        jsonEncode({"error": "invalid or expired session"}),
        headers: {"content-type": "application/json"},
      );
    }

    final bodyBytes = <int>[];
    await for (final chunk in req.read()) {
      bodyBytes.addAll(chunk);
    }

    final authHeaders = <String, String>{};
    if (rec.identityName != null) {
      final identity = identities[rec.identityName!];
      if (identity != null) {
        authHeaders["x-identity-name"] = identity.identityName;
        authHeaders["x-identity-roles"] = jsonEncode(identity.roles);
      }
      else {
        authHeaders["x-identity-name"] = rec.identityName!;
        authHeaders["x-identity-roles"] = jsonEncode(rec.roles);
      }
    }
    else if (rec.roles.isNotEmpty) {
      authHeaders["x-identity-name"] = "stub";
      authHeaders["x-identity-roles"] = jsonEncode(rec.roles);
    }

    final rebuilt = req.change(body: bodyBytes, headers: authHeaders);
    return innerHandler(rebuilt);
  }
}
