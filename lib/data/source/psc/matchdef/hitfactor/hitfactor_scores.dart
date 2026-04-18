
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/source/psc/parse_utils.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'hitfactor_scores.g.dart';

@JsonSerializable()
class HitFactorScores {
  @JsonKey(name: "match_scores", defaultValue: [])
  List<HitFactorStageScores> stageScores = [];

  HitFactorScores();
  factory HitFactorScores.fromJson(Map<String, dynamic> json) => _$HitFactorScoresFromJson(json);
  Map<String, dynamic> toJson() => _$HitFactorScoresToJson(this);
}

@JsonSerializable()
class HitFactorStageScores {
  @JsonKey(name: "stage_number", fromJson: jsonStringOrNumToInt)
  int stageNumber = 0;
  @JsonKey(name: "stage_uuid")
  String stageId = "";
  @JsonKey(name: "stage_stagescores", defaultValue: [])
  List<HitFactorScore> scores = [];

  HitFactorStageScores();
  factory HitFactorStageScores.fromJson(Map<String, dynamic> json) => _$HitFactorStageScoresFromJson(json);
  Map<String, dynamic> toJson() => _$HitFactorStageScoresToJson(this);
}

@JsonSerializable()
class HitFactorScore {
  @JsonKey(name: "shtr")
  String shooterId = "";
  @JsonKey(name: "poph", defaultValue: 0)
  int steelHits = 0;
  @JsonKey(name: "popm", defaultValue: 0)
  int steelMisses = 0;
  @JsonKey(name: "popns", defaultValue: 0)
  int steelNoShoots = 0;
  @JsonKey(name: "rawpts", defaultValue: 0)
  int rawPoints = 0;
  @JsonKey(name: "str")
  List<double> stringTimes = [];
  @JsonKey(name: "ts", defaultValue: [])
  List<int> encodedTargetHits = [];
  @JsonKey(name: "proc", defaultValue: 0)
  int procedurals = 0;
  @JsonKey(name: "ots", defaultValue: 0)
  int overtimeShots = 0;
  @JsonKey(name: "aprv", defaultValue: false)
  bool approved = false;
  @JsonKey(name: "dnf", defaultValue: false)
  bool stageDnf = false;
  @JsonKey(name: "mod", fromJson: parseUtcDate)
  DateTime? modified;
  @JsonKey(name: "dqs", defaultValue: [])
  List<String> dqReasons = [];

  double get totalTime => stringTimes.sum;

  /// Decode target hits encoded USPSA-style.
  ///
  /// [events] is target hits in increasing order of encoding (A = 1, C = 256,
  /// etc.)
  ///
  /// Returns a list of maps of hits on target.
  List<Map<ScoringEvent, int>> decodeTargetHits(PowerFactor pf) {
    List<Map<ScoringEvent, int>> events = [];

    List<ScoringEvent?> orderedEvents = [
      pf.targetEvents.lookupByName("A"),
      pf.targetEvents.lookupByName("B"),
      pf.targetEvents.lookupByName("C"),
      pf.targetEvents.lookupByName("D"),
      pf.targetEvents.lookupByName("NS"),
      pf.targetEvents.lookupByName("M"),
      pf.targetEvents.lookupByName("NPM"),
    ];

    for(var encodedTarget in encodedTargetHits) {
      Map<ScoringEvent, int> targetHits = {};

      for(int power = 6; power >= 0; power--) {
        var event = orderedEvents[power];

        if(event != null) {
          int hits = hitsInPosition(encodedTarget, power + 1);
          targetHits.incrementBy(event, hits);
        }
      }

      events.add(targetHits);
    }

    return events;
  }

  static int hitsInPosition(int encodedTarget, int position) {
    // Each hit is represented by an 8-bit number, split across the
    // first 28 bits and the last 28 bits of the encoded target, with
    // the low order bits in each position's slot in the first 28 bits,
    // and the high order bits in each position's slot in the last 28 bits.
    return switch(position) {
      1 => (((15 & encodedTarget) >>> 0) + ((encodedTarget & 64424509440) >>> 28)),
      2 => (((240 & encodedTarget) >>> 4) + ((encodedTarget & 1030792151040) >>> 32)),
      3 => (((3840 & encodedTarget) >>> 8) + ((encodedTarget & 16492674416640) >>> 36)),
      4 => (((61440 & encodedTarget) >>> 12) + ((encodedTarget & 263882790666240) >>> 40)),
      5 => (((983040 & encodedTarget) >>> 16) + ((encodedTarget & 4222124650659840) >>> 44)),
      6 => (((15728640 & encodedTarget) >>> 20) + ((encodedTarget & 67553994410557440) >>> 48)),
      7 => (((251658240 & encodedTarget) >>> 24) + ((encodedTarget & 1080863910568919040) >>> 52)),
      _ => throw Exception("Invalid position: $position")
    };
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

  HitFactorScore();

  factory HitFactorScore.fromJson(Map<String, dynamic> json) => _$HitFactorScoreFromJson(json);
  Map<String, dynamic> toJson() => _$HitFactorScoreToJson(this);
}
