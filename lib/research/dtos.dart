/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:json_annotation/json_annotation.dart";

part "dtos.g.dart";

/// Compact JSON DTOs for research MCP responses.

const String kDefaultResearchProjectName = "L2s Main LLR";
const int kDefaultResearchMcpPort = 8090;
/// Default [getMatchResults] / [getMatchScores] row cap. Pass topN 0 for the full pool.
const int kDefaultMatchPoolTopN = 10;

String? researchDateOnlyToJson(DateTime? d) =>
    d?.toIso8601String().split("T").first;

DateTime researchDateOnlyFromJson(Object? value) {
  if (value is DateTime) return value;
  final parsed = DateTime.tryParse(value?.toString() ?? "");
  if (parsed == null) {
    throw FormatException("Invalid research date: $value");
  }
  return parsed;
}

DateTime? researchDateOnlyFromJsonNullable(Object? value) {
  if (value == null) return null;
  return researchDateOnlyFromJson(value);
}

class ResearchException implements Exception {
  ResearchException(this.message, {this.statusCode = 400});
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

Map<String, dynamic> researchErrorJson(Object error) {
  if (error is ResearchException) {
    return {
      "error": error.message,
      "statusCode": error.statusCode,
    };
  }
  return {
    "error": error.toString(),
    "statusCode": 500,
  };
}

@JsonSerializable(explicitToJson: true)
class RatingProjectDto {
  RatingProjectDto({
    required this.id,
    required this.name,
    required this.sportName,
    required this.matchCount,
    required this.groups,
    required this.algorithm,
    required this.algorithmLabel,
    required this.supportedSorts,
    this.latestMatchDate,
    this.byStage = false,
  });

  final int id;
  final String name;
  final String sportName;
  final int matchCount;
  final List<RatingGroupDto> groups;
  /// Stable algorithm id from project settings (e.g. latentLog, multiElo).
  final String algorithm;
  /// Human-readable algorithm name.
  final String algorithmLabel;
  final List<RatingSortModeDto> supportedSorts;
  /// Most recent match date in the project (anchor for seenSince defaults).
  @JsonKey(
    toJson: researchDateOnlyToJson,
    fromJson: researchDateOnlyFromJsonNullable,
    includeIfNull: false,
  )
  final DateTime? latestMatchDate;
  final bool byStage;

  factory RatingProjectDto.fromJson(Map<String, dynamic> json) =>
      _$RatingProjectDtoFromJson(json);
  Map<String, dynamic> toJson() => _$RatingProjectDtoToJson(this);
}

@JsonSerializable()
class RatingSortModeDto {
  RatingSortModeDto({
    required this.id,
    required this.label,
  });

  /// [RatingSortMode] enum name (e.g. lastChange, agedRating).
  final String id;
  final String label;

  factory RatingSortModeDto.fromJson(Map<String, dynamic> json) =>
      _$RatingSortModeDtoFromJson(json);
  Map<String, dynamic> toJson() => _$RatingSortModeDtoToJson(this);
}

@JsonSerializable()
class RatingGroupDto {
  RatingGroupDto({
    required this.uuid,
    required this.name,
  });

  final String uuid;
  final String name;

  factory RatingGroupDto.fromJson(Map<String, dynamic> json) =>
      _$RatingGroupDtoFromJson(json);
  Map<String, dynamic> toJson() => _$RatingGroupDtoToJson(this);
}

@JsonSerializable()
class MatchSummaryDto {
  MatchSummaryDto({
    required this.id,
    required this.name,
    required this.date,
    required this.sportName,
    required this.sourceIds,
  });

  final int id;
  final String name;
  @JsonKey(toJson: researchDateOnlyToJson, fromJson: researchDateOnlyFromJson)
  final DateTime date;
  final String sportName;
  final List<String> sourceIds;

