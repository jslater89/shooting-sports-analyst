/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:json_annotation/json_annotation.dart';

part 'idpa_matchdef.g.dart';

@JsonSerializable()
class IdpaLikeMatchDef {
  @JsonKey(name: "match_id", defaultValue: "")
  String uuid = "";

  @JsonKey(name: "match_name")
  String name = "";

  @JsonKey(name: "match_date")
  String rawDate = "";

  @JsonKey(name: "match_shooters")
  List<IdpaShooterDef> shooters = [];

  @JsonKey(name: "match_stages")
  List<IdpaStageDef> stages = [];

  @JsonKey(name: "match_penalties")
  List<IdpaPenalty> penalties = [];

  @JsonKey(name: "match_cats")
  List<String> divisions = [];

  IdpaLikeMatchDef();

  factory IdpaLikeMatchDef.fromJson(Map<String, dynamic> json) => _$IdpaLikeMatchDefFromJson(json);
  Map<String, dynamic> toJson() => _$IdpaLikeMatchDefToJson(this);
}

@JsonSerializable()
class IdpaShooterDef {
  @JsonKey(name: "sh_id", defaultValue: "")
  String memberNumber = "";
  @JsonKey(name: "sh_sqd", defaultValue: 0)
  int squad = 0;
  @JsonKey(name: "sh_fn")
  String firstName = "";
  @JsonKey(name: "sh_ln")
  String lastName = "";
  @JsonKey(name: "sh_eml")
  String? email;
  @JsonKey(name: "sh_uuid")
  String uuid = "";
  @JsonKey(name: "sh_ctgs", defaultValue: "[]")
  String rawCategories = "[]";
  @JsonKey(name: "sh_grd", defaultValue: "UN")
  String className = "UN";
  @JsonKey(name: "sh_dvp", defaultValue: "")
  String divisionName = "";
  @JsonKey(name: "sh_del", defaultValue: false)
  bool deleted = false;
  @JsonKey(name: "sh_dq", defaultValue: false)
  bool disqualified = false;

  IdpaShooterDef();

  factory IdpaShooterDef.fromJson(Map<String, dynamic> json) => _$IdpaShooterDefFromJson(json);
  Map<String, dynamic> toJson() => _$IdpaShooterDefToJson(this);
}

const IdpaStageScoreType = "IDPA";

@JsonSerializable()
class IdpaStageDef {
  @JsonKey(name: "stage_strings")
  int strings = 1;
  @JsonKey(name: "stage_numtargs")
  int paper = -1;
  @JsonKey(name: "stage_number")
  int stageNumber = -1;
  @JsonKey(name: "stage_name")
  String name = "";
  @JsonKey(name: "stage_uuid")
  String uuid = "";
  @JsonKey(name: "stage_poppers")
  int steel = -1;
  @JsonKey(name: "stage_scoretype")
  String scoreType = "";
  @JsonKey(name: "stage_deleted", defaultValue: false)
  bool deleted = false;

  IdpaStageDef();

  factory IdpaStageDef.fromJson(Map<String, dynamic> json) => _$IdpaStageDefFromJson(json);
  Map<String, dynamic> toJson() => _$IdpaStageDefToJson(this);
}

@JsonSerializable()
class IdpaPenalty {
  @JsonKey(name: "pen_name")
  String name;

  @JsonKey(name: "pen_val")
  double value;

  IdpaPenalty({required this.name, required this.value});

  factory IdpaPenalty.fromJson(Map<String, dynamic> json) => _$IdpaPenaltyFromJson(json);
  Map<String, dynamic> toJson() => _$IdpaPenaltyToJson(this);
}
