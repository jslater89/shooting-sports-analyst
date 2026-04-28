/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/match_info_zip.dart';
import 'package:shooting_sports_analyst/data/source/psc/parse_utils.dart';

part 'idpa_scorelogs.g.dart';

class IdpaScoreLogs {
  final List<IdpaScoreLog> logs;

  IdpaScoreLogs(ScoreLogs rawLogs) :
    logs = rawLogs.logs.map((e) => IdpaScoreLog.fromJson(e)).toList();
}

@JsonSerializable()
class IdpaScoreLog {
  final int id;
  @JsonKey(name: 'match_uuid')
  final String matchUuid;
  @JsonKey(name: 'log_uuid')
  final String logUuid;
  @JsonKey(name: 'device_id')
  final String deviceId;
  @JsonKey(name: 'device_name')
  final String deviceName;
  @JsonKey(name: 'operator')
  final String operatorName;
  final String timestamp;
  @JsonKey(name: 'timestamp_local')
  final String timestampLocal;
  @JsonKey(name: 'shooter_unique_id')
  final String shooterUniqueId;
  @JsonKey(name: 'shooter_first_name')
  final String shooterFirstName;
  @JsonKey(name: 'shooter_last_name')
  final String shooterLastName;
  @JsonKey(name: 'shooter_id')
  final String shooterId;
  @JsonKey(name: 'stage_uuid')
  final String stageUuid;
  @JsonKey(name: 'stage_name', defaultValue: "")
  final String stageName;
  final String score;
  @JsonKey(name: 'penalty_reasons', defaultValue: "")
  final String penaltyReasons;
  @JsonKey(name: 'dq_reasons', defaultValue: "")
  final String dqReasons;
  @JsonKey(name: 'contact_phone')
  final String? contactPhone;
  @JsonKey(name: 'contact_email', defaultValue: "")
  final String contactEmail;
  @JsonKey(name: 'created_at')
  final String createdAt;
  @JsonKey(name: 'updated_at')
  final String updatedAt;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Map<String, dynamic>? originalLog;

  IdpaScoreLog({
    required this.id,
    required this.matchUuid,
    required this.logUuid,
    required this.deviceId,
    required this.deviceName,
    required this.operatorName,
    required this.timestamp,
    required this.timestampLocal,
    required this.shooterUniqueId,
    required this.shooterFirstName,
    required this.shooterLastName,
    required this.shooterId,
    required this.stageUuid,
    required this.stageName,
    required this.score,
    required this.penaltyReasons,
    required this.dqReasons,
    this.contactPhone,
    required this.contactEmail,
    required this.createdAt,
    required this.updatedAt,
  });

  double? _rawTime;
  double? _finalTime;
  Map<String, int>? _eventNamesToCounts;

  bool get isValid {
    if(_eventNamesToCounts == null || _finalTime == null || _rawTime == null) {
      _processScore();
    }
    return _eventNamesToCounts != null && _finalTime != null && _rawTime != null;
  }

  Map<String, int> get eventNamesToCounts {
    if(_eventNamesToCounts == null) {
      _processScore();
    }
    return _eventNamesToCounts!;
  }

  double get rawTime {
    if(_rawTime == null) {
      _processScore();
    }
    return _rawTime!;
  }

  double get finalTime {
    if(_finalTime == null) {
      _processScore();
    }
    return _finalTime!;
  }

  DateTime get modified {
    var updated = updatedAt.endsWith("Z") ? updatedAt : "${updatedAt}Z";
    return parseUtcDate(updated);
  }

  void _processScore() {
    var segments = score.split(RegExp(r"<br\s*/?>"));
    var mapEntries = segments.map((e) => e.split(':')).map((e) => MapEntry(e[0], double.tryParse(e[1]) ?? 0));
    var eventsOnly = <String, int>{};
    for(var entry in mapEntries) {
      if(entry.key.toLowerCase() == "time") {
        _rawTime = entry.value;
      }
      else if(entry.key.toLowerCase() == "final") {
        _finalTime = entry.value;
      }
      else {
        eventsOnly[entry.key] = entry.value.round();
      }
    }
    _eventNamesToCounts = eventsOnly;
  }

  factory IdpaScoreLog.fromJson(Map<String, dynamic> json) {
    var log = _$IdpaScoreLogFromJson(json);
    log.originalLog = json;
    return log;
  }
  Map<String, dynamic> toJson() => _$IdpaScoreLogToJson(this);
}