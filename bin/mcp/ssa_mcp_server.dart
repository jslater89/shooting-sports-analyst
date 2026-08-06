/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// SSA research MCP shim (stdio).
///
/// Cursor always launches this process. If the Flutter app has the research MCP
/// host enabled, this proxies stdio onto that localhost socket (app owns Isar).
/// Otherwise it opens AnalystDatabase and serves MCP tools directly.
///
/// Obsidian / Cursor mcp.json example:
/// ```json
/// {
///   "mcpServers": {
///     "ssa-research": {
///       "command": "dart",
///       "args": ["run", "bin/mcp/ssa_mcp_server.dart"],
///       "cwd": "/path/to/shooting-sports-analyst",
///       "env": {
///         "SSA_MCP_DEFAULT_PROJECT": "L2s Main LLR"
///       }
///     }
///   }
/// }
/// ```
///
/// Env: SSA_MCP_DEFAULT_PROJECT, SSA_DB_PATH, SSA_RESEARCH_MCP_PORT (default 8090).
///
/// Config.toml (Flutter app): researchMcpServerEnabled, researchMcpServerPort.
library;

import "dart:async";
import "dart:io" as io;

import "package:dart_mcp/stdio.dart";
import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/dtos.dart";
import "package:shooting_sports_analyst/research/mcp/ssa_research_mcp_server.dart";
import "package:shooting_sports_analyst/research/research_facade.dart";
import "package:shooting_sports_analyst/server/providers.dart";

final _log = SSALogger("SsaMcpShim");

Future<void> main(List<String> args) async {
  FlutterOrNative.debugModeProvider = ServerDebugProvider();
  FlutterOrNative.isolateModeProvider = ServerDebugProvider(isMultiIsolate: false);
  SSALogger.consoleOutput = false;
  SSALogger.fileOutput = true;
  await _log.ready;

  final defaultProject =
      io.Platform.environment["SSA_MCP_DEFAULT_PROJECT"] ?? kDefaultResearchProjectName;
  final port = int.tryParse(io.Platform.environment["SSA_RESEARCH_MCP_PORT"] ?? "") ??
      kDefaultResearchMcpPort;

  if (await _proxyToAppMcp(port)) {
    return;
  }

  _log.i("No in-app research MCP on 127.0.0.1:$port; opening AnalystDatabase");
  FlutterOrNative.debugModeProvider = ServerDebugProvider();
  FlutterOrNative.isolateModeProvider = ServerDebugProvider(isMultiIsolate: false);
  await ConfigLoader().readyFuture;

  final dbPath = io.Platform.environment["SSA_DB_PATH"];
  final AnalystDatabase db;
  if (dbPath != null && dbPath.isNotEmpty) {
    db = AnalystDatabase.path(dbPath);
  }
  else {
    db = AnalystDatabase();
  }
  await db.ready;

  // Keep the server object alive for the process lifetime.
  // ignore: unused_local_variable
  final server = SsaResearchMcpServer(
    stdioChannel(input: io.stdin, output: io.stdout),
    facade: ResearchFacade(db),
    defaultProject: defaultProject,
  );
  await Completer<void>().future;
}

/// Pipe Cursor stdio to the Flutter app's MCP socket. Returns false if not listening.
Future<bool> _proxyToAppMcp(int port) async {
  io.Socket socket;
  try {
    socket = await io.Socket.connect(
      io.InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(milliseconds: 350),
    );
  } catch (_) {
    return false;
  }

  _log.i("Proxying stdio MCP to in-app research MCP at 127.0.0.1:$port");

  final done = Completer<void>();

  socket.listen(
    (data) {
      io.stdout.add(data);
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    onError: (Object e, StackTrace st) {
      _log.w("App MCP socket error", error: e, stackTrace: st);
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );

  io.stdin.listen(
    (data) {
      socket.add(data);
    },
    onDone: () {
      socket.destroy();
      if (!done.isCompleted) done.complete();
    },
    onError: (Object e, StackTrace st) {
      _log.w("Stdin error while proxying", error: e, stackTrace: st);
      socket.destroy();
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );

  await done.future;
  return true;
}
