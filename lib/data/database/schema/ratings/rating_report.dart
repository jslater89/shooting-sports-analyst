/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'rating_report.g.dart';

var _log = SSALogger("RatingReport");

@embedded
class RatingReport {
  RatingReport({
    this.type = RatingReportType.stringDifferenceNameForSameNumber,
    this.severity = RatingReportSeverity.info,
    RatingReportData? data,
  }) {
    if(data != null) {
      this.data = data;
    }
  }

  @enumerated
  RatingReportType type;
  @enumerated
  RatingReportSeverity severity;

  @ignore
  String get ratingGroupName => data.ratingGroupName;

  @ignore
  String get uiTitle {
    return "${type.listItemTitle(data)}";
  }

  @ignore
  String? get uiSubtitle {
    return type.listItemSubtitle(data);
  }

  @ignore
  RatingReportData get data {
    if(_data == null) {
      switch(type) {
        case RatingReportType.stringDifferenceNameForSameNumber:
          _data = StringDifferenceNameForSameNumber.fromJson(jsonDecode(jsonEncodedData));
          break;
        case RatingReportType.ratingMergeWithDualHistory:
          _data = RatingMergeWithDualHistory.fromJson(jsonDecode(jsonEncodedData));
          break;
        case RatingReportType.dataEntryFixLoop:
          _data = DataEntryFixLoop.fromJson(jsonDecode(jsonEncodedData));
          break;
        case RatingReportType.duplicateDataEntryFix:
          _data = DuplicateDataEntryFix.fromJson(jsonDecode(jsonEncodedData));
          break;
        case RatingReportType.duplicateBlacklistEntry:
          _data = DuplicateBlacklistEntry.fromJson(jsonDecode(jsonEncodedData));
          break;
        case RatingReportType.duplicateUserMapping:
          _data = DuplicateUserMapping.fromJson(jsonDecode(jsonEncodedData));
          break;
        case RatingReportType.duplicateAutoMapping:
          _data = DuplicateAutoMapping.fromJson(jsonDecode(jsonEncodedData));
          break;
        case RatingReportType.blacklistedMapping:
          _data = BlacklistedMapping.fromJson(jsonDecode(jsonEncodedData));
          break;
        case RatingReportType.fiftyPercentDnfs:
          _data = FiftyPercentDnfs.fromJson(jsonDecode(jsonEncodedData));
          break;
      }
    }
    return _data!;
  }
  set data(RatingReportData value) {
    _data = value;
    jsonEncodedData = jsonEncode(value);
    // _log.vv("json data: $jsonEncodedData");
  }

  @ignore
  RatingReportData? _data;

  String jsonEncodedData = "";

  @override
  String toString() {
    return "${severity.uiLabel} - ${type.listItemTitle(data)} - $data";
  }

  @override
  bool operator==(Object other) {
    if(other is! RatingReport) {
      return false;
    }
    if(severity != other.severity || type != other.type || data != other.data) {
      return false;
    }
    return data == other.data;
  }
}

enum RatingReportType {
  stringDifferenceNameForSameNumber,
  ratingMergeWithDualHistory,
  dataEntryFixLoop,
  duplicateDataEntryFix,
  duplicateBlacklistEntry,
  duplicateUserMapping,
  duplicateAutoMapping,
  blacklistedMapping,
  fiftyPercentDnfs;

  String get dropdownName => switch(this) {
    RatingReportType.stringDifferenceNameForSameNumber => "Possibly-distinct names",
    RatingReportType.ratingMergeWithDualHistory => "Merged ratings with history",
    RatingReportType.dataEntryFixLoop => "Data entry fix loop",
    RatingReportType.duplicateDataEntryFix => "Duplicate data entry fix",
    RatingReportType.duplicateBlacklistEntry => "Duplicate blacklist entry",
    RatingReportType.duplicateUserMapping => "Duplicate user mapping",
    RatingReportType.duplicateAutoMapping => "Duplicate auto mapping",
    RatingReportType.blacklistedMapping => "Blacklisted mapping",
    RatingReportType.fiftyPercentDnfs => "High DNF rate at match",
  };

