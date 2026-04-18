
import 'dart:math';

import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

part 'icore_matchdef.g.dart';

const icoreChronoScoringName = "Chrono";

@JsonSerializable()
class IcoreMatchDef {
  @JsonKey(name: "match_id", defaultValue: "")
  String uuid = "";

  @JsonKey(name: "match_name")
  String name = "";

  @JsonKey(name: "match_date")
  String rawDate = "";

  @JsonKey(name: "match_stages")
  List<IcoreStageDef> stages = [];

  @JsonKey(name: "match_shooters")
  List<IcoreShooterDef> shooters = [];

  @JsonKey(name: "match_cats")
  List<String> divisions = [];

  @JsonKey(name: "match_bonuses", defaultValue: [])
  List<IcoreBonus> bonuses = [];

  @JsonKey(name: "match_penalties", defaultValue: [])
  List<IcorePenalty> penalties = [];

  @JsonKey(name: "match_level", defaultValue: "L1")
  String levelName = "L1";

  IcoreMatchDef();

  factory IcoreMatchDef.fromJson(Map<String, dynamic> json) => _$IcoreMatchDefFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreMatchDefToJson(this);
}

@JsonSerializable()
class IcoreBonus {
  @JsonKey(name: "bon_name")
  String name = "";

  @JsonKey(name: "bon_val", defaultValue: 0)
  double value = 0;

  /// Whether the bonus is an on/off, or can occur multiple times.
  @JsonKey(name: "bon_bin", defaultValue: false)
  bool binary = false;

  @JsonKey(name: "bon_mod", defaultValue: "")
  String mod = "";

  IcoreBonus();

  factory IcoreBonus.fromJson(Map<String, dynamic> json) => _$IcoreBonusFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreBonusToJson(this);

  ScoringEvent toScoringEvent([int? sortOrder]) {
    return ScoringEvent(
      name,
      shortName: _shortEventName(name),
      timeChange: -value,
      sortOrder: sortOrder ?? 0,
      displayInOverview: false,
      dynamic: true,
    );
  }
}

String _shortEventName(String name) {
  var parts = name.split(" ");
  if(parts.length > 1) {
    // If there are multiple words, use the first letter of each, up to 3 letters.
    var abbreviated = parts.map(
      (s) => s.isNotEmpty ? s[0] : ""
    ).join().toUpperCase();
    return abbreviated.substring(0, min(3, abbreviated.length));
  }
  else {
    // If there is only one word, use the first 3 letters.
    return name.toUpperCase().substring(0, min(3, name.length));
  }
}

@JsonSerializable()
class IcorePenalty {
  IcorePenalty();

  IcorePenalty.create({required this.name, required this.value, required this.binary});

  @JsonKey(name: "pen_name")
  String name = "";

  @JsonKey(name: "pen_val", defaultValue: 0)
  double value = 0;

  /// Whether the penalty is an on/off, or can occur multiple times.
  ///
  /// e.g. chrono failure is a binary (can only be entered once), but other
  /// penalties are not.
  @JsonKey(name: "pen_bin", defaultValue: false)
  bool binary = false;

  factory IcorePenalty.fromJson(Map<String, dynamic> json) => _$IcorePenaltyFromJson(json);
  Map<String, dynamic> toJson() => _$IcorePenaltyToJson(this);

  ScoringEvent toScoringEvent([int? sortOrder]) {
    return ScoringEvent(
      name,
      shortName: _shortEventName(name),
      timeChange: value,
      sortOrder: sortOrder ?? 0,
      displayInOverview: false,
      dynamic: true,
    );
  }
}

@JsonSerializable()
class IcoreStageDef {
  @JsonKey(name: "stage_name")
  String name = "";

  @JsonKey(name: "stage_uuid")
  String uuid = "";

  @JsonKey(name: "stage_number")
  int stageNumber = -1;

  @JsonKey(name: "stage_targets", defaultValue: [])
  List<IcoreTarget> targets = [];

  @JsonKey(name: "stage_poppers")
  int steel = -1;

  @JsonKey(name: "stage_classifier")
  bool classifier = false;

  @JsonKey(name: "stage_classifiercode")
  String classifierCode = "";

  @JsonKey(name: "stage_deleted", defaultValue: false)
  bool deleted = false;

  /// A transient map of target index to nonstandard target hit for hits named
  /// "X".
  @JsonKey(includeToJson: false, includeFromJson: false)
  Map<int, ScoringEvent> nonstandardX = {};

  @JsonKey(name: "stage_scoretype", defaultValue: "")
  String scoreType = "";

  int get minRounds {
    if(steel < 0) throw StateError("invalid steel target count");
    int total = steel;

    for(var t in targets) {
      total += t.requiredShots;
    }

    return total;
  }

  @JsonKey(name: "stage_strings")
  int strings = 1;

  IcoreStageDef();

  factory IcoreStageDef.fromJson(Map<String, dynamic> json) => _$IcoreStageDefFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreStageDefToJson(this);
}

@JsonSerializable()
class IcoreTarget {
  @JsonKey(name: "target_number", defaultValue: -1)
  int number = -1;

  @JsonKey(name: "target_reqshots", defaultValue: 2)
  int requiredShots = 2;

  @JsonKey(name: "target_xmult", defaultValue: 1)
  double xMult = 1;

  IcoreTarget();

  factory IcoreTarget.fromJson(Map<String, dynamic> json) => _$IcoreTargetFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreTargetToJson(this);
}

@JsonSerializable()
class IcoreShooterDef {
  @JsonKey(name: "sh_id", defaultValue: "")
  String memberNumber = "";

  @JsonKey(name: "sh_sqd", defaultValue: 0)
  int squad = 0;

  @JsonKey(name: "sh_fn", defaultValue: "")
  String firstName = "";

  @JsonKey(name: "sh_ln", defaultValue: "")
  String lastName = "";

  @JsonKey(name: "sh_uuid")
  String uuid = "";

  @JsonKey(name: "sh_eml")
  String? email;

  @JsonKey(name: "sh_ctgs", defaultValue: "[]")
  String rawCategories = "[]";

  @JsonKey(name: "sh_grd", defaultValue: "U")
  String className = "U";

  @JsonKey(name: "sh_dvp", defaultValue: "")
  String divisionName = "";

  @JsonKey(name: "sh_st", defaultValue: "")
  String? state;

  // TODO: see if we need PF based on how PS2 does Big 6

  @JsonKey(name: "sh_del", defaultValue: false)
  bool deleted = false;

  @JsonKey(name: "sh_dq", defaultValue: false)
  bool disqualified = false;

  IcoreShooterDef();

  factory IcoreShooterDef.fromJson(Map<String, dynamic> json) => _$IcoreShooterDefFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreShooterDefToJson(this);
}