  factory MatchSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$MatchSummaryDtoFromJson(json);
  Map<String, dynamic> toJson() => _$MatchSummaryDtoToJson(this);
}

@JsonSerializable(explicitToJson: true)
class MatchWinnerDto {
  MatchWinnerDto({
    required this.divisionOrGroup,
    required this.kind,
    required this.place,
    required this.name,
    required this.memberNumber,
    required this.ratio,
    required this.percentage,
    this.classification,
    this.division,
    this.female = false,
    this.ageCategory,
    this.categories = const [],
    this.points,
    this.competitorCount,
    this.dq = false,
  });

  final String divisionOrGroup;
  /// "division" | "ratingGroup"
  final String kind;
  final int place;
  final String name;
  final String memberNumber;
  final String? classification;
  final String? division;
  final bool female;
  final String? ageCategory;
  final List<String> categories;
  final double ratio;
  final double percentage;
  @JsonKey(includeIfNull: false)
  final double? points;
  @JsonKey(includeIfNull: false)
  final int? competitorCount;
  final bool dq;

  factory MatchWinnerDto.fromJson(Map<String, dynamic> json) =>
      _$MatchWinnerDtoFromJson(json);
  Map<String, dynamic> toJson() => _$MatchWinnerDtoToJson(this);
}

@JsonSerializable(explicitToJson: true)
class MatchWinnersResponse {
  MatchWinnersResponse({
    required this.match,
    required this.winners,
  });

  final MatchSummaryDto match;
  final List<MatchWinnerDto> winners;

  factory MatchWinnersResponse.fromJson(Map<String, dynamic> json) =>
      _$MatchWinnersResponseFromJson(json);
  Map<String, dynamic> toJson() => _$MatchWinnersResponseToJson(this);
}

@JsonSerializable(explicitToJson: true)
class MatchCompetitorResultDto {
  MatchCompetitorResultDto({
    required this.place,
    required this.name,
    required this.firstName,
    required this.lastName,
    required this.memberNumber,
    required this.ratio,
    required this.percentage,
    this.classification,
    this.division,
    this.powerFactor,
    this.female = false,
    this.ageCategory,
    this.categories = const [],
    this.points,
    this.dq = false,
    this.reentry = false,
    this.squad,
  });

  final int place;
  final String name;
  final String firstName;
  final String lastName;
  final String memberNumber;
  final String? classification;
  final String? division;
  final String? powerFactor;
  final bool female;
  final String? ageCategory;
  final List<String> categories;
  final double ratio;
  final double percentage;
  @JsonKey(includeIfNull: false)
  final double? points;
  final bool dq;
  final bool reentry;
  @JsonKey(includeIfNull: false)
  final int? squad;

  factory MatchCompetitorResultDto.fromJson(Map<String, dynamic> json) =>
      _$MatchCompetitorResultDtoFromJson(json);
  Map<String, dynamic> toJson() => _$MatchCompetitorResultDtoToJson(this);
}

@JsonSerializable(explicitToJson: true)
class MatchResultsResponse {
  MatchResultsResponse({
    required this.match,
    required this.pool,
    required this.kind,
    required this.competitorCount,
    required this.results,
    this.femaleOnly = false,
    this.ageCategory,
    this.category,
  });

  final MatchSummaryDto match;
  /// Division name, rating-group name, or "overall".
  final String pool;
  /// "division" | "ratingGroup" | "overall"
  final String kind;
  final bool femaleOnly;
  @JsonKey(includeIfNull: false)
  final String? ageCategory;
  @JsonKey(includeIfNull: false)
  final String? category;
  final int competitorCount;
  final List<MatchCompetitorResultDto> results;

  factory MatchResultsResponse.fromJson(Map<String, dynamic> json) =>
      _$MatchResultsResponseFromJson(json);
  Map<String, dynamic> toJson() => _$MatchResultsResponseToJson(this);
}

@JsonSerializable()
class ScoringEventCountsDto {
  ScoringEventCountsDto({
    required this.targetEvents,
    required this.penaltyEvents,
    required this.penaltyCount,
    required this.hasPenalties,
  });

