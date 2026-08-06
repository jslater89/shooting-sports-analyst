/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:json_annotation/json_annotation.dart";

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
  return fromJson(mcpArgumentsToJsonMap(arguments));
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
      _$ListRatingProjectsArgsFromJson(json);
  Map<String, dynamic> toJson() => _$ListRatingProjectsArgsToJson(this);
}

@JsonSerializable()
class SearchMatchesArgs {
  SearchMatchesArgs({
    this.query = "",
    this.limit = 10,
  });

  @JsonKey(defaultValue: "")
  final String query;
  @JsonKey(defaultValue: 10)
  final int limit;

  factory SearchMatchesArgs.fromJson(Map<String, dynamic> json) =>
      _$SearchMatchesArgsFromJson(json);
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
  });

  final int? matchId;
  final String? matchQuery;
  final String? project;
  @JsonKey(defaultValue: false)
  final bool byRatingGroup;
  @JsonKey(defaultValue: 1)
  final int topN;

  factory GetMatchWinnersArgs.fromJson(Map<String, dynamic> json) =>
      _$GetMatchWinnersArgsFromJson(json);
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
    this.topN,
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
  final int? topN;

  factory GetMatchResultsArgs.fromJson(Map<String, dynamic> json) =>
      _$GetMatchResultsArgsFromJson(json);
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

  @JsonKey(defaultValue: "")
  final String query;
  final String? memberNumber;
  final String? project;
  final String? group;
  final String? groupUuid;
  @JsonKey(defaultValue: 20)
  final int limit;
  @JsonKey(defaultValue: false)
  final bool includeInternal;

  factory SearchShootersArgs.fromJson(Map<String, dynamic> json) =>
      _$SearchShootersArgsFromJson(json);
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
  });

  final String? memberNumber;
  final int? ratingId;
  final String? project;
  final String? group;
  final String? groupUuid;
  final int? limit;
  @JsonKey(defaultValue: false)
  final bool includeInternal;

  factory ShooterLookupArgs.fromJson(Map<String, dynamic> json) =>
      _$ShooterLookupArgsFromJson(json);
  Map<String, dynamic> toJson() => _$ShooterLookupArgsToJson(this);
}
