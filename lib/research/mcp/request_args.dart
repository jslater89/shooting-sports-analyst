/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:json_annotation/json_annotation.dart";
import "package:shooting_sports_analyst/research/dtos.dart"
    show
        kDefaultHeatMinCount,
        kDefaultHeatPercentile,
        kDefaultMatchPoolTopN,
        kDefaultPackageMoverLimit,
        kDefaultPredictionSearchLimit,
        kDefaultPredictionTopN,
        kDefaultRatingFieldMinMatches,
        researchArgsJson,
        researchBoolFromJson,
        researchDateOnlyFromJsonNullable,
        researchDateOnlyToJson,
        researchIdFromJson,
        researchIdFromJsonNullable,
        researchIntFromJsonNullable,
        researchIntListFromJson,
        researchStringListFromJson;

part "request_args.g.dart";

/// Convert MCP [CallToolRequest.arguments] into a JSON map for request DTOs.
Map<String, dynamic> mcpArgumentsToJsonMap(Map<String, Object?>? arguments) {
  if (arguments == null || arguments.isEmpty) {
    return <String, dynamic>{};
  }
  return Map<String, dynamic>.from(arguments);
}

T parseMcpArgs<T>(
  Map<String, Object?>? arguments,
  T Function(Map<String, dynamic> json) fromJson,
) {
  return fromJson(researchArgsJson(mcpArgumentsToJsonMap(arguments)));
}

@JsonSerializable()
class ListRatingProjectsArgs {
  ListRatingProjectsArgs({
    this.name,
    this.limit = 50,
  });

  final String? name;
  @JsonKey(defaultValue: 50)
  final int limit;

  factory ListRatingProjectsArgs.fromJson(Map<String, dynamic> json) =>
      _$ListRatingProjectsArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$ListRatingProjectsArgsToJson(this);
}

@JsonSerializable()
class SearchMatchesArgs {
  SearchMatchesArgs({
    this.query = "",
    this.limit = 10,
    this.after,
    this.before,
  });

  @JsonKey(defaultValue: "")
  final String query;
  @JsonKey(fromJson: _limit10FromJson)
  final int limit;
  /// Inclusive lower bound on match date.
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? after;
  /// Exclusive upper bound on match date.
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? before;

  factory SearchMatchesArgs.fromJson(Map<String, dynamic> json) =>
      _$SearchMatchesArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$SearchMatchesArgsToJson(this);
}

@JsonSerializable()
class GetMatchWinnersArgs {
  GetMatchWinnersArgs({
    this.matchId,
    this.matchQuery,
    this.project,
    this.byRatingGroup = false,
    this.topN = 1,
    this.includeRatings = false,
    this.heatPercentile = kDefaultHeatPercentile,
    this.heatMinCount = kDefaultHeatMinCount,
    this.ratingMinMatches = kDefaultRatingFieldMinMatches,
    this.seenSince,
  });

  final int? matchId;
  final String? matchQuery;
  final String? project;
  @JsonKey(defaultValue: false)
  final bool byRatingGroup;
  @JsonKey(defaultValue: 1)
  final int topN;
  /// Attach pre-match rating, rating percentile, and per-division heat.
  @JsonKey(defaultValue: false)
  final bool includeRatings;
  /// Percentile that counts toward [DivisionHeatSummaryDto.heat].
  @JsonKey(defaultValue: kDefaultHeatPercentile)
  final int heatPercentile;
  @JsonKey(defaultValue: kDefaultHeatMinCount)
  final int heatMinCount;
  /// Minimum matches for the active field the percentiles are taken from.
  @JsonKey(defaultValue: kDefaultRatingFieldMinMatches)
  final int ratingMinMatches;
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? seenSince;

  factory GetMatchWinnersArgs.fromJson(Map<String, dynamic> json) =>
      _$GetMatchWinnersArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$GetMatchWinnersArgsToJson(this);
}

