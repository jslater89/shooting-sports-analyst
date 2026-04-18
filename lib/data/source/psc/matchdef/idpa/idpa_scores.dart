import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/source/psc/parse_utils.dart';

part 'idpa_scores.g.dart';

@JsonSerializable()
class IdpaLikeScores {
  @JsonKey(name: "match_scores", defaultValue: [])
  List<IdpaStageScores> stageScores = [];

  IdpaLikeScores({required this.stageScores});

  factory IdpaLikeScores.fromJson(Map<String, dynamic> json) => _$IdpaLikeScoresFromJson(json);
  Map<String, dynamic> toJson() => _$IdpaLikeScoresToJson(this);
}

@JsonSerializable()
class IdpaStageScores {
  @JsonKey(name: "stage_number", fromJson: jsonStringOrNumToInt)
  int stageNumber = 0;
  @JsonKey(name: "stage_uuid")
  String stageId = "";
  @JsonKey(name: "stage_stagescores", defaultValue: [])
  List<IdpaScore> scores = [];

  IdpaStageScores();

  factory IdpaStageScores.fromJson(Map<String, dynamic> json) => _$IdpaStageScoresFromJson(json);
  Map<String, dynamic> toJson() => _$IdpaStageScoresToJson(this);
}

@JsonSerializable()
class IdpaScore {
  @JsonKey(name: "shtr")
  String shooterId = "";

  @JsonKey(name: "tpts", defaultValue: [])
  List<int> targetPointsDown = [];

  @JsonKey(name: "poph")
  int steelHits = 0;
  @JsonKey(name: "popm")
  int steelMisses = 0;

  @JsonKey(name: "str", defaultValue: [])
  List<double> stringTimes = [];

  @JsonKey(name: "pens", defaultValue: [])
  List<int> penalties = [];

  @JsonKey(name: "mod", fromJson: parseUtcDate)
  DateTime? modified;
  @JsonKey(name: "dqs", defaultValue: [])
  List<String> dqReasons = [];

  double get totalTime => stringTimes.sum;

  int get totalPointsDown {
    int total = 0;
    // where e > 0: for some unfathomable reason, PractiScore has negative
    // numbers in some IDPA match results
    total += targetPointsDown.where((e) => e > 0).sum;
    total += steelMisses * 5;
    return total;
  }

  IdpaScore();

  factory IdpaScore.fromJson(Map<String, dynamic> json) => _$IdpaScoreFromJson(json);
  Map<String, dynamic> toJson() => _$IdpaScoreToJson(this);
}