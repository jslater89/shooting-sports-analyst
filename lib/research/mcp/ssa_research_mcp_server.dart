/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:async";
import "dart:convert";

import "package:dart_mcp/server.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/dtos.dart";
import "package:shooting_sports_analyst/research/mcp/request_args.dart";
import "package:shooting_sports_analyst/research/research_facade.dart";
import "package:stream_channel/stream_channel.dart";

final _log = SSALogger("SsaResearchMcp");

/// Shared MCP tools over [ResearchFacade].
///
/// Hosted by the headless stdio server ([bin/mcp/ssa_mcp_server.dart]), and by
/// the Flutter app over a localhost TCP socket when research MCP is enabled.
base class SsaResearchMcpServer extends MCPServer with ToolsSupport {
  SsaResearchMcpServer(
    StreamChannel<String> channel, {
    required ResearchFacade facade,
    this.defaultProject = kDefaultResearchProjectName,
  })  : _facade = facade,
        super.fromStreamChannel(
          channel,
          implementation: Implementation(
            name: "ssa-research",
            version: "0.1.0",
          ),
          instructions:
              "Read-only Shooting Sports Analyst research tools. Default rating "
              "project is '$defaultProject'. Prefer list_rating_projects for "
              "algorithm/supportedSorts metadata, search_matches then "
              "get_match_winners / get_shooter_summary. Use get_leaderboard for "
              "sorted group rankings (movers = sort=lastChange). Use get_match_scores / "
              "get_competitor_stage_scores for stage results and hit/penalty counts. "
              "Use get_rating_history for rating trajectory, and "
              "get_shooter_match_results (bestFirst=true for career highlights) "
              "for a competitor's match list.",
        ) {
    registerTool(_listProjectsTool, _listProjects);
    registerTool(_searchMatchesTool, _searchMatches);
    registerTool(_getMatchWinnersTool, _getMatchWinners);
    registerTool(_getMatchResultsTool, _getMatchResults);
    registerTool(_getMatchScoresTool, _getMatchScores);
    registerTool(_getCompetitorStageScoresTool, _getCompetitorStageScores);
    registerTool(_searchShootersTool, _searchShooters);
    registerTool(_getShooterSummaryTool, _getShooterSummary);
    registerTool(_getRatingHistoryTool, _getRatingHistory);
    registerTool(_getShooterMatchResultsTool, _getShooterMatchResults);
    registerTool(_getLeaderboardTool, _getLeaderboard);
  }

  final String defaultProject;
  final ResearchFacade _facade;

  FutureOr<CallToolResult> _listProjects(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, ListRatingProjectsArgs.fromJson);
      final projects = await _facade.listRatingProjects(
        name: args.name,
        limit: args.limit,
      );
      return {"projects": projects.map((p) => p.toJson()).toList()};
    });
  }

  FutureOr<CallToolResult> _searchMatches(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, SearchMatchesArgs.fromJson);
      final matches = await _facade.searchMatches(
        query: args.query,
        limit: args.limit,
      );
      return {"matches": matches.map((m) => m.toJson()).toList()};
    });
  }

  FutureOr<CallToolResult> _getMatchWinners(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, GetMatchWinnersArgs.fromJson);
      final result = await _facade.getMatchWinners(
        matchId: args.matchId,
        matchQuery: args.matchQuery,
        projectName: args.project ?? defaultProject,
        byRatingGroup: args.byRatingGroup,
        topN: args.topN,
      );
      return result.toJson();
    });
  }

  FutureOr<CallToolResult> _getMatchResults(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, GetMatchResultsArgs.fromJson);
      final result = await _facade.getMatchResults(
        matchId: args.matchId,
        matchQuery: args.matchQuery,
        projectName: args.project ?? defaultProject,
        division: args.division,
        groupUuid: args.groupUuid,
        groupName: args.group,
        femaleOnly: args.femaleOnly,
        ageCategory: args.ageCategory,
        category: args.category,
        topN: args.topN,
        overall: args.overall,
      );
      return result.toJson();
    });
  }

  FutureOr<CallToolResult> _getMatchScores(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, GetMatchScoresArgs.fromJson);
      final result = await _facade.getMatchScores(
        matchId: args.matchId,
        matchQuery: args.matchQuery,
        projectName: args.project ?? defaultProject,
        division: args.division,
        groupUuid: args.groupUuid,
        groupName: args.group,
        femaleOnly: args.femaleOnly,
        ageCategory: args.ageCategory,
        category: args.category,
        topN: args.topN,
        overall: args.overall,
        includeStages: args.includeStages,
        includeScoringEventCounts: args.includeScoringEventCounts,
      );
      return result.toJson();
    });
  }

  FutureOr<CallToolResult> _getCompetitorStageScores(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, GetCompetitorStageScoresArgs.fromJson);
      final result = await _facade.getCompetitorStageScores(
        matchId: args.matchId,
        matchQuery: args.matchQuery,
        projectName: args.project ?? defaultProject,
        memberNumber: args.memberNumber,
        ratingId: args.ratingId,
        division: args.division,
        groupUuid: args.groupUuid,
        groupName: args.group,
        overall: args.overall,
        includeScoringEventCounts: args.includeScoringEventCounts,
      );
      return result.toJson();
    });
  }

  FutureOr<CallToolResult> _searchShooters(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, SearchShootersArgs.fromJson);
      final hits = await _facade.searchShooters(
        query: args.query,
        projectName: args.project ?? defaultProject,
        groupName: args.group,
        groupUuid: args.groupUuid,
        memberNumber: args.memberNumber,
        limit: args.limit,
        includeInternal: args.includeInternal,
      );
      return {"shooters": hits.map((h) => h.toJson()).toList()};
    });
  }

  FutureOr<CallToolResult> _getShooterSummary(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, ShooterLookupArgs.fromJson);
      final summary = await _facade.getShooterSummary(
        projectName: args.project ?? defaultProject,
        groupName: args.group,
        groupUuid: args.groupUuid,
        memberNumber: args.memberNumber,
        ratingId: args.ratingId,
        includeInternal: args.includeInternal,
      );
      return summary.toJson();
    });
  }

  FutureOr<CallToolResult> _getRatingHistory(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, ShooterLookupArgs.fromJson);
      final events = await _facade.getRatingHistory(
        projectName: args.project ?? defaultProject,
        groupName: args.group,
        groupUuid: args.groupUuid,
        memberNumber: args.memberNumber,
        ratingId: args.ratingId,
        limit: args.limit ?? 50,
        includeInternal: args.includeInternal,
      );
      return {"events": events.map((e) => e.toJson()).toList()};
    });
  }

  FutureOr<CallToolResult> _getShooterMatchResults(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, ShooterLookupArgs.fromJson);
      final results = await _facade.getShooterMatchResults(
        projectName: args.project ?? defaultProject,
        groupName: args.group,
        groupUuid: args.groupUuid,
        memberNumber: args.memberNumber,
        ratingId: args.ratingId,
        limit: args.limit ?? 50,
        includeInternal: args.includeInternal,
        bestFirst: args.bestFirst,
      );
      return {"results": results.map((r) => r.toJson()).toList()};
    });
  }

  FutureOr<CallToolResult> _getLeaderboard(CallToolRequest request) {
    return _run(() async {
      final args = parseMcpArgs(request.arguments, GetLeaderboardArgs.fromJson);
      final result = await _facade.getLeaderboard(
        projectName: args.project ?? defaultProject,
        groupName: args.group,
        groupUuid: args.groupUuid,
        sort: args.sort,
        limit: args.limit,
        minMatches: args.minMatches,
        seenSince: args.seenSince,
        changeSince: args.changeSince,
      );
      return result.toJson();
    });
  }

  Future<CallToolResult> _run(Future<Map<String, dynamic>> Function() body) async {
    try {
      final data = await body();
      return CallToolResult(
        content: [TextContent(text: jsonEncode(data))],
      );
    } catch (e, st) {
      _log.w("Tool error", error: e, stackTrace: st);
      return CallToolResult(
        isError: true,
        content: [TextContent(text: jsonEncode(researchErrorJson(e)))],
      );
    }
  }

  final _listProjectsTool = Tool(
    name: "list_rating_projects",
    description:
        "List rating projects with groups, algorithm id/label, supportedSorts, "
        "byStage, and latestMatchDate (anchor for leaderboard seenSince defaults).",
    inputSchema: Schema.object(
      properties: {
        "name": Schema.string(description: "Optional name filter"),
        "limit": Schema.int(description: "Max projects (default 50)"),
      },
    ),
  );

  final _searchMatchesTool = Tool(
    name: "search_matches",
    description: "Search matches by name (fuzzy text search).",
    inputSchema: Schema.object(
      properties: {
        "query": Schema.string(description: "Match name query, e.g. '2024 Area 5'"),
        "limit": Schema.int(description: "Max results (default 10)"),
      },
      required: ["query"],
    ),
  );

  final _getMatchWinnersTool = Tool(
    name: "get_match_winners",
    description:
        "Get top finishers per division (default) or per rating group for a match. "
        "Pass matchId from search_matches, or matchQuery. Includes female/age/category flags.",
    inputSchema: Schema.object(
      properties: {
        "matchId": Schema.int(description: "Database match id"),
        "matchQuery": Schema.string(description: "Match name query if matchId unknown"),
        "project": Schema.string(description: "Rating project name (for byRatingGroup)"),
        "byRatingGroup": Schema.bool(
          description: "If true, score by project rating-group filters instead of each division",
        ),
        "topN": Schema.int(description: "Places to return per division/group (default 1)"),
      },
    ),
  );

  final _getMatchResultsTool = Tool(
    name: "get_match_results",
    description:
        "Lean standings for one scoring pool in a match (place/ratio/percentage/points). "
        "Provide division, a rating group (group/groupUuid), or overall=true. For stage "
        "scores or hit/penalty counts, use get_match_scores or get_competitor_stage_scores.",
    inputSchema: Schema.object(
      properties: {
        "matchId": Schema.int(description: "Database match id"),
        "matchQuery": Schema.string(description: "Match name query if matchId unknown"),
        "division": Schema.string(description: "Division name, e.g. 'Carry Optics'"),
        "group": Schema.string(description: "Rating group name filter"),
        "groupUuid": Schema.string(description: "Rating group uuid"),
        "project": Schema.string(description: "Rating project when using a group"),
        "overall": Schema.bool(description: "Score the whole match roster as one pool"),
        "femaleOnly": Schema.bool(description: "Restrict pool to female competitors"),
        "ageCategory": Schema.string(description: "Age category name, e.g. 'Senior'"),
        "category": Schema.string(description: "Competitor category name, e.g. 'Law Enforcement'"),
        "topN": Schema.int(description: "Limit rows (default 10; 0 = entire pool)"),
      },
    ),
  );

  final _getMatchScoresTool = Tool(
    name: "get_match_scores",
    description:
        "Detailed scores for one scoring pool. Always includes place, ratio, percentage, "
        "and underlying points/finalTime/hitFactor (see scoringKind: hitFactor|timePlus|points). "
        "Set includeStages for per-stage rows. Set includeScoringEventCounts for target/penalty "
        "event maps (A/C/D/M/NS, procedurals, etc.) on match totals, and on stages when "
        "includeStages is also true. hasPenalties counts non-target penalty events only; "
        "misses/NS are in targetEvents.",
    inputSchema: Schema.object(
      properties: {
        "matchId": Schema.int(description: "Database match id"),
        "matchQuery": Schema.string(description: "Match name query if matchId unknown"),
        "division": Schema.string(description: "Division name, e.g. 'Limited Optics'"),
        "group": Schema.string(description: "Rating group name filter"),
        "groupUuid": Schema.string(description: "Rating group uuid"),
        "project": Schema.string(description: "Rating project when using a group"),
        "overall": Schema.bool(description: "Score the whole match roster as one pool"),
        "femaleOnly": Schema.bool(description: "Restrict pool to female competitors"),
        "ageCategory": Schema.string(description: "Age category name, e.g. 'Senior'"),
        "category": Schema.string(description: "Competitor category name"),
        "topN": Schema.int(description: "Limit rows (default 10; 0 = entire pool)"),
        "includeStages": Schema.bool(description: "Nest stage score rows (default false)"),
        "includeScoringEventCounts": Schema.bool(
          description: "Include target/penalty event count maps (default false)",
        ),
      },
    ),
  );

  final _getCompetitorStageScoresTool = Tool(
    name: "get_competitor_stage_scores",
    description:
        "One competitor's stage scores at a match (stage wins, HF/times per stage). "
        "Defaults scoring pool to the competitor's entered division. Always returns "
        "percentage plus underlying points/finalTime/hitFactor. Optional "
        "includeScoringEventCounts for hit/penalty maps.",
    inputSchema: Schema.object(
      properties: {
        "matchId": Schema.int(description: "Database match id"),
        "matchQuery": Schema.string(description: "Match name query if matchId unknown"),
        "memberNumber": Schema.string(description: "Competitor member number"),
        "ratingId": Schema.int(description: "DbShooterRating id; resolves member number"),
        "division": Schema.string(description: "Override scoring pool division"),
        "group": Schema.string(description: "Rating group name filter"),
        "groupUuid": Schema.string(description: "Rating group uuid"),
        "project": Schema.string(description: "Rating project when using ratingId/group"),
        "overall": Schema.bool(description: "Score against the whole match roster"),
        "includeScoringEventCounts": Schema.bool(
          description: "Include target/penalty event count maps (default false)",
        ),
      },
    ),
  );

  final _searchShootersTool = Tool(
    name: "search_shooters",
    description:
        "Search shooters in a rating project by name or member number. "
        "Returns display/scaled ratings, location (region/regionSubdivision), "
        "and rating ids useful for summary/history tools.",
    inputSchema: Schema.object(
      properties: {
        "query": Schema.string(description: "Name query (min 2 chars) if not using memberNumber"),
        "memberNumber": Schema.string(description: "Exact member number lookup"),
        "project": Schema.string(description: "Rating project name"),
        "group": Schema.string(description: "Optional rating group name filter"),
        "groupUuid": Schema.string(description: "Optional rating group uuid"),
        "limit": Schema.int(description: "Max results (default 20)"),
        "includeInternal": Schema.bool(
          description: "Include raw/internal rating fields (default false)",
        ),
      },
    ),
  );

  final _getShooterSummaryTool = Tool(
    name: "get_shooter_summary",
    description:
        "Career/rating summary for a shooter (display rating, location, first/last seen, "
        "career min/max, event count).",
    inputSchema: Schema.object(
      properties: {
        "memberNumber": Schema.string(),
        "ratingId": Schema.int(description: "DbShooterRating id from search_shooters"),
        "project": Schema.string(),
        "group": Schema.string(),
        "groupUuid": Schema.string(),
        "includeInternal": Schema.bool(
          description: "Include raw/internal rating fields (default false)",
        ),
      },
    ),
  );

  final _getRatingHistoryTool = Tool(
    name: "get_rating_history",
    description:
        "Recent match-level rating events (display rating change + match finish) for a shooter. "
        "Includes division and classification entered at each match when available "
        "(useful for multi-division rating groups).",
    inputSchema: Schema.object(
      properties: {
        "memberNumber": Schema.string(),
        "ratingId": Schema.int(),
        "project": Schema.string(),
        "group": Schema.string(),
        "groupUuid": Schema.string(),
        "limit": Schema.int(description: "Max events (default 50)"),
        "includeInternal": Schema.bool(
          description: "Include raw/internal rating fields (default false)",
        ),
      },
    ),
  );

  final _getShooterMatchResultsTool = Tool(
    name: "get_shooter_match_results",
    description:
        "Distinct match finishes for a shooter derived from rating events. "
        "Default order is most recent first. Set bestFirst for career highlights "
        "(highest percentage, then best place). Includes division and classification "
        "entered at each match when available.",
    inputSchema: Schema.object(
      properties: {
        "memberNumber": Schema.string(),
        "ratingId": Schema.int(),
        "project": Schema.string(),
        "group": Schema.string(),
        "groupUuid": Schema.string(),
        "limit": Schema.int(description: "Max matches (default 50)"),
        "bestFirst": Schema.bool(
          description:
              "If true, return the best finishes first (percentage, then place) "
              "instead of most recent. Default false.",
        ),
        "includeInternal": Schema.bool(
          description: "Include raw/internal rating fields (default false)",
        ),
      },
    ),
  );

  final _getLeaderboardTool = Tool(
    name: "get_leaderboard",
    description:
        "Sorted rating leaderboard for one project group. Use list_rating_projects "
        "for supportedSorts (e.g. rating, agedRating, lastChange/movers, trend). "
        "seenSince filters by competitor lastSeen; when omitted it defaults to "
        "January 1 of the year before the project's latest match date (not today). "
        "Pass seenSince=1970-01-01 for no recency filter. minMatches uses the "
        "algorithm's matchCount when available, else history length.",
    inputSchema: Schema.object(
      properties: {
        "project": Schema.string(description: "Rating project name"),
        "group": Schema.string(description: "Rating group name (required if multiple groups)"),
        "groupUuid": Schema.string(description: "Rating group uuid"),
        "sort": Schema.string(
          description:
              "Sort mode id from supportedSorts (default: algorithm's first). "
              "Aliases: movers -> lastChange",
        ),
        "limit": Schema.int(description: "Max rows (default 25)"),
        "minMatches": Schema.int(
          description:
              "Minimum matches/history length (default 0). Uses matchCount when "
              "the algorithm tracks it; otherwise rating history length.",
        ),
        "seenSince": Schema.string(
          description:
              "YYYY-MM-DD inclusive lastSeen cutoff. Default: Jan 1 of the year "
              "before the project's latest match (relative to data, not today).",
        ),
        "changeSince": Schema.string(
          description: "YYYY-MM-DD optional date for trend-since-date sorting",
        ),
      },
    ),
  );
}
