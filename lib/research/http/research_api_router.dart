/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";

import "package:shelf_plus/shelf_plus.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/dtos.dart";
import "package:shooting_sports_analyst/research/http/research_api_constants.dart";
import "package:shooting_sports_analyst/research/mcp/request_args.dart";
import "package:shooting_sports_analyst/research/research_queries.dart";

final _log = SSALogger("ResearchApiRouter");

/// Shelf router that wraps [ResearchQueries] with MCP-compatible JSON payloads.
RouterPlus buildResearchApiRouter(ResearchQueries facade) {
  final router = Router().plus;

  router.get(kResearchApiHealthPath, (Request request) {
    return _jsonOk({
      "ok": true,
      "service": kResearchApiServiceName,
    });
  });

  router.get("$kResearchApiPathPrefix/projects", (Request request) async {
    return _run(() async {
      final args = ListRatingProjectsArgs.fromJson(_queryMap(request));
      final projects = await facade.listRatingProjects(
        name: args.name,
        limit: args.limit,
      );
      return {"projects": projects.map((p) => p.toJson()).toList()};
    });
  });

  router.get("$kResearchApiPathPrefix/matches", (Request request) async {
    return _run(() async {
      final args = SearchMatchesArgs.fromJson(_queryMap(request));
      final matches = await facade.searchMatches(
        query: args.query,
        limit: args.limit,
      );
      return {"matches": matches.map((m) => m.toJson()).toList()};
    });
  });

  router.get("$kResearchApiPathPrefix/matches/winners", (Request request) async {
    return _run(() async {
      final args = GetMatchWinnersArgs.fromJson(_queryMap(request));
      final result = await facade.getMatchWinners(
        matchId: args.matchId,
        matchQuery: args.matchQuery,
        projectName: args.project,
        byRatingGroup: args.byRatingGroup,
        topN: args.topN,
      );
      return result.toJson();
    });
  });

  router.get("$kResearchApiPathPrefix/matches/results", (Request request) async {
    return _run(() async {
      final args = GetMatchResultsArgs.fromJson(_queryMap(request));
      final result = await facade.getMatchResults(
        matchId: args.matchId,
        matchQuery: args.matchQuery,
        projectName: args.project,
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
  });

  router.get("$kResearchApiPathPrefix/matches/scores", (Request request) async {
    return _run(() async {
      final args = GetMatchScoresArgs.fromJson(_queryMap(request));
      final result = await facade.getMatchScores(
        matchId: args.matchId,
        matchQuery: args.matchQuery,
        projectName: args.project,
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
  });

  router.get("$kResearchApiPathPrefix/matches/competitor-stages", (Request request) async {
    return _run(() async {
      final args = GetCompetitorStageScoresArgs.fromJson(_queryMap(request));
      final result = await facade.getCompetitorStageScores(
        matchId: args.matchId,
        matchQuery: args.matchQuery,
        projectName: args.project,
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
  });

  router.get("$kResearchApiPathPrefix/shooters", (Request request) async {
    return _run(() async {
      final args = SearchShootersArgs.fromJson(_queryMap(request));
      final hits = await facade.searchShooters(
        query: args.query,
        projectName: args.project,
        groupName: args.group,
        groupUuid: args.groupUuid,
        memberNumber: args.memberNumber,
        limit: args.limit,
        includeInternal: args.includeInternal,
      );
      return {"shooters": hits.map((h) => h.toJson()).toList()};
    });
  });

  router.get("$kResearchApiPathPrefix/shooters/summary", (Request request) async {
    return _run(() async {
      final args = ShooterLookupArgs.fromJson(_queryMap(request));
      final summary = await facade.getShooterSummary(
        projectName: args.project,
        groupName: args.group,
        groupUuid: args.groupUuid,
        memberNumber: args.memberNumber,
        ratingId: args.ratingId,
        includeInternal: args.includeInternal,
      );
      return summary.toJson();
    });
  });

  router.get("$kResearchApiPathPrefix/shooters/history", (Request request) async {
    return _run(() async {
      final args = ShooterLookupArgs.fromJson(_queryMap(request));
      final events = await facade.getRatingHistory(
        projectName: args.project,
        groupName: args.group,
        groupUuid: args.groupUuid,
        memberNumber: args.memberNumber,
        ratingId: args.ratingId,
        limit: args.limit ?? 50,
        includeInternal: args.includeInternal,
      );
      return {"events": events.map((e) => e.toJson()).toList()};
    });
  });

  router.get("$kResearchApiPathPrefix/shooters/match-results", (Request request) async {
    return _run(() async {
      final args = ShooterLookupArgs.fromJson(_queryMap(request));
      final results = await facade.getShooterMatchResults(
        projectName: args.project,
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
  });

  router.get("$kResearchApiPathPrefix/leaderboard", (Request request) async {
    return _run(() async {
      final args = GetLeaderboardArgs.fromJson(_queryMap(request));
      final result = await facade.getLeaderboard(
        projectName: args.project,
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
  });

  return router;
}

Map<String, dynamic> _queryMap(Request request) {
  final out = <String, dynamic>{};
  request.url.queryParameters.forEach((key, value) {
    out[key] = _coerceQueryValue(value);
  });
  return out;
}

/// Coerce common query-string forms into JSON-friendly values for request DTOs.
dynamic _coerceQueryValue(String value) {
  final lower = value.toLowerCase();
  if(lower == "true") {
    return true;
  }
  if(lower == "false") {
    return false;
  }
  final asInt = int.tryParse(value);
  if(asInt != null) {
    return asInt;
  }
  final asDouble = double.tryParse(value);
  if(asDouble != null && value.contains(".")) {
    return asDouble;
  }
  return value;
}

Future<Response> _run(Future<Map<String, dynamic>> Function() body) async {
  try {
    return _jsonOk(await body());
  }
  catch(e, st) {
    _log.w("Research API error", error: e, stackTrace: st);
    final err = researchErrorJson(e);
    final status = err["statusCode"] as int? ?? 500;
    return Response(
      status,
      body: jsonEncode(err),
      headers: {"Content-Type": "application/json"},
    );
  }
}

Response _jsonOk(Map<String, dynamic> body) {
  return Response.ok(
    jsonEncode(body),
    headers: {"Content-Type": "application/json"},
  );
}