  final Map<String, int> targetEvents;
  final Map<String, int> penaltyEvents;
  final int penaltyCount;
  final bool hasPenalties;

  factory ScoringEventCountsDto.fromJson(Map<String, dynamic> json) =>
      _$ScoringEventCountsDtoFromJson(json);
  Map<String, dynamic> toJson() => _$ScoringEventCountsDtoToJson(this);
}

@JsonSerializable(explicitToJson: true)
class StageScoreDto {
  StageScoreDto({
    required this.stageNumber,
    required this.stageName,
    required this.place,
    required this.ratio,
    required this.percentage,
    required this.points,
    this.finalTime,
    this.hitFactor,
    this.rawPoints,
    this.dnf = false,
    this.eventCounts,
  });

  final int stageNumber;
  final String stageName;
  final int place;
  final double ratio;
  final double percentage;
  /// Stage match points (HF sports) or cumulative stage value (time-plus).
  final double points;
  @JsonKey(includeIfNull: false)
  final double? finalTime;
  @JsonKey(includeIfNull: false)
  final double? hitFactor;
  @JsonKey(includeIfNull: false)
  final double? rawPoints;
  final bool dnf;
  @JsonKey(includeIfNull: false)
  final ScoringEventCountsDto? eventCounts;

  factory StageScoreDto.fromJson(Map<String, dynamic> json) =>
      _$StageScoreDtoFromJson(json);
  Map<String, dynamic> toJson() => _$StageScoreDtoToJson(this);
}

@JsonSerializable(explicitToJson: true)
class MatchScoreRowDto {
  MatchScoreRowDto({
    required this.place,
    required this.name,
    required this.firstName,
    required this.lastName,
    required this.memberNumber,
    required this.ratio,
    required this.percentage,
    required this.points,
    this.classification,
    this.division,
    this.powerFactor,
    this.female = false,
    this.ageCategory,
    this.categories = const [],
    this.finalTime,
    this.hitFactor,
    this.rawPoints,
    this.dq = false,
    this.reentry = false,
    this.squad,
    this.entryId,
    this.eventCounts,
    this.stages = const [],
  });

  final int place;
  final String name;
  final String firstName;
  final String lastName;
  final String memberNumber;
  final String? classification;
  final String? division;
  final String? powerFactor;
  final bool female;
  final String? ageCategory;
  final List<String> categories;
  final double ratio;
  final double percentage;
  /// Match points (HF) or cumulative match value (time-plus).
  final double points;
  @JsonKey(includeIfNull: false)
  final double? finalTime;
  @JsonKey(includeIfNull: false)
  final double? hitFactor;
  @JsonKey(includeIfNull: false)
  final double? rawPoints;
  final bool dq;
  final bool reentry;
  @JsonKey(includeIfNull: false)
  final int? squad;
  @JsonKey(includeIfNull: false)
  final int? entryId;
  @JsonKey(includeIfNull: false)
  final ScoringEventCountsDto? eventCounts;
  final List<StageScoreDto> stages;

  factory MatchScoreRowDto.fromJson(Map<String, dynamic> json) =>
      _$MatchScoreRowDtoFromJson(json);
  Map<String, dynamic> toJson() => _$MatchScoreRowDtoToJson(this);
}

@JsonSerializable(explicitToJson: true)
class MatchScoresResponse {
  MatchScoresResponse({
    required this.match,
    required this.pool,
    required this.kind,
    required this.scoringKind,
    required this.competitorCount,
    required this.scores,
    this.femaleOnly = false,
    this.ageCategory,
    this.category,
    this.includeStages = false,
    this.includeScoringEventCounts = false,
  });

  final MatchSummaryDto match;
  final String pool;
  /// "division" | "ratingGroup" | "overall"
  final String kind;
  /// "hitFactor" | "timePlus" | "points"
  final String scoringKind;
  final bool femaleOnly;
  @JsonKey(includeIfNull: false)
  final String? ageCategory;
  @JsonKey(includeIfNull: false)
  final String? category;
  final int competitorCount;
  final bool includeStages;
  final bool includeScoringEventCounts;
  final List<MatchScoreRowDto> scores;

