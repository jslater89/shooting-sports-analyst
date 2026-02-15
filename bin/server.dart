/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_client/dart_machine_fingerprinter.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_server/auth_server.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/matches/match_service.dart';
import 'package:shooting_sports_analyst/server/matches/registration_service.dart';
import 'package:shooting_sports_analyst/server/middleware/logger_middleware.dart';
import 'package:shooting_sports_analyst/server/providers.dart';
import 'package:shooting_sports_analyst/version.dart';

final _log = SSALogger("Server");

Future<void> main() async {
  print("Starting server.");
  // True only for multi-isolate servers
  var serverModeProvider = ServerDebugProvider(isMultiIsolate: false);
  FlutterOrNative.isolateModeProvider = serverModeProvider;
  FlutterOrNative.debugModeProvider = serverModeProvider;
  FlutterOrNative.machineFingerprintProvider = DartOnlyMachineFingerprinter();

  // Use an LRU match cache for this isolate.
  final lruSize = int.tryParse(Platform.environment["MATCH_LRU_SIZE"] ?? "250") ?? 250;
  HydratedMatchCache(useLru: true, lruCapacity: lruSize);

  var configLoader = ConfigLoader();
  await configLoader.readyFuture;
  print("Loaded configuration.");
  var configProvider = ServerConfigProvider(configLoader.config);
  initLogger(configLoader.config, configProvider);


  _log.i("Initialized logger.");

  var database = AnalystDatabase();
  await database.ready;

  _log.i("Server initialization completed.");

  final authServer = SSAAuthServer();
  await authServer.setupKeys();
  shelfRun(() => init(authServer));
}

Handler init(SSAAuthServer authServer) {
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
