/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shelf_plus/shelf_plus.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_client/dart_machine_fingerprinter.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_server/auth_server.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/matches/match_service.dart';
import 'package:shooting_sports_analyst/server/middleware/logger_middleware.dart';
import 'package:shooting_sports_analyst/server/providers.dart';
import 'package:shooting_sports_analyst/version.dart';

final _log = SSALogger("Server Main");

Future<void> main() async {
  print("Starting server.");
  FlutterOrNative.debugModeProvider = ServerDebugProvider();
  FlutterOrNative.machineFingerprintProvider = DartOnlyMachineFingerprinter();

  var configLoader = ConfigLoader();
  await configLoader.readyFuture;
  print("Loaded configuration.");
  var configProvider = ServerConfigProvider(configLoader.config);
  initLogger(configLoader.config, configProvider);


  _log.i("Initialized logger.");

  var database = AnalystDatabase();
  await database.ready;

  _log.i("Server initialization completed.");

  setupKeys();
  shelfRun(init);
}

Handler init() {
  final app = Router().plus;
  app.use(createLoggerMiddleware());
  app.get("/", (request) => "Shooting Sports Analyst API ${VersionInfo.version}");

  // var leagueService = LeagueService([createLoggerMiddleware()]);
  // app.mount("/league", leagueService.router);

  var authService = AuthService([createLoggerMiddleware()]);
  app.mount("/auth", authService.router);

  var matchService = MatchService([createLoggerMiddleware(), createSSAAuthMiddleware()]);
  app.mount("/match", matchService.router);

  return app.call;
}
