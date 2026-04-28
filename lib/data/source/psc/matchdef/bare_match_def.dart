/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:json_annotation/json_annotation.dart';

part 'bare_match_def.g.dart';

@JsonSerializable()
class BareMatchDef {
  @JsonKey(name: "match_id")
  String id = "";

  @JsonKey(name: "match_name")
  String name = "";

  @JsonKey(name: "match_date")
  String rawDate = "";

  @JsonKey(name: "match_type")
  String matchType = "";

  @JsonKey(name: "match_subtype", defaultValue: "")
  String matchSubtype = "";

  @JsonKey(name: "match_level", defaultValue: "")
  String levelName = "";

  @JsonKey(includeFromJson: false, includeToJson: false)
  Map<String, dynamic> matchDefJson = {};

  @JsonKey(includeFromJson: false, includeToJson: false)
  Map<String, dynamic> scoresJson = {};

  BareMatchDef();

  factory BareMatchDef.fromJson(Map<String, dynamic> json) {
    var matchDef = _$BareMatchDefFromJson(json);
    matchDef.matchDefJson = json;
    return matchDef;
  }
  Map<String, dynamic> toJson() => _$BareMatchDefToJson(this);
}