@JsonSerializable()
class GetMatchResultsArgs {
  GetMatchResultsArgs({
    this.matchId,
    this.matchQuery,
    this.division,
    this.group,
    this.groupUuid,
    this.project,
    this.overall = false,
    this.femaleOnly = false,
    this.ageCategory,
    this.category,
    this.topN = kDefaultMatchPoolTopN,
    this.includeRatings = false,
    this.heatPercentile = kDefaultHeatPercentile,
    this.heatMinCount = kDefaultHeatMinCount,
    this.ratingMinMatches = kDefaultRatingFieldMinMatches,
    this.seenSince,
  });

  final int? matchId;
  final String? matchQuery;
  final String? division;
  final String? group;
  final String? groupUuid;
  final String? project;
  @JsonKey(defaultValue: false)
  final bool overall;
  @JsonKey(defaultValue: false)
  final bool femaleOnly;
  final String? ageCategory;
  final String? category;
  @JsonKey(defaultValue: kDefaultMatchPoolTopN)
  final int topN;
  @JsonKey(defaultValue: false)
  final bool includeRatings;
  @JsonKey(defaultValue: kDefaultHeatPercentile)
  final int heatPercentile;
  @JsonKey(defaultValue: kDefaultHeatMinCount)
  final int heatMinCount;
  @JsonKey(defaultValue: kDefaultRatingFieldMinMatches)
  final int ratingMinMatches;
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? seenSince;

  factory GetMatchResultsArgs.fromJson(Map<String, dynamic> json) =>
      _$GetMatchResultsArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$GetMatchResultsArgsToJson(this);
}

@JsonSerializable()
class SearchShootersArgs {
  SearchShootersArgs({
    this.query = "",
    this.memberNumber,
    this.project,
    this.group,
    this.groupUuid,
    this.limit = 20,
    this.includeInternal = false,
  });

  final String query;
  final String? memberNumber;
  final String? project;
  final String? group;
  final String? groupUuid;
  final int limit;
  final bool includeInternal;

  factory SearchShootersArgs.fromJson(Map<String, dynamic> json) =>
      _$SearchShootersArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$SearchShootersArgsToJson(this);
}

/// Shared shooter identity args for summary / history / career-result tools.
@JsonSerializable()
class ShooterLookupArgs {
  ShooterLookupArgs({
    this.memberNumber,
    this.ratingId,
    this.project,
    this.group,
    this.groupUuid,
    this.limit,
    this.includeInternal = false,
    this.bestFirst = false,
    this.name,
    this.maxPlace,
  });

  final String? memberNumber;
  final int? ratingId;
  final String? project;
  final String? group;
  final String? groupUuid;
  final int? limit;
  @JsonKey(defaultValue: false)
  final bool includeInternal;
  /// When true, [get_shooter_match_results] returns best finishes first (by
  /// percentage, then place) instead of most-recent first. Ignored by other tools.
  @JsonKey(defaultValue: false)
  final bool bestFirst;
  /// Used only when [memberNumber] misses. A unique name match is returned
  /// with matchedBy "name" and the requested number alongside the stored one.
  final String? name;
  /// [get_shooter_match_results] only. Keep finishes with in-division place
  /// from 1 through this value.
  final int? maxPlace;

  factory ShooterLookupArgs.fromJson(Map<String, dynamic> json) =>
      _$ShooterLookupArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$ShooterLookupArgsToJson(this);
}

@JsonSerializable()
class GetLeaderboardArgs {
  GetLeaderboardArgs({
    this.project,
    this.group,
    this.groupUuid,
    this.sort,
    this.limit = 25,
    this.minMatches = 0,
    this.seenSince,
    this.changeSince,
    this.ascending = false,
    this.offset = 0,
  });

