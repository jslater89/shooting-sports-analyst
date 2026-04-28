/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/source/psc/parse_utils.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'icore_scores.g.dart';

@JsonSerializable()
class IcoreScores {
  @JsonKey(name: "match_scores", defaultValue: [])
  List<IcoreStageScores> stageScores = [];

  IcoreScores();

  factory IcoreScores.fromJson(Map<String, dynamic> json) => _$IcoreScoresFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreScoresToJson(this);
}

@JsonSerializable()
class IcoreStageScores {
  @JsonKey(name: "stage_number", fromJson: jsonStringOrNumToInt)
  int stageNumber = 0;

  @JsonKey(name: "stage_uuid")
  String stageId = "";

  @JsonKey(name: "stage_stagescores", defaultValue: [])
  List<IcoreScore> scores = [];

  IcoreStageScores();

  factory IcoreStageScores.fromJson(Map<String, dynamic> json) => _$IcoreStageScoresFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreStageScoresToJson(this);
}

@JsonSerializable()
class IcoreScore {
  @JsonKey(name: "shtr")
  String shooterId = "";
  @JsonKey(name: "poph", defaultValue: 0)
  int steelHits = 0;
  @JsonKey(name: "popm", defaultValue: 0)
  int steelMisses = 0;
  @JsonKey(name: "str")
  List<double> stringTimes = [];
  @JsonKey(name: "ts", defaultValue: [])
  List<int> encodedTargetHits = [];
  @JsonKey(name: "aprv", defaultValue: false)
  bool approved = false;
  @JsonKey(name: "dnf", defaultValue: false)
  bool stageDnf = false;
  @JsonKey(name: "mod", fromJson: parseUtcDate)
  DateTime? modified;
  @JsonKey(name: "dqs", defaultValue: [])
  List<String> dqReasons = [];
  @JsonKey(name: "pens", defaultValue: [])
  List<int> penalties = [];
  @JsonKey(name: "bons", defaultValue: [])
  List<int> bonuses = [];

  double get totalTime => stringTimes.sum;

  /// Decode target hits encoded ICORE-style.
  ///
  /// Returns a list of maps of hits on target.
  ///
  /// [nonstandardXValues] is a map of target index to X-ring multiplier. This
  /// is used for ICORE stages that have more than one nonstandard X-ring multiplier.
  List<Map<ScoringEvent, int>> decodeTargetHits(PowerFactor pf, Map<int, ScoringEvent> nonstandardXValues) {
    List<Map<ScoringEvent, int>> events = [];

    // Events in order of ascending power in the encoding
    // A = 16^0, B = 16^1, C = 16^2, X = 16^3, NS = 16^4, M = 16^5, NPM = 16^6
    var xEvent = pf.targetEvents.lookupByName("X");
    List<ScoringEvent?> orderedEvents = [
      pf.targetEvents.lookupByName("A"),
      pf.targetEvents.lookupByName("B"),
      pf.targetEvents.lookupByName("C"),
      xEvent,
      pf.targetEvents.lookupByName("NS"),
      pf.targetEvents.lookupByName("M"),
      pf.targetEvents.lookupByName("NPM"),
    ];

    for(var (i, encodedTarget) in encodedTargetHits.indexed) {
      Map<ScoringEvent, int> targetHits = {};

      for(int power = 6; power >= 0; power--) {
        var event = orderedEvents[power];

        int currentDivisor = pow(16, power).round();
        if(event != null) {
          if(xEvent != null && event.name == icoreX.name && event.variableValue && nonstandardXValues.containsKey(i)) {
            event = nonstandardXValues[i]!;
          }

          int hits = encodedTarget ~/ currentDivisor;
          targetHits.incrementBy(event, hits);
        }
        encodedTarget = encodedTarget % currentDivisor;
      }

      events.add(targetHits);
    }

    return events;
  }

  static Map<ScoringEvent, int> flattenTargetScores(List<Map<ScoringEvent, int>> targetScores) {
    Map<ScoringEvent, int> flat = {};
    for(var target in targetScores) {
      for(var key in target.keys) {
        flat.incrementBy(key, target[key]!);
      }
    }

    return flat;
  }

  IcoreScore();

  factory IcoreScore.fromJson(Map<String, dynamic> json) => _$IcoreScoreFromJson(json);
  Map<String, dynamic> toJson() => _$IcoreScoreToJson(this);
}
