/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:async";
import "dart:io";

import "package:dart_mcp/stdio.dart";
import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/dtos.dart";
import "package:shooting_sports_analyst/research/mcp/ssa_research_mcp_server.dart";
import "package:shooting_sports_analyst/research/research_facade.dart";

final _log = SSALogger("ResearchMcpHost");

/// Optional localhost MCP host owned by the Flutter app process.
///
/// Speaks the same newline-delimited MCP JSON-RPC framing as stdio.
/// The headless [bin/mcp/ssa_mcp_server.dart] opens the database itself
/// rather than proxying here; that has been the convenient path in practice.
class ResearchMcpHost {
  static ResearchMcpHost? _instance;
  factory ResearchMcpHost() {
    _instance ??= ResearchMcpHost._();
    return _instance!;
  }

  ResearchMcpHost._();

  ServerSocket? _server;
  final List<SsaResearchMcpServer> _sessions = [];
  StreamSubscription<Socket>? _acceptSub;
  bool _initialized = false;
  late SerializedConfig _config;

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _config = FlutterOrNative.configProvider.currentConfig;
    FlutterOrNative.configProvider.addListener((config) {
      _config = config;
      unawaited(_syncFromConfig());
    });
    await _syncFromConfig();
  }

  Future<void> _syncFromConfig() async {
    if (!_config.researchMcpServerEnabled) {
      await stop();
      return;
    }
    final desiredPort = _config.researchMcpServerPort;
    if (_server != null && _server!.port == desiredPort) {
      return;
    }
    await stop();
    await start(port: desiredPort);
  }

  Future<void> start({int port = kDefaultResearchMcpPort}) async {
    if (_server != null) {
      return;
    }
    await AnalystDatabase().ready;
    final facade = ResearchFacade(AnalystDatabase());
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _log.i("Research MCP listening on 127.0.0.1:${_server!.port}");
      _acceptSub = _server!.listen((socket) async {
        _log.i("Research MCP client connected from ${socket.remoteAddress.address}:${socket.remotePort}");
        final channel = stdioChannel(input: socket, output: socket);
        final session = SsaResearchMcpServer(
          channel,
          facade: facade,
          defaultProject: kDefaultResearchProjectName,
        );
        final tools = await session.listTools();
        _log.i("Available tools: ${tools.tools.map((t) => t.name).join(", ")}");
        _sessions.add(session);
        socket.done.then((_) {
          _sessions.remove(session);
          _log.i("Research MCP client disconnected");
        });
      });
    } catch (e, st) {
      _log.e("Failed to start research MCP on port $port", error: e, stackTrace: st);
      _server = null;
    }
  }

  Future<void> stop() async {
    await _acceptSub?.cancel();
    _acceptSub = null;
    _sessions.clear();
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close();
      _log.i("Research MCP stopped");
    }
  }
}