  final String? project;
  final String? group;
  final String? groupUuid;
  /// RatingSortMode name (e.g. rating, agedRating, lastChange, trend).
  final String? sort;
  @JsonKey(defaultValue: 25)
  final int limit;
  @JsonKey(defaultValue: 0)
  final int minMatches;
  /// YYYY-MM-DD. Default: Jan 1 of the year before the project's latest match.
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? seenSince;
  /// Optional date for trend-since-date sorting.
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? changeSince;
  /// When true, reverse the usual high-first order. For lastChange and trend,
  /// that lists the largest drops first.
  @JsonKey(defaultValue: false)
  final bool ascending;
  /// Rows to skip. Place numbers stay absolute, so offset = p90 rank - 1 reads that row.
  @JsonKey(defaultValue: 0)
  final int offset;

  factory GetLeaderboardArgs.fromJson(Map<String, dynamic> json) =>
      _$GetLeaderboardArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$GetLeaderboardArgsToJson(this);
}

@JsonSerializable()
class GetMatchScoresArgs {
  GetMatchScoresArgs({
    this.matchId,
    this.matchQuery,
    this.division,
    this.group,
    this.groupUuid,
    this.project,
    this.overall = false,
    this.femaleOnly = false,
    this.ageCategory,
    this.category,
    this.topN = kDefaultMatchPoolTopN,
    this.includeStages = false,
    this.includeScoringEventCounts = false,
  });

  final int? matchId;
  final String? matchQuery;
  final String? division;
  final String? group;
  final String? groupUuid;
  final String? project;
  @JsonKey(defaultValue: false)
  final bool overall;
  @JsonKey(defaultValue: false)
  final bool femaleOnly;
  final String? ageCategory;
  final String? category;
  final int topN;
  @JsonKey(defaultValue: false)
  final bool includeStages;
  @JsonKey(defaultValue: false)
  final bool includeScoringEventCounts;

  factory GetMatchScoresArgs.fromJson(Map<String, dynamic> json) =>
      _$GetMatchScoresArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$GetMatchScoresArgsToJson(this);
}

@JsonSerializable()
class GetCompetitorStageScoresArgs {
  GetCompetitorStageScoresArgs({
    this.matchId,
    this.matchQuery,
    this.memberNumber,
    this.ratingId,
    this.division,
    this.group,
    this.groupUuid,
    this.project,
    this.overall = false,
    this.includeScoringEventCounts = false,
  });

  final int? matchId;
  final String? matchQuery;
  final String? memberNumber;
  final int? ratingId;
  final String? division;
  final String? group;
  final String? groupUuid;
  final String? project;
  @JsonKey(defaultValue: false)
  final bool overall;
  @JsonKey(defaultValue: false)
  final bool includeScoringEventCounts;

  factory GetCompetitorStageScoresArgs.fromJson(Map<String, dynamic> json) =>
      _$GetCompetitorStageScoresArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$GetCompetitorStageScoresArgsToJson(this);
}

@JsonSerializable()
class SearchMatchPrepsArgs {
  SearchMatchPrepsArgs({
    this.project,
    this.query,
    this.after,
    this.before,
    this.limit = 10,
    this.hasPredictionsOnly = true,
  });

  final String? project;
  final String? query;
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? after;
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? before;
  @JsonKey(fromJson: _limit10FromJson)
  final int limit;
  @JsonKey(fromJson: _hasPredictionsOnlyFromJson)
  final bool hasPredictionsOnly;

  factory SearchMatchPrepsArgs.fromJson(Map<String, dynamic> json) =>
      _$SearchMatchPrepsArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$SearchMatchPrepsArgsToJson(this);
}

@JsonSerializable()
class ListPredictionSetsArgs {
  ListPredictionSetsArgs({
    required this.prepId,
  });

  @JsonKey(fromJson: researchIdFromJson)
  final String prepId;

  factory ListPredictionSetsArgs.fromJson(Map<String, dynamic> json) =>
      _$ListPredictionSetsArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$ListPredictionSetsArgsToJson(this);
}

