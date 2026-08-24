/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:async";
import "dart:io";

import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/dtos.dart";
import "package:shooting_sports_analyst/research/http/http_research_facade.dart";
import "package:shooting_sports_analyst/research/research_facade.dart";
import "package:shooting_sports_analyst/research/research_queries.dart";

final _log = SSALogger("SwitchingResearchFacade");

/// Prefers the desktop app's local research REST API; falls back to opening
/// Isar in-process when the app is unavailable.
///
/// Intended for the standalone stdio MCP process only. Do not use from the
/// in-app MCP host (that already owns [AnalystDatabase]).
class SwitchingResearchFacade implements ResearchQueries {
  SwitchingResearchFacade({
    HttpResearchFacade? httpFacade,
    this.dbPath,
    this.healthCacheTtl = const Duration(seconds: 2),
  }) : _http = httpFacade ?? HttpResearchFacade();

  final HttpResearchFacade _http;
  final String? dbPath;
  final Duration healthCacheTtl;

  ResearchFacade? _local;
  bool? _cachedHealthy;
  DateTime? _healthCheckedAt;
  Future<void>? _localOpenFuture;

  @override
  Future<List<RatingProjectDto>> listRatingProjects({String? name, int limit = 50}) {
    return _delegate((f) => f.listRatingProjects(name: name, limit: limit));
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
  }) {
    return _delegate((f) => f.getLeaderboard(
          projectName: projectName,
          groupUuid: groupUuid,
          groupName: groupName,
          sort: sort,
          limit: limit,
          minMatches: minMatches,
          seenSince: seenSince,
          changeSince: changeSince,
        ));
  }

  @override
  Future<List<MatchSummaryDto>> searchMatches({
    required String query,
    int limit = 10,
    DateTime? after,
    DateTime? before,
  }) {
    return _delegate((f) => f.searchMatches(
          query: query,
          limit: limit,
          after: after,
          before: before,
        ));
  }

  @override
  Future<MatchWinnersResponse> getMatchWinners({
    int? matchId,
    String? matchQuery,
    String? projectName,
    bool byRatingGroup = false,
    int topN = 1,
  }) {
    return _delegate((f) => f.getMatchWinners(
          matchId: matchId,
          matchQuery: matchQuery,
          projectName: projectName,
          byRatingGroup: byRatingGroup,
          topN: topN,
        ));
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
  }) {
    return _delegate((f) => f.getMatchResults(
          matchId: matchId,
          matchQuery: matchQuery,
          projectName: projectName,
          division: division,
          groupUuid: groupUuid,
          groupName: groupName,
          femaleOnly: femaleOnly,
          ageCategory: ageCategory,
          category: category,
          topN: topN,
          overall: overall,
        ));
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
  }) {
    return _delegate((f) => f.getMatchScores(
          matchId: matchId,
          matchQuery: matchQuery,
          projectName: projectName,
          division: division,
          groupUuid: groupUuid,
          groupName: groupName,
          femaleOnly: femaleOnly,
          ageCategory: ageCategory,
          category: category,
          topN: topN,
          overall: overall,
          includeStages: includeStages,
          includeScoringEventCounts: includeScoringEventCounts,
        ));
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
  }) {
    return _delegate((f) => f.getCompetitorStageScores(
          matchId: matchId,
          matchQuery: matchQuery,
          projectName: projectName,
          memberNumber: memberNumber,
          ratingId: ratingId,
          division: division,
          groupUuid: groupUuid,
          groupName: groupName,
          overall: overall,
          includeScoringEventCounts: includeScoringEventCounts,
        ));
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
  }) {
    return _delegate((f) => f.searchShooters(
          query: query,
          projectName: projectName,
          groupUuid: groupUuid,
          groupName: groupName,
          memberNumber: memberNumber,
          limit: limit,
          includeInternal: includeInternal,
        ));
  }

  @override
  Future<ShooterSummaryDto> getShooterSummary({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    bool includeInternal = false,
  }) {
    return _delegate((f) => f.getShooterSummary(
          projectName: projectName,
          groupUuid: groupUuid,
          groupName: groupName,
          memberNumber: memberNumber,
          ratingId: ratingId,
          includeInternal: includeInternal,
        ));
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
  }) {
    return _delegate((f) => f.getRatingHistory(
          projectName: projectName,
          groupUuid: groupUuid,
          groupName: groupName,
          memberNumber: memberNumber,
          ratingId: ratingId,
          limit: limit,
          matchLevelOnly: matchLevelOnly,
          includeInternal: includeInternal,
        ));
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
  }) {
    return _delegate((f) => f.getShooterMatchResults(
          projectName: projectName,
          groupUuid: groupUuid,
          groupName: groupName,
          memberNumber: memberNumber,
          ratingId: ratingId,
          limit: limit,
          includeInternal: includeInternal,
          bestFirst: bestFirst,
        ));
  }

  Future<T> _delegate<T>(Future<T> Function(ResearchQueries facade) body) async {
    final healthy = await _checkHealthy();
    if(healthy) {
      await _closeLocalIfOpen();
      return body(_http);
    }
    final local = await _ensureLocal();
    return body(local);
  }

  Future<bool> _checkHealthy() async {
    final now = DateTime.now();
    final checkedAt = _healthCheckedAt;
    final cached = _cachedHealthy;
    if(checkedAt != null &&
        cached != null &&
        now.difference(checkedAt) < healthCacheTtl) {
      return cached;
    }
    final healthy = await _http.isHealthy();
    _cachedHealthy = healthy;
    _healthCheckedAt = now;
    if(healthy) {
      _log.v("Local research API healthy; using HTTP");
    }
    else {
      _log.v("Local research API unavailable; using local Isar");
    }
    return healthy;
  }

  Future<void> _closeLocalIfOpen() async {
    if(!AnalystDatabase.isOpen && _local == null) {
      return;
    }
    _local = null;
    _localOpenFuture = null;
    if(AnalystDatabase.isOpen) {
      _log.i("Closing local Isar; desktop research API is available");
      await AnalystDatabase.close();
    }
  }

  Future<ResearchFacade> _ensureLocal() async {
    final existing = _local;
    if(existing != null && AnalystDatabase.isOpen) {
      return existing;
    }

    final inFlight = _localOpenFuture;
    if(inFlight != null) {
      await inFlight;
      return _local!;
    }

    final completer = Completer<void>();
    _localOpenFuture = completer.future;
    try {
      _log.i("Opening AnalystDatabase for stdio MCP fallback");
      final path = dbPath ?? Platform.environment["SSA_DB_PATH"];
      if(path != null && path.isNotEmpty) {
        // Named constructor sets the singleton; factory returns it.
        AnalystDatabase.path(path);
      }
      final db = AnalystDatabase();
      await db.ready;
      _local = ResearchFacade(db);
      completer.complete();
      return _local!;
    }
    catch(e, st) {
      completer.completeError(e, st);
      _localOpenFuture = null;
      rethrow;
    }
  }
}
