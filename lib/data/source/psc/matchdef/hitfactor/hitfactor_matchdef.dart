/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:json_annotation/json_annotation.dart';

part 'hitfactor_matchdef.g.dart';

@JsonSerializable()
class HitFactorMatchDef {
  @JsonKey(name: "match_id", defaultValue: "")
  String uuid = "";

  @JsonKey(name: "match_name", defaultValue: "")
  String name = "";

  @JsonKey(name: "match_date")
  String rawDate = "";

  @JsonKey(name: "match_creationdate", defaultValue: "")
  String rawCreationDate = "";

  @JsonKey(name: "match_cats")
  List<String> divisions = [];

  HitFactorMatchDef();

  @JsonKey(name: "match_stages")
  List<HitFactorStageDef> stages = [];

  @JsonKey(name: "match_shooters")
  List<HitFactorShooterDef> shooters = [];

  @JsonKey(name: "match_level", defaultValue: "L1")
  String levelName = "L1";

  factory HitFactorMatchDef.fromJson(Map<String, dynamic> json) => _$HitFactorMatchDefFromJson(json);
  Map<String, dynamic> toJson() => _$HitFactorMatchDefToJson(this);
}

const comstockScoring = "Comstock";
const virginiaScoring = "Virginia";
const fixedTimeScoring = "Fixed";
const chronoScoring = "Chrono";

@JsonSerializable()
class HitFactorStageDef {
  @JsonKey(name: "stage_strings")
  int strings = 1;
  @JsonKey(name: "stage_number")
  int stageNumber = -1;
  @JsonKey(name: "stage_name")
  String name = "";
  @JsonKey(name: "stage_uuid")
  String uuid = "";
  @JsonKey(name: "stage_scoretype")
  String scoreType = "Comstock";
  @JsonKey(name: "stage_targets", defaultValue: [])
  List<HitFactorTarget> targets = [];
  @JsonKey(name: "stage_poppers")
  int steel = -1;
  @JsonKey(name: "stage_classifier")
  bool classifier = false;
  @JsonKey(name: "stage_classifiercode")
  String classifierCode = "";
  @JsonKey(name: "stage_deleted", defaultValue: false)
  bool deleted = false;

  int get minRounds {
    if(steel < 0) throw StateError("invalid steel target count");
    int total = steel;

    for(var t in targets) {
      if(t.deleted) continue;
      total += t.requiredShots;
    }

    return total;
  }

  int get maxPoints {
    return minRounds * 5;
  }

  HitFactorStageDef();

  factory HitFactorStageDef.fromJson(Map<String, dynamic> json) => _$HitFactorStageDefFromJson(json);
  Map<String, dynamic> toJson() => _$HitFactorStageDefToJson(this);
}

@JsonSerializable()
class HitFactorTarget {
  @JsonKey(name: "target_number")
  int targetNumber = -1;
  @JsonKey(name: "target_reqshots")
  int requiredShots = 2;
  @JsonKey(name: "target_deleted", defaultValue: false)
  bool deleted = false;

  HitFactorTarget();
  factory HitFactorTarget.fromJson(Map<String, dynamic> json) => _$HitFactorTargetFromJson(json);
  Map<String, dynamic> toJson() => _$HitFactorTargetToJson(this);
}

@JsonSerializable()
class HitFactorShooterDef {
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

  String get uuid => uuidProperty ?? uidProperty ?? "";

  @JsonKey(name: "sh_uuid")
  String? uuidProperty;
  @JsonKey(name: "sh_uid")
  String? uidProperty;


  @JsonKey(name: "sh_ctgs", defaultValue: "[]")
  String rawCategories = "[]";
  @JsonKey(name: "sh_grd", defaultValue: "U")
  String className = "U";
  @JsonKey(name: "sh_dvp")
  String divisionName = "";
  @JsonKey(name: "sh_pf")
  String powerFactorName = "SUB";
  @JsonKey(name: "sh_del", defaultValue: false)
  bool deleted = false;
  @JsonKey(name: "sh_dq", defaultValue: false)
  bool disqualified = false;

  @JsonKey(name: "sh_st", includeIfNull: false)
  String? shooterState;

  HitFactorShooterDef();
  factory HitFactorShooterDef.fromJson(Map<String, dynamic> json) => _$HitFactorShooterDefFromJson(json);
  Map<String, dynamic> toJson() => _$HitFactorShooterDefToJson(this);
}
