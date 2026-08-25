/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/research/dtos.dart";

/// Read-only research query surface shared by the local DB facade, HTTP
/// client facade, and MCP tool handlers.
abstract class ResearchQueries {
  Future<ResearchResult<List<RatingProjectDto>>> listRatingProjects({String? name, int limit = 50});

  Future<ResearchResult<LeaderboardResponse>> getLeaderboard({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? sort,
    int limit = 25,
    int minMatches = 0,
    DateTime? seenSince,
    DateTime? changeSince,
  });

  Future<ResearchResult<List<MatchSummaryDto>>> searchMatches({
    required String query,
    int limit = 10,
    DateTime? after,
    DateTime? before,
  });

  Future<ResearchResult<MatchWinnersResponse>> getMatchWinners({
    int? matchId,
    String? matchQuery,
    String? projectName,
    bool byRatingGroup = false,
    int topN = 1,
  });

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
  });

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
  });

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
  });

  Future<ResearchResult<List<ShooterHitDto>>> searchShooters({
    required String query,
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int limit = 20,
    bool includeInternal = false,
  });

  Future<ResearchResult<ShooterSummaryDto>> getShooterSummary({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    bool includeInternal = false,
  });

  Future<ResearchResult<List<RatingEventDto>>> getRatingHistory({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool matchLevelOnly = true,
    bool includeInternal = false,
  });

  Future<ResearchResult<List<ShooterMatchResultDto>>> getShooterMatchResults({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool includeInternal = false,
    bool bestFirst = false,
  });

  Future<ResearchResult<List<MatchPrepHitDto>>> searchMatchPreps({
    String? projectName,
    String? query,
    DateTime? after,
    DateTime? before,
    int limit = 10,
    bool hasPredictionsOnly = true,
  });

  Future<ResearchResult<List<PredictionSetDto>>> listPredictionSets({
    required String prepId,
  });

  Future<ResearchResult<PredictionsResponse>> getPredictions({
    String? predictionSetId,
    String? prepId,
    String? groupUuid,
    String? groupName,
    int topN = kDefaultPredictionTopN,
  });

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
  });
}