  String listItemTitle(RatingReportData data) {
    switch(this) {
      case RatingReportType.stringDifferenceNameForSameNumber:
        var typedData = data as StringDifferenceNameForSameNumber;
        return "Possibly-distinct names for ${typedData.number} in ${typedData.ratingGroupName}";
      case RatingReportType.ratingMergeWithDualHistory:
        var typedData = data as RatingMergeWithDualHistory;
        return "Merged rating for ${typedData.memberNumbers.firstOrNull} has dual history in ${typedData.ratingGroupName}";
      case RatingReportType.dataEntryFixLoop:
        return "Data entry fix for  has loop in ${data.ratingGroupName}";
      case RatingReportType.duplicateDataEntryFix:
        return "Duplicate data entry fix in ${data.ratingGroupName}";
      case RatingReportType.duplicateBlacklistEntry:
        return "Duplicate blacklist entry in ${data.ratingGroupName}";
      case RatingReportType.duplicateUserMapping:
        return "Duplicate user mapping in ${data.ratingGroupName}";
      case RatingReportType.duplicateAutoMapping:
        return "Duplicate auto mapping in ${data.ratingGroupName}";
      case RatingReportType.blacklistedMapping:
        return "Blacklisted mapping in ${data.ratingGroupName}";
      case RatingReportType.fiftyPercentDnfs:
        return "High DNF rate at match in ${data.ratingGroupName}";
    }
  }

  String? listItemSubtitle(RatingReportData data) {
    switch(this) {
      case RatingReportType.stringDifferenceNameForSameNumber:
        var typedData = data as StringDifferenceNameForSameNumber;
        return "Names: ${typedData.names.join(", ")}";
      case RatingReportType.ratingMergeWithDualHistory:
        var typedData = data as RatingMergeWithDualHistory;
        return "Member numbers: ${typedData.memberNumbers.join(", ")}";
      case RatingReportType.dataEntryFixLoop:
        var typedData = data as DataEntryFixLoop;
        return "Numbers: ${typedData.numbers.join(", ")}";
      case RatingReportType.duplicateDataEntryFix:
        var typedData = data as DuplicateDataEntryFix;
        return "Source number: ${typedData.sourceNumber}, target number: ${typedData.targetNumber}, deduplicator name: ${typedData.deduplicatorName}";
      case RatingReportType.duplicateBlacklistEntry:
        var typedData = data as DuplicateBlacklistEntry;
        return "Source number: ${typedData.sourceNumber}, target number: ${typedData.targetNumber}";
      case RatingReportType.duplicateUserMapping:
        var typedData = data as DuplicateUserMapping;
        return "Source number: ${typedData.sourceNumber}, target number: ${typedData.targetNumber}";
      case RatingReportType.duplicateAutoMapping:
        var typedData = data as DuplicateAutoMapping;
        return "Source numbers: ${typedData.sourceNumbers.join(", ")}, target number: ${typedData.targetNumber}";
      case RatingReportType.blacklistedMapping:
        var typedData = data as BlacklistedMapping;
        return "${typedData.sourceNumber} → ${typedData.targetNumber}";
      case RatingReportType.fiftyPercentDnfs:
        var typedData = data as FiftyPercentDnfs;
        return "Match: ${typedData.matchName}";
    }
  }
}

enum RatingReportSeverity {
  info,
  warning,
  severe;

  String get uiLabel => switch(this) {
    RatingReportSeverity.info => "Info",
    RatingReportSeverity.warning => "Warning",
    RatingReportSeverity.severe => "Severe",
  };
}

sealed class RatingReportData {
  String get ratingGroupName;
}

@JsonSerializable()
class StringDifferenceNameForSameNumber extends RatingReportData {
  StringDifferenceNameForSameNumber({required this.names, required this.number, required this.ratingGroupUuid, required this.ratingGroupName});

  List<String> names;
  String number;
  String ratingGroupUuid;
  String ratingGroupName;
  factory StringDifferenceNameForSameNumber.fromJson(Map<String, dynamic> json) => _$StringDifferenceNameForSameNumberFromJson(json);
  Map<String, dynamic> toJson() => _$StringDifferenceNameForSameNumberToJson(this);

  @override
  bool operator==(Object other) {
    if(other is! StringDifferenceNameForSameNumber) {
      return false;
    }
    if(names.length != other.names.length || number != other.number || ratingGroupUuid != other.ratingGroupUuid) {
      return false;
    }
    if(!names.containsOnly(other.names)) {
      return false;
    }
    return true;
  }

  @override
  String toString() {
    return "StringDifferenceNameForSameNumber(names: $names, number: $number, ratingGroupUuid: $ratingGroupUuid, ratingGroupName: $ratingGroupName)";
  }
}

@JsonSerializable()
class RatingMergeWithDualHistory extends RatingReportData {
  RatingMergeWithDualHistory({required this.ratingIds, required this.memberNumbers, required this.ratingGroupUuid, required this.ratingGroupName});

