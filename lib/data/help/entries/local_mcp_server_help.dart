/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/app_settings_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const localMcpServerHelpId = "local_mcp_server";
const localMcpServerHelpLink = "?$localMcpServerHelpId";

final helpLocalMcpServer = HelpTopic(
  id: localMcpServerHelpId,
  name: "Local MCP server",
  content: _content,
);

const _content =
"""# Local MCP Server

Shooting Sports Analyst exposes a read-only **ssa-research** MCP server for AI agents and other
tools. It queries your local Analyst database: rating projects, match results tied to those
projects, leaderboards, and shooter histories. It cannot modify ratings, import matches, or change
settings.

## Local research REST API

While the desktop app is running, it also hosts a loopback-only research HTTP API on
`127.0.0.1:6578`, under the `/research` path. That host wraps the same
read-only research facade used by MCP. Agents do not call it directly; the stdio MCP process
health-checks `GET /research/health` and uses the API when the app is available so only one process
holds the Isar database file open.

This local API is intentionally separate from the public SSA server. It is not a preview of the
future public REST API.

## Connection Options

### Headless stdio server (recommended)

Build the standalone binary from the project root:

```
./build-mcp.sh
```

This produces `dist/ssa_mcp_server`. Rebuild after updating research/MCP code so agents pick up
changes. The process speaks MCP over stdio. When the desktop app is running, it prefers the local
research REST API; when the app is not available, it opens AnalystDatabase itself.

Example Cursor / OpenCode configuration:

```json
{
  "mcpServers": {
    "ssa-research": {
      "command": "/path/to/shooting-sports-analyst/dist/ssa_mcp_server",
      "cwd": "/path/to/shooting-sports-analyst",
      "env": {
        "SSA_MCP_DEFAULT_PROJECT": "L2s Main LLR"
      }
    }
  }
}
```

Environment variables:

* **SSA_MCP_DEFAULT_PROJECT** — rating project name used when a tool call omits `project`. Defaults
  to `L2s Main LLR`.
* **SSA_DB_PATH** — optional path to the Analyst database directory for the local-Isar fallback.
  When unset, the server uses the same default location as the desktop app.
* **SSA_RESEARCH_API_BASE** — base URL of the desktop research API (default
  `http://127.0.0.1:6578`).

### In-app localhost MCP (optional)

Enable **Research MCP server** in [app settings]($appSettingsHelpLink). While the application is
running, Analyst can also listen for MCP JSON-RPC over TCP on `127.0.0.1` (default port 8090).
That path uses the app's already-open database in-process; it is separate from the stdio binary
and from the research REST API on port 6578.

The in-app host uses the built-in default project name (`L2s Main LLR`) rather than
`SSA_MCP_DEFAULT_PROJECT`. Most agent workflows should prefer the headless binary.

## Tools

### Projects and discovery

* **list_rating_projects** — List rating projects with their groups, algorithm id/label,
  supported leaderboard sorts, whether the algorithm is stage-based, and the latest match date in
  the project.
* **search_matches** — Fuzzy search completed matches in the local database by name.

### Match results

* **get_match_winners** — Top finishers per division, or per rating group when `byRatingGroup` is
  true. Supports female-only, age, and category filters.
* **get_match_results** — Lean standings for one scoring pool (place, ratio, percentage, points).
  Specify a division, a rating group, or `overall=true`.
* **get_match_scores** — Detailed scores for a pool, including underlying points, time, and hit
  factor. Optionally include per-stage rows and target/penalty event counts.
* **get_competitor_stage_scores** — One competitor's stage-by-stage breakdown at a match, looked up
  by member number or rating id.

### Shooters and ratings

* **search_shooters** — Search competitors in a rating project by name or member number. Returns
  display ratings, location fields, and ids for follow-up calls.
* **get_shooter_summary** — Career summary: current display rating, first/last seen, career
  min/max, and event count.
* **get_rating_history** — Recent match-level rating events (rating change plus finish at each
  match).
* **get_shooter_match_results** — Distinct match finishes derived from rating events. Default order
  is most recent first; use `bestFirst` for career highlights.
* **get_leaderboard** — Sorted leaderboard for one rating group. Sort modes come from
  `supportedSorts` on the project (for example rating, aged rating, last change / movers, trend).
  `seenSince` filters by last activity; when omitted it defaults relative to the project's latest
  match date, not today's calendar date.

## Errors and Limits

Tool failures return JSON error objects in the MCP result. Access is read-only. When the stdio
server is using the desktop research API, results reflect the app's live database; when falling
back to a local Isar open, results reflect that process's snapshot.

For the optional in-app MCP TCP toggle and port, see [app settings]($appSettingsHelpLink).
""";
