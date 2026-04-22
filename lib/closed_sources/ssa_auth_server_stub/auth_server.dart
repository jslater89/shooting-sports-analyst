// Open stub: dev-only SSA auth server "v1" surface (identical behavior to stub v2 via [StubSsaAuthShared]).
import "package:shelf_plus/shelf_plus.dart";
import "stub_auth_shared.dart";
import "package:shooting_sports_analyst/server/auth/auth_identity.dart";

class SSAAuthServer {
  Map<String, AuthIdentity> get knownIdentities => StubSsaAuthShared.identities;

  List<String> knownRoles = StubSsaAuthShared.knownRoles;

  Future<void> setupKeys() async {
    await StubSsaAuthShared.loadIdentitiesAndApiKeysOnce();
  }

  Future<Response> handleChallenge(Request req) {
    return StubSsaAuthShared.handleChallenge(req);
  }

  Future<Response> handleExchange(Request req) {
    return StubSsaAuthShared.handleExchange(req);
  }

  Future<Response> handleProtectedApi(Request req, Handler innerHandler) {
    return StubSsaAuthShared.handleProtected(req, innerHandler);
  }
}

class AuthService {
  final SSAAuthServer authServer;
  final router = Router().plus;

  AuthService([List<Middleware> middleware = const []]) : authServer = SSAAuthServer() {
    for (final m in middleware) {
      router.use(m);
    }
    router.get("/challenge", authServer.handleChallenge);
    router.post("/exchange", authServer.handleExchange);
  }

  AuthService.withServer(this.authServer, [List<Middleware> middleware = const []]) {
    for (final m in middleware) {
      router.use(m);
    }
    router.get("/challenge", authServer.handleChallenge);
    router.post("/exchange", authServer.handleExchange);
  }
}

Middleware createSSAAuthMiddleware(SSAAuthServer authServer) {
  return (Handler innerHandler) {
    return (Request request) {
      return authServer.handleProtectedApi(request, innerHandler);
    };
  };
}