  List<int> ratingIds;
  List<String> memberNumbers;
  String ratingGroupUuid;
  String ratingGroupName;

  factory RatingMergeWithDualHistory.fromJson(Map<String, dynamic> json) => _$RatingMergeWithDualHistoryFromJson(json);
  Map<String, dynamic> toJson() => _$RatingMergeWithDualHistoryToJson(this);

  @override
  bool operator==(Object other) {
    if(other is! RatingMergeWithDualHistory) {
      return false;
    }
    if(ratingGroupUuid != other.ratingGroupUuid) {
      return false;
    }
    if(memberNumbers.length != other.memberNumbers.length) {
      return false;
    }
    if(!memberNumbers.containsOnly(other.memberNumbers)) {
      return false;
    }
    return true;
  }

  @override
  String toString() {
    return "RatingMergeWithDualHistory(ratingIds: $ratingIds, memberNumbers: $memberNumbers, ratingGroupUuid: $ratingGroupUuid, ratingGroupName: $ratingGroupName)";
  }
}

@JsonSerializable()
class DataEntryFixLoop extends RatingReportData {
  DataEntryFixLoop({required this.numbers, required this.ratingGroupUuid, required this.ratingGroupName});

  List<String> numbers;
  String ratingGroupUuid;
  String ratingGroupName;

  factory DataEntryFixLoop.fromJson(Map<String, dynamic> json) => _$DataEntryFixLoopFromJson(json);
  Map<String, dynamic> toJson() => _$DataEntryFixLoopToJson(this);

  @override
  bool operator==(Object other) {
    if(other is! DataEntryFixLoop) {
      return false;
    }
    if(ratingGroupUuid != other.ratingGroupUuid) {
      return false;
    }
    if(numbers.length != other.numbers.length) {
      return false;
    }
    if(!numbers.containsOnly(other.numbers)) {
      return false;
    }
    return true;
  }

  @override
  String toString() {
    return "DataEntryFixLoop(numbers: $numbers, ratingGroupUuid: $ratingGroupUuid, ratingGroupName: $ratingGroupName)";
  }
}

@JsonSerializable()
class DuplicateDataEntryFix extends RatingReportData {
  DuplicateDataEntryFix({required this.sourceNumber, required this.targetNumber, required this.deduplicatorName, required this.ratingGroupUuid, required this.ratingGroupName});

  String sourceNumber;
  String targetNumber;
  String deduplicatorName;
  String ratingGroupUuid;
  String ratingGroupName;

  factory DuplicateDataEntryFix.fromJson(Map<String, dynamic> json) => _$DuplicateDataEntryFixFromJson(json);
  Map<String, dynamic> toJson() => _$DuplicateDataEntryFixToJson(this);

  @override
  bool operator==(Object other) {
    if(other is! DuplicateDataEntryFix) {
      return false;
    }
    return deduplicatorName == other.deduplicatorName
      && sourceNumber == other.sourceNumber
      && targetNumber == other.targetNumber
      && ratingGroupUuid == other.ratingGroupUuid;
  }

  @override
  String toString() {
    return "DuplicateDataEntryFix(sourceNumber: $sourceNumber, targetNumber: $targetNumber, deduplicatorName: $deduplicatorName, ratingGroupUuid: $ratingGroupUuid, ratingGroupName: $ratingGroupName)";
  }
}

@JsonSerializable()
class DuplicateBlacklistEntry extends RatingReportData {
  DuplicateBlacklistEntry({required this.sourceNumber, required this.targetNumber, required this.ratingGroupUuid, required this.ratingGroupName});

  String sourceNumber;
  String targetNumber;
  String ratingGroupUuid;
  String ratingGroupName;

  factory DuplicateBlacklistEntry.fromJson(Map<String, dynamic> json) => _$DuplicateBlacklistEntryFromJson(json);
  Map<String, dynamic> toJson() => _$DuplicateBlacklistEntryToJson(this);

  @override
  bool operator==(Object other) {
    if(other is! DuplicateBlacklistEntry) {
      return false;
    }
    return sourceNumber == other.sourceNumber
      && targetNumber == other.targetNumber
      && ratingGroupUuid == other.ratingGroupUuid;
  }

  @override
  String toString() {
    return "DuplicateBlacklistEntry(sourceNumber: $sourceNumber, targetNumber: $targetNumber, ratingGroupUuid: $ratingGroupUuid, ratingGroupName: $ratingGroupName)";
  }
}

@JsonSerializable()
class DuplicateUserMapping extends RatingReportData {
  DuplicateUserMapping({required this.sourceNumber, required this.targetNumber, required this.ratingGroupUuid, required this.ratingGroupName});