  factory MatchScoresResponse.fromJson(Map<String, dynamic> json) =>
      _$MatchScoresResponseFromJson(json);
  Map<String, dynamic> toJson() => _$MatchScoresResponseToJson(this);
}

@JsonSerializable(explicitToJson: true)
class CompetitorStageScoresResponse {
  CompetitorStageScoresResponse({
    required this.match,
    required this.pool,
    required this.kind,
    required this.scoringKind,
    required this.competitor,
    required this.stages,
    this.includeScoringEventCounts = false,
  });

  final MatchSummaryDto match;
  final String pool;
  /// "division" | "ratingGroup" | "overall"
  final String kind;
  /// "hitFactor" | "timePlus" | "points"
  final String scoringKind;
  /// Competitor identity plus match-level score in the resolved pool.
  final MatchScoreRowDto competitor;
  final List<StageScoreDto> stages;
  final bool includeScoringEventCounts;

  factory CompetitorStageScoresResponse.fromJson(Map<String, dynamic> json) =>
      _$CompetitorStageScoresResponseFromJson(json);
  Map<String, dynamic> toJson() => _$CompetitorStageScoresResponseToJson(this);
}

@JsonSerializable()
class ShooterHitDto {
  ShooterHitDto({
    required this.ratingId,
    required this.firstName,
    required this.lastName,
    required this.name,
    required this.memberNumber,
    required this.deduplicatorName,
    required this.groupUuid,
    required this.groupName,
    required this.rating,
    required this.agedRating,
    this.classification,
    this.division,
    this.female = false,
    this.ageCategory,
    this.categories = const [],
    this.region,
    this.regionSubdivision,
    this.rawLocation,
    this.internalRating,
    this.internalAgedRating,
  });

  final int ratingId;
  final String firstName;
  final String lastName;
  final String name;
  final String memberNumber;
  final String deduplicatorName;
  final String groupUuid;
  final String groupName;
  /// Display/scaled rating.
  final double rating;
  /// Display/scaled aged rating.
  final double agedRating;
  final String? classification;
  final String? division;
  final bool female;
  final String? ageCategory;
  final List<String> categories;
  /// Typically an ISO-3166 country code (e.g. USA).
  @JsonKey(includeIfNull: false)
  final String? region;
  /// Typically an ISO-3166 state/province code (e.g. TX).
  @JsonKey(includeIfNull: false)
  final String? regionSubdivision;
  /// Unparsed source location when region/subdivision are unavailable.
  @JsonKey(includeIfNull: false)
  final String? rawLocation;
  @JsonKey(includeIfNull: false)
  final double? internalRating;
  @JsonKey(includeIfNull: false)
  final double? internalAgedRating;

  factory ShooterHitDto.fromJson(Map<String, dynamic> json) =>
      _$ShooterHitDtoFromJson(json);
  Map<String, dynamic> toJson() => _$ShooterHitDtoToJson(this);
}

@JsonSerializable()
class ShooterSummaryDto {
  ShooterSummaryDto({
    required this.ratingId,
    required this.firstName,
    required this.lastName,
    required this.name,
    required this.memberNumber,
    required this.knownMemberNumbers,
    required this.deduplicatorName,
    required this.projectName,
    required this.groupUuid,
    required this.groupName,
    required this.rating,
    required this.agedRating,
    required this.careerMinimumRating,
    required this.careerMaximumRating,
    required this.eventCount,
    required this.firstSeen,
    required this.lastSeen,
    this.classification,
    this.division,
    this.female = false,
    this.ageCategory,
    this.categories = const [],
    this.region,
    this.regionSubdivision,
    this.rawLocation,
    this.connectivity,
    this.internalRating,
    this.internalAgedRating,
    this.internalCareerMinimumRating,
    this.internalCareerMaximumRating,
  });

