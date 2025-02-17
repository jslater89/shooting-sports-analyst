/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_view.dart';
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

  List<Widget> expandedUi(BuildContext context) {
    return type.expandedUi(context, data);
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
      }
    }
    return _data!;
  }
  set data(RatingReportData value) {
    _data = value;
    jsonEncodedData = jsonEncode(value);
    _log.vv("json data: $jsonEncodedData");
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
  blacklistedMapping;

  String get dropdownName => switch(this) {
    RatingReportType.stringDifferenceNameForSameNumber => "Possibly-distinct names",
    RatingReportType.ratingMergeWithDualHistory => "Merged ratings with history",
    RatingReportType.dataEntryFixLoop => "Data entry fix loop",
    RatingReportType.duplicateDataEntryFix => "Duplicate data entry fix",
    RatingReportType.duplicateBlacklistEntry => "Duplicate blacklist entry",
    RatingReportType.duplicateUserMapping => "Duplicate user mapping",
    RatingReportType.duplicateAutoMapping => "Duplicate auto mapping",
    RatingReportType.blacklistedMapping => "Blacklisted mapping",
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
    }
  }

  List<Widget> expandedUi(BuildContext context, RatingReportData data) {
    switch(this) {
      case RatingReportType.stringDifferenceNameForSameNumber:
        var typedData = data as StringDifferenceNameForSameNumber;
        return [
          Text(
            "The following names appear in the dataset for ${typedData.number} and have high string difference, which may indicate "
            "that they are different competitors. If they are, and you can identify an additional member number belonging to one "
            "of them, you can correct this issue by adding a data entry fix. If they are not distinct individuals, no action is "
            "required, but you can use a competitor name alias to resolve this report on the next full calculation."
          ),
          SizedBox(height: 8),
          ...typedData.names.map((name) => Text(" • $name")),
        ];
      case RatingReportType.ratingMergeWithDualHistory:
        var typedData = data as RatingMergeWithDualHistory;
        return [
          Text(
            "Ratings corresponding to the following member numbers were merged as a result of a member number mapping, "
            "but more than one rating had history data at the time of the merge. A full recalculation may be required for "
            "accurate ratings."
          ),
          SizedBox(height: 8),
          ...typedData.memberNumbers.map((number) => Text(" • $number")),
        ];
      case RatingReportType.dataEntryFixLoop:
        var typedData = data as DataEntryFixLoop;
        return [
          Text(
            "The following numbers are part of a data entry fix loop: data entry fixes occur for each number in this list, "
            "to the next, then cycle back to the first. At least one data entry fix from this list should be removed.\n\n"
            "This may indicate a bug in the shooter deduplicator. Please report it on Discord or GitHub."
          ),
          SizedBox(height: 8),
          Text(typedData.numbers.join(" → ")),
        ];
      case RatingReportType.duplicateDataEntryFix:
        var typedData = data as DuplicateDataEntryFix;
        return [
          Text(
            "The deduplicator attempted to add the data entry fix below, which duplicates an existing data entry fix. "
            "This is a deduplicator bug. Please report it on Discord or GitHub, including the information below and "
            "an export of your project file."
          ),
          SizedBox(height: 8),
          Text("Deduplicator name: ${typedData.deduplicatorName}"),
          Text("Source number: ${typedData.sourceNumber}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
      case RatingReportType.duplicateBlacklistEntry:
        var typedData = data as DuplicateBlacklistEntry;
        return [
          Text(
            "The deduplicator attempted to add the blacklist entry below, which duplicates an existing entry. "
            "This is a deduplicator bug. Please report it on Discord or GitHub, including the information below and "
            "an export of your project file."
          ),
          SizedBox(height: 8),
          Text("Source number: ${typedData.sourceNumber}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
      case RatingReportType.duplicateUserMapping:
        var typedData = data as DuplicateUserMapping;
        return [
          Text(
            "The user mapping below duplicates an existing user mapping. This may be an issue with the import of a "
            "pre-8.0 project, or it may indicate a deduplicator bug. Please report it on Discord or GitHub, including "
            "the information below and an export of your project file."
          ),
          SizedBox(height: 8),
          Text("Source number: ${typedData.sourceNumber}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
      case RatingReportType.duplicateAutoMapping:
        var typedData = data as DuplicateAutoMapping;
        return [
          Text(
            "The auto mapping below duplicates an existing auto mapping. This may be an issue with the import of a "
            "pre-8.0 project, or it may indicate a deduplicator bug. Please report it on Discord or GitHub, including "
            "the information below and an export of your project file."
          ),
          SizedBox(height: 8),
          Text("Source numbers: ${typedData.sourceNumbers.join(", ")}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
      case RatingReportType.blacklistedMapping:
        var typedData = data as BlacklistedMapping;
        return [
          Text(
            "The mapping below was detected and/or appears in the project settings, but is also blacklisted. "
            "The mapping was not applied. Remove the blacklist entry or the mapping to suppress this message."
          ),
          SizedBox(height: 8),
          Text("Source number: ${typedData.sourceNumber}"),
          Text("Target number: ${typedData.targetNumber}"),
        ];
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

  IconData get uiIcon => switch(this) {
    RatingReportSeverity.info => Icons.info,
    RatingReportSeverity.warning => Icons.warning,
    RatingReportSeverity.severe => Icons.cancel,
  };

  Color get uiColor => switch(this) {
    RatingReportSeverity.info => Colors.blue.shade700,
    RatingReportSeverity.warning => Colors.yellow.shade700,
    RatingReportSeverity.severe => Colors.red.shade600,
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
