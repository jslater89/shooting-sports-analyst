import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/match_info_zip.dart';
import 'package:shooting_sports_analyst/data/source/psc/parse_utils.dart';
import 'package:shooting_sports_analyst/logger.dart';

part 'hitfactor_scorelogs.g.dart';

var _log = SSALogger("HitFactorScoreLogs");

class HitFactorScoreLogs {
  final List<HitFactorScoreLog> logs;

  HitFactorScoreLogs(ScoreLogs rawLogs) :
    logs = rawLogs.logs.map((e) => HitFactorScoreLog.fromJson(e)).toList();
}

@JsonSerializable()
class HitFactorScoreLog {
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

  HitFactorScoreLog({
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

  Map<String, int>? _eventNamesToCounts;
  double? _time;
  List<double>? _stringTimes;

  bool get isValid {
    if(_eventNamesToCounts == null || _time == null) {
      _processScore();
    }
    return _eventNamesToCounts != null && _time != null;
  }

  bool get isValidPointsOnly {
    if(_eventNamesToCounts == null) {
      _processScore();
    }
    return _eventNamesToCounts != null;
  }

  Map<String, int> get eventNamesToCounts {
    if(_eventNamesToCounts == null) {
      _eventNamesToCounts = {};

      _processScore();
    }
    return _eventNamesToCounts!;
  }

  List<double> get stringTimes {
    if(_stringTimes == null) {
      _processScore();
    }
    return _stringTimes ?? [];
  }

  double get time {
    if(_time == null) {
      _processScore();
    }
    if(_time == null) {
      _log.w("Time is null for score log $logUuid");
      _log.v("Original log: ${jsonEncode(originalLog)}");
    }
    return _time ?? 0.0;
  }

  DateTime get modified {
    var updated = updatedAt.endsWith("Z") ? updatedAt : "${updatedAt}Z";
    return parseUtcDate(updated);
  }

  void _processScore() {
    var segments = score.split(RegExp(r"<br\s*/?>"));
    var mapEntries = segments.map((e) => e.split(':')).map((e) => MapEntry(e[0], e.length >= 2 ? double.tryParse(e[1]) ?? 0.0 : 0.0));
    if(mapEntries.isEmpty) {
      // null everything will be detected as invalid
      return;
    }
    List<MapEntry<String, String>> stringMapEntries = [];
    for(var segment in segments) {
      var parts = segment.split(':');
      if(parts.length >= 2) {
        stringMapEntries.add(MapEntry(parts[0], parts[1]));
      }
      else {
        _log.w("Unknown score segment: $segment");
        _stringTimes ??= [];
        _time ??= 0.0;
      }
    }
    Map<String, String> stringEntries = Map.fromEntries(stringMapEntries);
    var eventsOnly = <String, int>{};
    for(var entry in mapEntries) {
      if(entry.key.toLowerCase() == "time") {
        _time = entry.value;
        _stringTimes = [entry.value];
      }
      else if(entry.key.toLowerCase() == "times") {
        // String times are stored as a json-formatted array of doubles, e.g. "[1.2, 2.3, 3.4]"
        var stringTimes = stringEntries[entry.key]!.replaceAll(RegExp(r"[\[\]]"), '').split(',').map((e) => double.tryParse(e) ?? 0).toList();
        _stringTimes = stringTimes;
        _time = stringTimes.sum;
      }
      else if(entry.key.toLowerCase() == "hf") {
        // ignore
      }
      else {
        eventsOnly[entry.key] = entry.value.round();
      }
    }
    _eventNamesToCounts = eventsOnly;
  }

  factory HitFactorScoreLog.fromJson(Map<String, dynamic> json) {
    var log = _$HitFactorScoreLogFromJson(json);
    log.originalLog = json;
    return log;
  }
  Map<String, dynamic> toJson() => _$HitFactorScoreLogToJson(this);
}