  final int ratingId;
  final String firstName;
  final String lastName;
  final String name;
  final String memberNumber;
  final List<String> knownMemberNumbers;
  final String deduplicatorName;
  final String projectName;
  final String groupUuid;
  final String groupName;
  /// Display/scaled rating.
  final double rating;
  /// Display/scaled aged rating.
  final double agedRating;
  final double careerMinimumRating;
  final double careerMaximumRating;
  final int eventCount;
  @JsonKey(toJson: researchDateOnlyToJson, fromJson: researchDateOnlyFromJson)
  final DateTime firstSeen;
  @JsonKey(toJson: researchDateOnlyToJson, fromJson: researchDateOnlyFromJson)
  final DateTime lastSeen;
  final String? classification;
  final String? division;
  final bool female;
  final String? ageCategory;
  final List<String> categories;
  /// Typically an ISO-3166 country code (e.g. USA).
  @JsonKey(includeIfNull: false)
  final String? region;
  /// Typically an ISO-3166 state/province code (e.g. TX).
  @JsonKey(includeIfNull: false)
  final String? regionSubdivision;
  /// Unparsed source location when region/subdivision are unavailable.
  @JsonKey(includeIfNull: false)
  final String? rawLocation;
  @JsonKey(includeIfNull: false)
  final double? connectivity;
  @JsonKey(includeIfNull: false)
  final double? internalRating;
  @JsonKey(includeIfNull: false)
  final double? internalAgedRating;
  @JsonKey(includeIfNull: false)
  final double? internalCareerMinimumRating;
  @JsonKey(includeIfNull: false)
  final double? internalCareerMaximumRating;

  factory ShooterSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$ShooterSummaryDtoFromJson(json);
  Map<String, dynamic> toJson() => _$ShooterSummaryDtoToJson(this);
}

@JsonSerializable()
class RatingEventDto {
  RatingEventDto({
    required this.date,
    required this.matchId,
    required this.matchName,
    required this.stageNumber,
    required this.oldRating,
    required this.newRating,
    required this.ratingChange,
    required this.matchPlace,
    required this.matchRatio,
    required this.matchPercentage,
    this.division,
    this.classification,
    this.internalOldRating,
    this.internalNewRating,
    this.internalRatingChange,
  });

  @JsonKey(toJson: researchDateOnlyToJson, fromJson: researchDateOnlyFromJson)
  final DateTime date;
  final String matchId;
  final String matchName;
  final int stageNumber;
  /// Display/scaled old rating.
  final double oldRating;
  /// Display/scaled new rating.
  final double newRating;
  /// Display/scaled rating change.
  final double ratingChange;
  final int matchPlace;
  final double matchRatio;
  final double matchPercentage;
  /// Division entered at this match, when available.
  @JsonKey(includeIfNull: false)
  final String? division;
  /// Classification at this match, when available.
  @JsonKey(includeIfNull: false)
  final String? classification;
  @JsonKey(includeIfNull: false)
  final double? internalOldRating;
  @JsonKey(includeIfNull: false)
  final double? internalNewRating;
  @JsonKey(includeIfNull: false)
  final double? internalRatingChange;

  factory RatingEventDto.fromJson(Map<String, dynamic> json) =>
      _$RatingEventDtoFromJson(json);
  Map<String, dynamic> toJson() => _$RatingEventDtoToJson(this);
}

@JsonSerializable()
class ShooterMatchResultDto {
  ShooterMatchResultDto({
    required this.matchId,
    required this.matchName,
    required this.date,
    required this.place,
    required this.ratio,
    required this.percentage,
    this.division,
    this.classification,
    this.ratingChange,
    this.oldRating,
    this.newRating,
    this.internalRatingChange,
    this.internalOldRating,
    this.internalNewRating,
  });

