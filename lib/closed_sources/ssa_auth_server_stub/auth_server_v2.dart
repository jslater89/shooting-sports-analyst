// Open stub: "v2" HTTP surface and dispatching middleware — same [StubSsaAuthShared] as v1 stub.
import "package:shelf_plus/shelf_plus.dart";
import "package:shooting_sports_analyst/closed_sources/ssa_auth_server/auth_server.dart";
import "package:shooting_sports_analyst/closed_sources/ssa_auth_server/stub_auth_shared.dart";
import "package:shooting_sports_analyst/server/auth/auth_identity.dart";

class SSAAuthServerV2 {
  Map<String, AuthIdentity> get knownIdentities => StubSsaAuthShared.identities;

  List<String> knownRoles = StubSsaAuthShared.knownRoles;

  Future<void> setupKeys() async {
    await StubSsaAuthShared.loadIdentitiesAndApiKeysOnce();
  }

  Future<Response> handleChallengeV2(Request req) {
    return StubSsaAuthShared.handleChallenge(req);
  }

  Future<Response> handleExchangeV2(Request req) {
    return StubSsaAuthShared.handleExchange(req);
  }

  Future<Response> handleProtectedApiV2(Request req, Handler innerHandler) {
    return StubSsaAuthShared.handleProtected(req, innerHandler);
  }
}

class AuthServiceV2 {
  final SSAAuthServerV2 authServer;
  final router = Router().plus;

  AuthServiceV2([List<Middleware> middleware = const []]) : authServer = SSAAuthServerV2() {
    for (final m in middleware) {
      router.use(m);
    }
    router.get("/challenge", authServer.handleChallengeV2);
    router.post("/exchange", authServer.handleExchangeV2);
  }

  AuthServiceV2.withServer(this.authServer, [List<Middleware> middleware = const []]) {
    for (final m in middleware) {
      router.use(m);
    }
    router.get("/challenge", authServer.handleChallengeV2);
    router.post("/exchange", authServer.handleExchangeV2);
  }
}

/// Stub: JWT-shaped (three-part) and opaque Bearer tokens use the same session lookup.
Middleware createDispatchingSSAAuthMiddleware({
  required SSAAuthServer authServerV1,
  required SSAAuthServerV2 authServerV2,
}) {
  assert(identical(authServerV1.knownIdentities, authServerV2.knownIdentities));
  return (Handler innerHandler) {
    return (Request request) {
      return StubSsaAuthShared.handleProtected(request, innerHandler);
    };
  };
}