  String sourceNumber;
  String targetNumber;
  String ratingGroupUuid;
  String ratingGroupName;

  factory DuplicateUserMapping.fromJson(Map<String, dynamic> json) => _$DuplicateUserMappingFromJson(json);
  Map<String, dynamic> toJson() => _$DuplicateUserMappingToJson(this);

  @override
  bool operator==(Object other) {
    if(other is! DuplicateUserMapping) {
      return false;
    }
    return sourceNumber == other.sourceNumber
      && targetNumber == other.targetNumber
      && ratingGroupUuid == other.ratingGroupUuid;
  }

  @override
  String toString() {
    return "DuplicateUserMapping(sourceNumber: $sourceNumber, targetNumber: $targetNumber, ratingGroupUuid: $ratingGroupUuid, ratingGroupName: $ratingGroupName)";
  }
}

@JsonSerializable()
class DuplicateAutoMapping extends RatingReportData {
  DuplicateAutoMapping({required this.sourceNumbers, required this.targetNumber, required this.ratingGroupUuid, required this.ratingGroupName});

  List<String> sourceNumbers;
  String targetNumber;
  String ratingGroupUuid;
  String ratingGroupName;

  factory DuplicateAutoMapping.fromJson(Map<String, dynamic> json) => _$DuplicateAutoMappingFromJson(json);
  Map<String, dynamic> toJson() => _$DuplicateAutoMappingToJson(this);

  @override
  bool operator==(Object other) {
    if(other is! DuplicateAutoMapping) {
      return false;
    }
    if(sourceNumbers.length != other.sourceNumbers.length || targetNumber != other.targetNumber || ratingGroupUuid != other.ratingGroupUuid) {
      return false;
    }
    if(!sourceNumbers.containsOnly(other.sourceNumbers)) {
      return false;
    }
    return true;
  }

  @override
  String toString() {
    return "DuplicateAutoMapping(sourceNumbers: $sourceNumbers, targetNumber: $targetNumber, ratingGroupUuid: $ratingGroupUuid, ratingGroupName: $ratingGroupName)";
  }
}

@JsonSerializable()
class BlacklistedMapping extends RatingReportData {
  BlacklistedMapping({
    required this.sourceNumber,
    required this.targetNumber,
    required this.ratingGroupUuid,
    required this.ratingGroupName,
    required this.autoMapping,
  });

  String sourceNumber;
  String targetNumber;
  String ratingGroupUuid;
  String ratingGroupName;
  bool autoMapping;

  factory BlacklistedMapping.fromJson(Map<String, dynamic> json) => _$BlacklistedMappingFromJson(json);
  Map<String, dynamic> toJson() => _$BlacklistedMappingToJson(this);

  @override
  bool operator==(Object other) {
    if(other is! BlacklistedMapping) {
      return false;
    }
    return sourceNumber == other.sourceNumber
      && targetNumber == other.targetNumber
      && ratingGroupUuid == other.ratingGroupUuid
      && autoMapping == other.autoMapping;
  }

  @override
  String toString() {
    return "BlacklistedMapping(sourceNumber: $sourceNumber, targetNumber: $targetNumber, ratingGroupUuid: $ratingGroupUuid, ratingGroupName: $ratingGroupName, autoMapping: $autoMapping)";
  }
}

@JsonSerializable()
class FiftyPercentDnfs extends RatingReportData {
  FiftyPercentDnfs({
    required this.matchDbId,
    required this.matchName,
    required this.ratingGroupUuid,
    required this.ratingGroupName,
    required this.dnfRatio,
    required this.dnfCount,
    required this.competitorCount,
  });

  int matchDbId;
  String matchName;
  String ratingGroupUuid;
  String ratingGroupName;
  double dnfRatio;
  int dnfCount;
  int competitorCount;

  factory FiftyPercentDnfs.fromJson(Map<String, dynamic> json) => _$FiftyPercentDnfsFromJson(json);
  Map<String, dynamic> toJson() => _$FiftyPercentDnfsToJson(this);

  @override
  bool operator==(Object other) {
    if(other is! FiftyPercentDnfs) {
      return false;
    }
    return matchDbId == other.matchDbId && ratingGroupUuid == other.ratingGroupUuid;
  }

  @override
  String toString() {
    return "FiftyPercentDnfs(matchDbId: $matchDbId, matchName: $matchName, ratingGroupUuid: $ratingGroupUuid, ratingGroupName: $ratingGroupName)";
  }
}