@JsonSerializable()
class GetPredictionsArgs {
  GetPredictionsArgs({
    this.predictionSetId,
    this.prepId,
    this.group,
    this.groupUuid,
    this.topN = kDefaultPredictionTopN,
  });

  @JsonKey(fromJson: researchIdFromJsonNullable)
  final String? predictionSetId;
  @JsonKey(fromJson: researchIdFromJsonNullable)
  final String? prepId;
  final String? group;
  final String? groupUuid;
  @JsonKey(fromJson: _topNPredictionFromJson)
  final int topN;

  factory GetPredictionsArgs.fromJson(Map<String, dynamic> json) =>
      _$GetPredictionsArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$GetPredictionsArgsToJson(this);
}

@JsonSerializable()
class SearchPredictionsArgs {
  SearchPredictionsArgs({
    this.predictionSetId,
    this.prepId,
    this.group,
    this.groupUuid,
    this.memberNumber,
    this.ratingId,
    this.query,
    this.memberNumbers,
    this.ratingIds,
    this.limit = kDefaultPredictionSearchLimit,
  });

  @JsonKey(fromJson: researchIdFromJsonNullable)
  final String? predictionSetId;
  @JsonKey(fromJson: researchIdFromJsonNullable)
  final String? prepId;
  final String? group;
  final String? groupUuid;
  final String? memberNumber;
  @JsonKey(fromJson: researchIntFromJsonNullable)
  final int? ratingId;
  final String? query;
  @JsonKey(fromJson: researchStringListFromJson)
  final List<String>? memberNumbers;
  @JsonKey(fromJson: researchIntListFromJson)
  final List<int>? ratingIds;
  @JsonKey(fromJson: _predictionSearchLimitFromJson)
  final int limit;

  factory SearchPredictionsArgs.fromJson(Map<String, dynamic> json) =>
      _$SearchPredictionsArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$SearchPredictionsArgsToJson(this);
}

@JsonSerializable()
class GetPackageMoversArgs {
  GetPackageMoversArgs({
    this.project,
    this.group,
    this.groups,
    this.groupUuid,
    this.since,
    this.seenSince,
    this.minMatches = kDefaultRatingFieldMinMatches,
    this.direction = "both",
    this.minRatingPct,
    this.signalPct,
    this.signalBasis = "package",
    this.limit = kDefaultPackageMoverLimit,
  });

  final String? project;
  final String? group;
  /// Comma-separated rating group names.
  final String? groups;
  final String? groupUuid;
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? since;
  @JsonKey(fromJson: researchDateOnlyFromJsonNullable, toJson: researchDateOnlyToJson)
  final DateTime? seenSince;
  @JsonKey(defaultValue: kDefaultRatingFieldMinMatches)
  final int minMatches;
  /// "up", "down", or "both".
  @JsonKey(defaultValue: "both")
  final String direction;
  final int? minRatingPct;
  final int? signalPct;
  /// "package" (default) ranks lastChange/trend among package shooters.
  /// "active" ranks them on the whole seenSince field. ratingPct is always active-field.
  @JsonKey(defaultValue: "package")
  final String signalBasis;
  @JsonKey(defaultValue: kDefaultPackageMoverLimit)
  final int limit;

  factory GetPackageMoversArgs.fromJson(Map<String, dynamic> json) =>
      _$GetPackageMoversArgsFromJson(researchArgsJson(json));
  Map<String, dynamic> toJson() => _$GetPackageMoversArgsToJson(this);
}

int _limit10FromJson(Object? value) => researchIntFromJsonNullable(value) ?? 10;

bool _hasPredictionsOnlyFromJson(Object? value) =>
    researchBoolFromJson(value, defaultValue: true);

int _topNPredictionFromJson(Object? value) =>
    researchIntFromJsonNullable(value) ?? kDefaultPredictionTopN;

int _predictionSearchLimitFromJson(Object? value) =>
    researchIntFromJsonNullable(value) ?? kDefaultPredictionSearchLimit;
