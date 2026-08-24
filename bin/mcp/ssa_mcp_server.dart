/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// SSA research MCP server (stdio).
///
/// Prefers the desktop app's loopback research REST API when available;
/// otherwise opens AnalystDatabase in-process. This is the usual agent path.
///
/// Build: `./build-mcp.sh` → `dist/ssa_mcp_server`
///
/// OpenCode / Cursor mcp example:
/// ```json
/// {
///   "mcpServers": {
///     "ssa-research": {
///       "command": "/path/to/shooting-sports-analyst/dist/ssa_mcp_server",
///       "cwd": "/path/to/shooting-sports-analyst",
///       "env": {
///         "SSA_MCP_DEFAULT_PROJECT": "L2s Main LLR"
///       }
///     }
///   }
/// }
/// ```
///
/// Env: SSA_MCP_DEFAULT_PROJECT, SSA_DB_PATH, SSA_RESEARCH_API_BASE.
library;

import "dart:async";
import "dart:io" as io;

import "package:dart_mcp/stdio.dart";
import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/dtos.dart";
import "package:shooting_sports_analyst/research/http/research_api_constants.dart";
import "package:shooting_sports_analyst/research/http/switching_research_facade.dart";
import "package:shooting_sports_analyst/research/mcp/ssa_research_mcp_server.dart";
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
  final apiBase =
      io.Platform.environment[kResearchApiBaseEnv] ?? kDefaultResearchApiBase;

  _log.i("stdio MCP starting (prefer research API at $apiBase)");
  await ConfigLoader().readyFuture;

  // Keep the server object alive for the process lifetime.
  // ignore: unused_local_variable
  final server = SsaResearchMcpServer(
    stdioChannel(input: io.stdin, output: io.stdout),
    facade: SwitchingResearchFacade(),
    defaultProject: defaultProject,
  );
  await Completer<void>().future;
}
