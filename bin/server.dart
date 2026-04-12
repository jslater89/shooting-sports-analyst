/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_client/dart_machine_fingerprinter.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_server/auth_server.dart';
import 'package:shooting_sports_analyst/closed_sources/ssa_auth_server/auth_server_v2.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/data/cache/constants.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/embedded.dart';
import 'package:shooting_sports_analyst/server/providers.dart';

final _log = SSALogger("Server");

Future<void> main() async {
  print("Starting API server.");

  await startServerStandalone();
}

/// Start the SSA API server in standalone mode, as a single-isolate-in-process server.
Future<void> startServerStandalone() async {
  var serverModeProvider = ServerDebugProvider(isMultiIsolate: false);
  FlutterOrNative.isolateModeProvider = serverModeProvider;
  FlutterOrNative.debugModeProvider = serverModeProvider;
  FlutterOrNative.machineFingerprintProvider = DartOnlyMachineFingerprinter();

  // Use an LRU match cache for this isolate.
  final matchLruSize = int.tryParse(Platform.environment[matchLruSizeEnv] ?? "250") ?? 250;
  HydratedMatchCache(useLru: true, lruCapacity: matchLruSize);

  _log.i("Using LRU cache: match=$matchLruSize");

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
  final authServerV2 = SSAAuthServerV2();
  await authServer.setupKeys();
  await authServerV2.setupKeys();
  await shelfRun(() => initApiServer(authServer, authServerV2));
}
