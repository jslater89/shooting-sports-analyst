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

## Connection Options

### Headless stdio server (recommended)

Build the standalone binary from the project root:

```
./build-mcp.sh
```

This produces `dist/ssa_mcp_server`. The process opens AnalystDatabase directly and speaks MCP over
stdio. This is the usual setup for Cursor, OpenCode, and similar agents.

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
* **SSA_DB_PATH** — optional path to the Analyst database directory. When unset, the server uses the
  same default location as the desktop app.

### In-app localhost server

Enable **Research MCP server** in [app settings]($appSettingsHelpLink). While the application is
running, Analyst listens on `127.0.0.1` only (default port 8090, configurable). Clients connect
over TCP with the same MCP JSON-RPC framing as stdio.

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

Tool failures return JSON error objects in the MCP result. All access is read-only against the
database snapshot available when the server started (headless) or when the app opened the database
(in-app host).

For enable/disable and port settings, see [app settings]($appSettingsHelpLink).
""";
