import 'package:shelf_plus/shelf_plus.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_client/dart_machine_fingerprinter.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_server/auth_server.dart';
import 'package:shooting_sports_analyst/data/cache/match/isolate_match_cache.dart';
import 'package:shooting_sports_analyst/data/cache/match/match_cache.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/matches/match_service.dart';
import 'package:shooting_sports_analyst/server/matches/registration_service.dart';
import 'package:shooting_sports_analyst/server/middleware/logger_middleware.dart';
import 'package:shooting_sports_analyst/server/providers.dart';
import 'package:shooting_sports_analyst/version.dart';

final _log = SSALogger("EmbeddedServer");

class EmbeddedServerStartData {
  IsolateStartData startData;
  bool devMode;
  String? bindAddress;
  int? bindPort;

  EmbeddedServerStartData({required this.startData, required this.devMode, this.bindAddress, this.bindPort});
}

/// Start the SSA API server in embedded mode, as an isolate in a multi-isolate server.
void startServerEmbedded(EmbeddedServerStartData startData) async {
  SSALogger.setupSendPort(startData.startData.logPort, isolateName: startData.startData.isolateId);

  var serverModeProvider = ServerDebugProvider(isMultiIsolate: true);
  FlutterOrNative.isolateModeProvider = serverModeProvider;
  FlutterOrNative.debugModeProvider = serverModeProvider;
  FlutterOrNative.machineFingerprintProvider = DartOnlyMachineFingerprinter();

  // Connect to the match cache server isolate.
  // Since we did the logger setup above, we don't need to do 'mainIsolate: false' in this call.
  final matchCacheClient = await IsolateMatchCacheClient.startOnCurrentIsolate(startData.startData);
  await matchCacheClient.ready;
  MatchCache.setInstance(matchCacheClient);
  _log.i("Match cache client ready.");

  _log.i("Initialized logger.");

  var database = AnalystDatabase();
  await database.ready;

  _log.i("Server initialization completed.");

  final authServer = SSAAuthServer();
  await authServer.setupKeys();
  await shelfRun(() => initApiServer(authServer),
    defaultBindAddress: startData.bindAddress ?? "0.0.0.0",
    defaultBindPort: startData.bindPort ?? 8081,
    defaultEnableHotReload: startData.devMode,
  );
}

Handler initApiServer(SSAAuthServer authServer) {
  final app = Router().plus;
  app.use(createLoggerMiddleware());
  app.get("/", (request) => "Shooting Sports Analyst API ${VersionInfo.version}");

  // var leagueService = LeagueService([createLoggerMiddleware()]);
  // app.mount("/league", leagueService.router);

  var authService = AuthService.withServer(authServer, [createLoggerMiddleware()]);
  app.mount("/auth", authService.router);

  var matchService = MatchService([createLoggerMiddleware(), createSSAAuthMiddleware(authServer)]);
  app.mount("/match", matchService.router);

  var registrationService = RegistrationService([createLoggerMiddleware(), createSSAAuthMiddleware(authServer)]);
  app.mount("/registration", registrationService.router);

  return app.call;
}
