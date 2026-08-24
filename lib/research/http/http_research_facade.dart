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
    try {
      final json = await _getJson(kResearchApiHealthPath, timeout: timeout);
      return json["ok"] == true && json["service"] == kResearchApiServiceName;
    }
    catch(_) {
      return false;
    }
  }

  void close() {
    _client.close(force: true);
  }

  @override
  Future<List<RatingProjectDto>> listRatingProjects({String? name, int limit = 50}) async {
    final json = await _getJson(
      "$kResearchApiPathPrefix/projects",
      query: {
        if(name != null) "name": name,
        "limit": limit,
      },
    );
    final list = json["projects"] as List<dynamic>? ?? [];
    return list
        .map((e) => RatingProjectDto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<LeaderboardResponse> getLeaderboard({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? sort,
    int limit = 25,
    int minMatches = 0,
    DateTime? seenSince,
    DateTime? changeSince,
  }) async {
    final json = await _getJson(
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
    );
    return LeaderboardResponse.fromJson(json);
  }

  @override
  Future<List<MatchSummaryDto>> searchMatches({
    required String query,
    int limit = 10,
    DateTime? after,
    DateTime? before,
  }) async {
    final json = await _getJson(
      "$kResearchApiPathPrefix/matches",
      query: {
        "query": query,
        "limit": limit,
        if(after != null) "after": researchDateOnlyToJson(after),
        if(before != null) "before": researchDateOnlyToJson(before),
      },
    );
    final list = json["matches"] as List<dynamic>? ?? [];
    return list
        .map((e) => MatchSummaryDto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<MatchWinnersResponse> getMatchWinners({
    int? matchId,
    String? matchQuery,
    String? projectName,
    bool byRatingGroup = false,
    int topN = 1,
  }) async {
    final json = await _getJson(
      "$kResearchApiPathPrefix/matches/winners",
      query: {
        if(matchId != null) "matchId": matchId,
        if(matchQuery != null) "matchQuery": matchQuery,
        if(projectName != null) "project": projectName,
        "byRatingGroup": byRatingGroup,
        "topN": topN,
      },
    );
    return MatchWinnersResponse.fromJson(json);
  }

  @override
  Future<MatchResultsResponse> getMatchResults({
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
  }) async {
    final json = await _getJson(
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
    );
    return MatchResultsResponse.fromJson(json);
  }

  @override
  Future<MatchScoresResponse> getMatchScores({
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
  }) async {
    final json = await _getJson(
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
    );
    return MatchScoresResponse.fromJson(json);
  }

  @override
  Future<CompetitorStageScoresResponse> getCompetitorStageScores({
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
  }) async {
    final json = await _getJson(
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
    );
    return CompetitorStageScoresResponse.fromJson(json);
  }

  @override
  Future<List<ShooterHitDto>> searchShooters({
    required String query,
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int limit = 20,
    bool includeInternal = false,
  }) async {
    final json = await _getJson(
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
    );
    final list = json["shooters"] as List<dynamic>? ?? [];
    return list
        .map((e) => ShooterHitDto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<ShooterSummaryDto> getShooterSummary({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    bool includeInternal = false,
  }) async {
    final json = await _getJson(
      "$kResearchApiPathPrefix/shooters/summary",
      query: {
        if(projectName != null) "project": projectName,
        if(groupUuid != null) "groupUuid": groupUuid,
        if(groupName != null) "group": groupName,
        if(memberNumber != null) "memberNumber": memberNumber,
        if(ratingId != null) "ratingId": ratingId,
        "includeInternal": includeInternal,
      },
    );
    return ShooterSummaryDto.fromJson(json);
  }

  @override
  Future<List<RatingEventDto>> getRatingHistory({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool matchLevelOnly = true,
    bool includeInternal = false,
  }) async {
    final json = await _getJson(
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
    );
    final list = json["events"] as List<dynamic>? ?? [];
    return list
        .map((e) => RatingEventDto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<ShooterMatchResultDto>> getShooterMatchResults({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool includeInternal = false,
    bool bestFirst = false,
  }) async {
    final json = await _getJson(
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
    );
    final list = json["results"] as List<dynamic>? ?? [];
    return list
        .map((e) => ShooterMatchResultDto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> _getJson(
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
        throw ResearchException(message, statusCode: status);
      }
      final decoded = jsonDecode(body);
      if(decoded is! Map) {
        throw ResearchException("Unexpected response from $uri", statusCode: 500);
      }
      return Map<String, dynamic>.from(decoded);
    }
    on ResearchException {
      rethrow;
    }
    on TimeoutException {
      throw ResearchException("Timed out calling $uri", statusCode: 504);
    }
    on SocketException catch(e) {
      throw ResearchException("Local research API unreachable: $e", statusCode: 503);
    }
    catch(e, st) {
      _log.w("HTTP research request failed: $uri", error: e, stackTrace: st);
      throw ResearchException("Local research API request failed: $e", statusCode: 502);
    }
  }
}
