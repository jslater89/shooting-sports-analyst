/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/dtos.dart";
import "package:shooting_sports_analyst/research/http/research_api_constants.dart";
import "package:shooting_sports_analyst/research/research_queries.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("HttpResearchFacade");

/// [ResearchQueries] implementation that calls the desktop app's local REST API.
class HttpResearchFacade implements ResearchQueries {
  HttpResearchFacade({
    String? baseUrl,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : baseUrl = (baseUrl ?? Platform.environment[kResearchApiBaseEnv] ?? kDefaultResearchApiBase)
            .replaceAll(RegExp(r"/+$"), ""),
        _client = httpClient ?? HttpClient();

  final String baseUrl;
  final Duration timeout;
  final HttpClient _client;

  /// Fast health check used by [SwitchingResearchFacade].
  Future<bool> isHealthy({Duration timeout = const Duration(milliseconds: 200)}) async {
    final json = await _getJson(kResearchApiHealthPath, timeout: timeout);
    if(json.isErr()) {
      return false;
    }
    final body = json.unwrap();
    return body["ok"] == true && body["service"] == kResearchApiServiceName;
  }

  void close() {
    _client.close(force: true);
  }

  @override
  Future<ResearchResult<List<RatingProjectDto>>> listRatingProjects({String? name, int limit = 50}) {
    return _mapJson(
      "$kResearchApiPathPrefix/projects",
      query: {
        if(name != null) "name": name,
        "limit": limit,
      },
      map: (json) {
        final list = json["projects"] as List<dynamic>? ?? [];
        return list
            .map((e) => RatingProjectDto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  @override
  Future<ResearchResult<LeaderboardResponse>> getLeaderboard({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? sort,
    int limit = 25,
    int minMatches = 0,
    DateTime? seenSince,
    DateTime? changeSince,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/leaderboard",
      query: {
        if(projectName != null) "project": projectName,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        if(sort != null) "sort": sort,
        "limit": limit,
        "minMatches": minMatches,
        if(seenSince != null) "seenSince": researchDateOnlyToJson(seenSince),
        if(changeSince != null) "changeSince": researchDateOnlyToJson(changeSince),
      },
      map: LeaderboardResponse.fromJson,
    );
  }

  @override
  Future<ResearchResult<List<MatchSummaryDto>>> searchMatches({
    required String query,
    int limit = 10,
    DateTime? after,
    DateTime? before,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/matches",
      query: {
        "query": query,
        "limit": limit,
        if(after != null) "after": researchDateOnlyToJson(after),
        if(before != null) "before": researchDateOnlyToJson(before),
      },
      map: (json) {
        final list = json["matches"] as List<dynamic>? ?? [];
        return list
            .map((e) => MatchSummaryDto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  @override
  Future<ResearchResult<MatchWinnersResponse>> getMatchWinners({
    int? matchId,
    String? matchQuery,
    String? projectName,
    bool byRatingGroup = false,
    int topN = 1,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/matches/winners",
      query: {
        if(matchId != null) "matchId": matchId,
        if(matchQuery != null) "matchQuery": matchQuery,
        if(projectName != null) "project": projectName,
        "byRatingGroup": byRatingGroup,
        "topN": topN,
      },
      map: MatchWinnersResponse.fromJson,
    );
  }

  @override
  Future<ResearchResult<MatchResultsResponse>> getMatchResults({
    int? matchId,
    String? matchQuery,
    String? projectName,
    String? division,
    String? groupUuid,
    String? groupName,
    bool femaleOnly = false,
    String? ageCategory,
    String? category,
    int topN = kDefaultMatchPoolTopN,
    bool overall = false,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/matches/results",
      query: {
        if(matchId != null) "matchId": matchId,
        if(matchQuery != null) "matchQuery": matchQuery,
        if(projectName != null) "project": projectName,
        if(division != null) "division": division,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        "femaleOnly": femaleOnly,
        if(ageCategory != null) "ageCategory": ageCategory,
        if(category != null) "category": category,
        "topN": topN,
        "overall": overall,
      },
      map: MatchResultsResponse.fromJson,
    );
  }

  @override
  Future<ResearchResult<MatchScoresResponse>> getMatchScores({
    int? matchId,
    String? matchQuery,
    String? projectName,
    String? division,
    String? groupUuid,
    String? groupName,
    bool femaleOnly = false,
    String? ageCategory,
    String? category,
    int topN = kDefaultMatchPoolTopN,
    bool overall = false,
    bool includeStages = false,
    bool includeScoringEventCounts = false,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/matches/scores",
      query: {
        if(matchId != null) "matchId": matchId,
        if(matchQuery != null) "matchQuery": matchQuery,
        if(projectName != null) "project": projectName,
        if(division != null) "division": division,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        "femaleOnly": femaleOnly,
        if(ageCategory != null) "ageCategory": ageCategory,
        if(category != null) "category": category,
        "topN": topN,
        "overall": overall,
        "includeStages": includeStages,
        "includeScoringEventCounts": includeScoringEventCounts,
      },
      map: MatchScoresResponse.fromJson,
    );
  }

  @override
  Future<ResearchResult<CompetitorStageScoresResponse>> getCompetitorStageScores({
    int? matchId,
    String? matchQuery,
    String? projectName,
    String? memberNumber,
    int? ratingId,
    String? division,
    String? groupUuid,
    String? groupName,
    bool overall = false,
    bool includeScoringEventCounts = false,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/matches/competitor-stages",
      query: {
        if(matchId != null) "matchId": matchId,
        if(matchQuery != null) "matchQuery": matchQuery,
        if(projectName != null) "project": projectName,
        if(memberNumber != null) "memberNumber": memberNumber,
        if(ratingId != null) "ratingId": ratingId,
        if(division != null) "division": division,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        "overall": overall,
        "includeScoringEventCounts": includeScoringEventCounts,
      },
      map: CompetitorStageScoresResponse.fromJson,
    );
  }

  @override
  Future<ResearchResult<List<ShooterHitDto>>> searchShooters({
    required String query,
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int limit = 20,
    bool includeInternal = false,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/shooters",
      query: {
        "query": query,
        if(projectName != null) "project": projectName,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        if(memberNumber != null) "memberNumber": memberNumber,
        "limit": limit,
        "includeInternal": includeInternal,
      },
      map: (json) {
        final list = json["shooters"] as List<dynamic>? ?? [];
        return list
            .map((e) => ShooterHitDto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  @override
  Future<ResearchResult<ShooterSummaryDto>> getShooterSummary({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    bool includeInternal = false,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/shooters/summary",
      query: {
        if(projectName != null) "project": projectName,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        if(memberNumber != null) "memberNumber": memberNumber,
        if(ratingId != null) "ratingId": ratingId,
        "includeInternal": includeInternal,
      },
      map: ShooterSummaryDto.fromJson,
    );
  }

  @override
  Future<ResearchResult<List<RatingEventDto>>> getRatingHistory({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool matchLevelOnly = true,
    bool includeInternal = false,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/shooters/history",
      query: {
        if(projectName != null) "project": projectName,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        if(memberNumber != null) "memberNumber": memberNumber,
        if(ratingId != null) "ratingId": ratingId,
        "limit": limit,
        "includeInternal": includeInternal,
      },
      map: (json) {
        final list = json["events"] as List<dynamic>? ?? [];
        return list
            .map((e) => RatingEventDto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  @override
  Future<ResearchResult<List<ShooterMatchResultDto>>> getShooterMatchResults({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool includeInternal = false,
    bool bestFirst = false,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/shooters/match-results",
      query: {
        if(projectName != null) "project": projectName,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        if(memberNumber != null) "memberNumber": memberNumber,
        if(ratingId != null) "ratingId": ratingId,
        "limit": limit,
        "includeInternal": includeInternal,
        "bestFirst": bestFirst,
      },
      map: (json) {
        final list = json["results"] as List<dynamic>? ?? [];
        return list
            .map((e) => ShooterMatchResultDto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  @override
  Future<ResearchResult<List<MatchPrepHitDto>>> searchMatchPreps({
    String? projectName,
    String? query,
    DateTime? after,
    DateTime? before,
    int limit = 10,
    bool hasPredictionsOnly = true,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/match-preps",
      query: {
        if(projectName != null) "project": projectName,
        if(query != null) "query": query,
        if(after != null) "after": researchDateOnlyToJson(after),
        if(before != null) "before": researchDateOnlyToJson(before),
        "limit": limit,
        "hasPredictionsOnly": hasPredictionsOnly,
      },
      map: (json) {
        final list = json["matchPreps"] as List<dynamic>? ?? [];
        return list
            .map((e) => MatchPrepHitDto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  @override
  Future<ResearchResult<List<PredictionSetDto>>> listPredictionSets({
    required String prepId,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/match-preps/prediction-sets",
      query: {"prepId": prepId},
      map: (json) {
        final list = json["predictionSets"] as List<dynamic>? ?? [];
        return list
            .map((e) => PredictionSetDto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  @override
  Future<ResearchResult<PredictionsResponse>> getPredictions({
    String? predictionSetId,
    String? prepId,
    String? groupUuid,
    String? groupName,
    int topN = kDefaultPredictionTopN,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/prediction-sets/predictions",
      query: {
        if(predictionSetId != null) "predictionSetId": predictionSetId,
        if(prepId != null) "prepId": prepId,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        "topN": topN,
      },
      map: PredictionsResponse.fromJson,
    );
  }

  @override
  Future<ResearchResult<List<PredictionRowDto>>> searchPredictions({
    String? predictionSetId,
    String? prepId,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    String? query,
    List<String>? memberNumbers,
    List<int>? ratingIds,
    int limit = kDefaultPredictionSearchLimit,
  }) {
    return _mapJson(
      "$kResearchApiPathPrefix/prediction-sets/search-predictions",
      query: {
        if(predictionSetId != null) "predictionSetId": predictionSetId,
        if(prepId != null) "prepId": prepId,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        if(memberNumber != null) "memberNumber": memberNumber,
        if(ratingId != null) "ratingId": ratingId,
        if(query != null) "query": query,
        if(memberNumbers != null && memberNumbers.isNotEmpty)
          "memberNumbers": memberNumbers.join(","),
        if(ratingIds != null && ratingIds.isNotEmpty)
          "ratingIds": ratingIds.join(","),
        "limit": limit,
      },
      map: (json) {
        final list = json["predictions"] as List<dynamic>? ?? [];
        return list
            .map((e) => PredictionRowDto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  Future<ResearchResult<T>> _mapJson<T>(
    String path, {
    Map<String, Object?> query = const {},
    required T Function(Map<String, dynamic> json) map,
  }) async {
    final json = await _getJson(path, query: query);
    if(json.isErr()) {
      return Result.errFrom(json);
    }
    return Result.ok(map(json.unwrap()));
  }

  Future<ResearchResult<Map<String, dynamic>>> _getJson(
    String path, {
    Map<String, Object?> query = const {},
    Duration? timeout,
  }) async {
    final uri = Uri.parse("$baseUrl$path").replace(
      queryParameters: {
        for(final e in query.entries)
          if(e.value != null) e.key: e.value.toString(),
      },
    );

    try {
      final request = await _client.getUrl(uri).timeout(timeout ?? this.timeout);
      final response = await request.close().timeout(timeout ?? this.timeout);
      final body = await response.transform(utf8.decoder).join();
      if(response.statusCode < 200 || response.statusCode >= 300) {
        Map<String, dynamic>? errJson;
        try {
          errJson = jsonDecode(body) as Map<String, dynamic>?;
        }
        catch(_) {}
        final message = errJson?["error"]?.toString() ?? body;
        final status = errJson?["statusCode"] as int? ?? response.statusCode;
        return Result.err(ResearchError(message, statusCode: status));
      }
      final decoded = jsonDecode(body);
      if(decoded is! Map) {
        return Result.err(ResearchError("Unexpected response from $uri", statusCode: 500));
      }
      return Result.ok(Map<String, dynamic>.from(decoded));
    }
    on TimeoutException {
      return Result.err(ResearchError("Timed out calling $uri", statusCode: 504));
    }
    on SocketException catch(e) {
      return Result.err(ResearchError("Local research API unreachable: $e", statusCode: 503));
    }
    catch(e, st) {
      _log.w("HTTP research request failed: $uri", error: e, stackTrace: st);
      return Result.err(ResearchError("Local research API request failed: $e", statusCode: 502));
    }
  }
}