  final String matchId;
  final String matchName;
  @JsonKey(toJson: researchDateOnlyToJson, fromJson: researchDateOnlyFromJson)
  final DateTime date;
  final int place;
  final double ratio;
  final double percentage;
  /// Division entered at this match, when available.
  @JsonKey(includeIfNull: false)
  final String? division;
  /// Classification at this match, when available.
  @JsonKey(includeIfNull: false)
  final String? classification;
  @JsonKey(includeIfNull: false)
  final double? ratingChange;
  @JsonKey(includeIfNull: false)
  final double? oldRating;
  @JsonKey(includeIfNull: false)
  final double? newRating;
  @JsonKey(includeIfNull: false)
  final double? internalRatingChange;
  @JsonKey(includeIfNull: false)
  final double? internalOldRating;
  @JsonKey(includeIfNull: false)
  final double? internalNewRating;

  factory ShooterMatchResultDto.fromJson(Map<String, dynamic> json) =>
      _$ShooterMatchResultDtoFromJson(json);
  Map<String, dynamic> toJson() => _$ShooterMatchResultDtoToJson(this);
}

@JsonSerializable(explicitToJson: true)
class LeaderboardResponse {
  LeaderboardResponse({
    required this.projectName,
    required this.groupUuid,
    required this.groupName,
    required this.sort,
    required this.sortLabel,
    required this.minMatches,
    required this.seenSince,
    required this.latestMatchDate,
    required this.totalAfterFilters,
    required this.entries,
  });

  final String projectName;
  final String groupUuid;
  final String groupName;
  /// [RatingSortMode] enum name.
  final String sort;
  final String sortLabel;
  final int minMatches;
  /// Inclusive lower bound on competitor lastSeen.
  ///
  /// Relative to [latestMatchDate], not wall-clock today, when defaulted.
  @JsonKey(toJson: researchDateOnlyToJson, fromJson: researchDateOnlyFromJson)
  final DateTime seenSince;
  @JsonKey(toJson: researchDateOnlyToJson, fromJson: researchDateOnlyFromJson)
  final DateTime latestMatchDate;
  final int totalAfterFilters;
  final List<LeaderboardEntryDto> entries;

  factory LeaderboardResponse.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardResponseFromJson(json);
  Map<String, dynamic> toJson() => _$LeaderboardResponseToJson(this);
}

@JsonSerializable()
class LeaderboardEntryDto {
  LeaderboardEntryDto({
    required this.place,
    required this.ratingId,
    required this.firstName,
    required this.lastName,
    required this.name,
    required this.memberNumber,
    required this.rating,
    required this.agedRating,
    required this.sortValue,
    required this.lastSeen,
    required this.historyLength,
    this.classification,
    this.division,
    this.female = false,
    this.ageCategory,
    this.categories = const [],
    this.region,
    this.regionSubdivision,
    this.rawLocation,
    this.matchCount,
    this.lastChange,
  });

  final int place;
  final int ratingId;
  final String firstName;
  final String lastName;
  final String name;
  final String memberNumber;
  /// Display/scaled rating.
  final double rating;
  /// Display/scaled aged rating.
  final double agedRating;
  /// Display value used for the requested sort (when numeric).
  final double sortValue;
  @JsonKey(toJson: researchDateOnlyToJson, fromJson: researchDateOnlyFromJson)
  final DateTime lastSeen;
  final String? classification;
  final String? division;
  final bool female;
  final String? ageCategory;
  final List<String> categories;
  @JsonKey(includeIfNull: false)
  final String? region;
  @JsonKey(includeIfNull: false)
  final String? regionSubdivision;
  @JsonKey(includeIfNull: false)
  final String? rawLocation;
  @JsonKey(includeIfNull: false)
  final int? matchCount;
  /// Rating-history length (stages when by-stage, else events/matches).
  final int historyLength;
  /// Display/scaled last match rating change, when available.
  @JsonKey(includeIfNull: false)
  final double? lastChange;

  factory LeaderboardEntryDto.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardEntryDtoFromJson(json);
  Map<String, dynamic> toJson() => _$LeaderboardEntryDtoToJson(this);
}
