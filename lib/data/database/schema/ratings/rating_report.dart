/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rating_report.g.dart';

@embedded
class RatingReport {
  RatingReport({this.type = RatingReportType.stringDifferenceNameForSameNumber, this.severity = RatingReportSeverity.info, RatingReportData? data}) {
    if(data != null) {
      this.data = data;
    }
    else {
      // just fill something in, since Isar embedded objects can't have required parameters
      this.data = StringDifferenceNameForSameNumber(names: [], number: "", ratingGroupUuid: "");
    }
  }

  @enumerated
  RatingReportType type;
  @enumerated
  RatingReportSeverity severity;

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
      }
    }
    return _data!;
  }
  set data(RatingReportData value) {
    _data = value;
    jsonEncodedData = jsonEncode(value);
  }

  @ignore
  RatingReportData? _data;

  String jsonEncodedData = "";
}

enum RatingReportType {
  stringDifferenceNameForSameNumber,
  ratingMergeWithDualHistory,
  dataEntryFixLoop,
}

enum RatingReportSeverity {
  info,
  warning,
  severe;
}

sealed class RatingReportData {
}

@JsonSerializable()
class StringDifferenceNameForSameNumber extends RatingReportData {
  StringDifferenceNameForSameNumber({required this.names, required this.number, required this.ratingGroupUuid});

  List<String> names;
  String number;
  String ratingGroupUuid;

  factory StringDifferenceNameForSameNumber.fromJson(Map<String, dynamic> json) => _$StringDifferenceNameForSameNumberFromJson(json);
  Map<String, dynamic> toJson() => _$StringDifferenceNameForSameNumberToJson(this);
}

@JsonSerializable()
class RatingMergeWithDualHistory extends RatingReportData {
  RatingMergeWithDualHistory({required this.ratingIds, required this.ratingGroupUuid});

  List<int> ratingIds;
  String ratingGroupUuid;

  factory RatingMergeWithDualHistory.fromJson(Map<String, dynamic> json) => _$RatingMergeWithDualHistoryFromJson(json);
  Map<String, dynamic> toJson() => _$RatingMergeWithDualHistoryToJson(this);
}

@JsonSerializable()
class DataEntryFixLoop extends RatingReportData {
  DataEntryFixLoop({required this.numbers});

  List<String> numbers;

  factory DataEntryFixLoop.fromJson(Map<String, dynamic> json) => _$DataEntryFixLoopFromJson(json);
  Map<String, dynamic> toJson() => _$DataEntryFixLoopToJson(this);
}