/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:async";
import "dart:io";

import "package:shelf/shelf_io.dart" as shelf_io;
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/http/research_api_constants.dart";
import "package:shooting_sports_analyst/research/http/research_api_router.dart";
import "package:shooting_sports_analyst/research/research_facade.dart";

final _log = SSALogger("ResearchApiHost");

/// Loopback-only local research REST host owned by the desktop app process.
///
/// Always started when the app opens the database. The stdio MCP process
/// health-checks this host and prefers it over opening Isar itself.
class ResearchApiHost {
  static ResearchApiHost? _instance;
  factory ResearchApiHost() {
    _instance ??= ResearchApiHost._();
    return _instance!;
  }

  ResearchApiHost._();

  HttpServer? _server;
  bool _started = false;

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;

  /// Bind [InternetAddress.loopbackIPv4] on [port]. Failures are logged and
  /// ignored so a port conflict does not block app startup.
  Future<void> start({int port = kDefaultResearchApiPort}) async {
    if(_started) {
      return;
    }
    _started = true;

    await AnalystDatabase().ready;
    final facade = ResearchFacade(AnalystDatabase());
    final handler = buildResearchApiRouter(facade).call;

    try {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        port,
      );
      _log.i("Research API listening on http://127.0.0.1:${_server!.port}$kResearchApiPathPrefix");
    }
    catch(e, st) {
      _log.w(
        "Failed to start research API on port $port (MCP may use another listener)",
        error: e,
        stackTrace: st,
      );
      _server = null;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _started = false;
    if(server != null) {
      await server.close(force: true);
      _log.i("Research API stopped");
    }
  }
}
