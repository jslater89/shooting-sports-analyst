/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/classifier_import.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'icore_export_converter.g.dart';

final _log = SSALogger("IcoreImporter");

@JsonSerializable()
class IcoreClassifierExport {
  IcoreClassifierExport({
    required this.scores,
  });
  factory IcoreClassifierExport.fromJson(Map<String, dynamic> json) => _$IcoreClassifierExportFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreClassifierExportToJson(this);

  factory IcoreClassifierExport.fromFile(File file) {
    List<dynamic> json = jsonDecode(file.readAsStringSync());
    for(var object in json) {
      if(object is Map<String, dynamic>) {
        if(object['data'] is List<dynamic>) {
          return IcoreClassifierExport.fromJson(object);
        }
      }
    }
    throw Exception("No data found in file");
  }

  List<ClassifierScore> toAnalystScores() {
    return scores.map((e) => e.toAnalystScore()).toList();
  }

  @JsonKey(name: 'data')
  List<IcoreClassifierRecord> scores;
}

@JsonSerializable()
class IcoreClassifierRecord {
  IcoreClassifierRecord({
    required this.memberNumber,
    required this.memberFirstName,
    required this.memberLastName,
    required this.classifierNumber,
    required this.eventDate,
    required this.eventDivision,
    required this.scoreRaw,
  });
  factory IcoreClassifierRecord.fromJson(Map<String, dynamic> json) => _$IcoreClassifierRecordFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreClassifierRecordToJson(this);

  String memberNumber;
  String memberFirstName;
  String memberLastName;
  String classifierNumber;
  String eventDate;
  DateTime? get parsedEventDate => programmerYmdFormat.tryParse(eventDate);
  String eventDivision;

  @JsonKey(name: 'scoreRAW')
  String scoreRaw;

  @JsonKey(name: "OpnClass")
  String? openClass;

  @JsonKey(name: "LtdClass")
  String? limitedClass;

  @JsonKey(name: "ClcClass")
  String? classicClass;

  @JsonKey(name: "L6Class")
  String? l6Class;

  @JsonKey(name: "B6Class")
  String? big6Class;

  double? get time => double.tryParse(scoreRaw);

  ClassifierScore toAnalystScore() {
    if(time == null || parsedEventDate == null) {
      _log.e("Invalid classifier record: $eventDate $scoreRaw");
    }
    var classString = switch(eventDivision) {
      "O" => openClass,
      "L" => limitedClass,
      "C" => classicClass,
      "L6" => l6Class,
      "B6" => big6Class,
      _ => "U",
    };
    return ClassifierScore(
      classifierCode: classifierNumber,
      classifierNumber: int.tryParse(classifierNumber.replaceFirst("CS-", "")),
      date: parsedEventDate!,
      division: eventDivision,
      classification: classString,
      firstName: memberFirstName,
      lastName: memberLastName,
      memberNumber: memberNumber,
      time: time!,
    );
  }
}

extension _MaybeParse on DateFormat {
  DateTime? tryParse(String input) {
    try {
      return parse(input);
    } catch (e) {
      return null;
    }
  }
}
