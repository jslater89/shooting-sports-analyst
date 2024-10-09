import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/booth/score_utils.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'ticker_criteria.g.dart';

@JsonSerializable()
class TickerEventCriterion {
  TickerEventType type;
  TickerPriority priority;

  TickerEventCriterion({
    required this.type,
    this.priority = TickerPriority.medium,
  });

  factory TickerEventCriterion.fromJson(Map<String, dynamic> json) => _$TickerEventCriterionFromJson(json);
  Map<String, dynamic> toJson() => _$TickerEventCriterionToJson(this);

  List<TickerEvent> checkEvents({
    required ScorecardModel scorecard,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required DateTime updateTime,
  }) {
    var events = <TickerEvent>[];
    for(var mapEntry in changes.entries) {
      var e = type.generateEvents(
        scorecard: scorecard,
        competitor: mapEntry.key,
        changes: changes,
        newScores: newScores,
        priority: priority,
        updateTime: updateTime,
      );
      events.addAll(e);
    }
    
    return events;
  }
}

@JsonSerializable(createFactory: false, createToJson: false)
sealed class TickerEventType {
  final String typeName;

  TickerEventType(this.typeName);
  factory TickerEventType.fromJson(Map<String, dynamic> json) => switch(json["typeName"]) {
    ExtremeScore.extremeScoreName => ExtremeScore.fromJson(json),
    MatchLeadChange.matchLeadChangeName => MatchLeadChange.fromJson(json),
    StageLeadChange.stageLeadChangeName => StageLeadChange.fromJson(json),
    _ => throw Exception("Unknown TickerEventType: ${json["typeName"]}"),
  };

  Map<String, dynamic> toJson();
  List<TickerEvent> generateEvents({
    required ScorecardModel scorecard,
    required MatchEntry competitor,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required TickerPriority priority,
    required DateTime updateTime,
  });

  String get uiLabel;

  bool get hasSettingsUI => false;
  Widget? buildSettingsUI(BuildContext context);
}

@JsonSerializable()
class ExtremeScore extends TickerEventType {
  static const extremeScoreName = "extremeScore";
  @JsonKey(includeToJson: true)
  final String typeName = extremeScoreName;

  @override
  String get uiLabel { 
    String amountLabel = "";
    if(aboveAverage && !belowAverage) {
      amountLabel = "+${changeThreshold}%";
    }
    else if(!aboveAverage && belowAverage) {
      amountLabel = "-${changeThreshold}%";
    }
    else {
      amountLabel = "±${changeThreshold}%";
    }
    return "Extreme ${extremeWord}score ($amountLabel)";
  }

  bool aboveAverage;
  bool belowAverage;

  /// The threshold to trigger a ticker event. This is not a ratio or multiplier,
  /// but rather a numerical figure: a threshold of 5% triggers if someone's average is 90%
  /// and the score is 84% or 96%, but not 86% or 94%.
  double changeThreshold;

  /// If set, the final score must be above this threshold to trigger a ticker event.
  double? minimumThreshold;

  /// If set, the average of previous scores must be above this threshold to trigger a ticker event.
  double? averageThreshold;

  ExtremeScore({
    required this.aboveAverage,
    required this.belowAverage,
    required this.changeThreshold,
    this.minimumThreshold,
    this.averageThreshold,
  }) : super(extremeScoreName);

  ExtremeScore.above({
    required this.changeThreshold,
    this.minimumThreshold,
    this.averageThreshold,
  }) : aboveAverage = true, belowAverage = false, super(extremeScoreName);

  ExtremeScore.below({
    required this.changeThreshold,
    this.minimumThreshold,
    this.averageThreshold,
  }) : aboveAverage = false, belowAverage = true, super(extremeScoreName);

  factory ExtremeScore.fromJson(Map<String, dynamic> json) => _$ExtremeScoreFromJson(json);
  Map<String, dynamic> toJson() => _$ExtremeScoreToJson(this);

  String get extremeWord {
    String extremeWord = "";
    if(aboveAverage && !belowAverage) {
      extremeWord = "high ";
    }
    else if(!aboveAverage && belowAverage) {
      extremeWord = "low ";
    }
    return extremeWord;
  }
  
  @override
  List<TickerEvent> generateEvents({
    required ScorecardModel scorecard,
    required MatchEntry competitor,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required TickerPriority priority,
    required DateTime updateTime,
  }) {
    var change = changes[competitor]!;
    List<TickerEvent> events = [];
    if(change.stageScoreChanges.isNotEmpty) {
      var previousPercentages = change.oldScore.stageScores.values.where((e) => !e.score.dnf).map((e) => e.percentage);
      if(previousPercentages.isEmpty) {
        return [];
      }
      var previousAverage = previousPercentages.average;
      if(averageThreshold != null && previousAverage < averageThreshold!) {
        return [];
      }

      for(var stageChange in change.stageScoreChanges.values) {
        var stagePercent = stageChange.newScore.percentage;

        if(minimumThreshold != null && stagePercent < minimumThreshold!) {
          continue;
        }

        var diff = (stagePercent - previousAverage);
        var diffSign = diff >= 0 ? "+" : "";
        bool above = stagePercent > previousAverage;
        if(diff.abs() >= changeThreshold) {
          if(above && aboveAverage || !above && belowAverage) {
            events.add(TickerEvent(
              generatedAt: updateTime,
              message: "${competitor.getName(suffixes: false).toUpperCase()} (${scorecard.name}) has a new extreme ${extremeWord}score (${stagePercent.toStringAsFixed(1)}%) on stage ${stageChange.newScore.stage.stageId} ($diffSign${diff.toStringAsFixed(2)}%)",
              reason: typeName,
              priority: priority,
            ));
          }
        }
      }
    }
    return events;
  }

  @override
  bool get hasSettingsUI => true;

  @override
  Widget? buildSettingsUI(BuildContext context) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: aboveAverage && !belowAverage ? "above" : 
                     belowAverage && !aboveAverage ? "below" : "both",
              items: [
                DropdownMenuItem(value: "above", child: Text("Above average")),
                DropdownMenuItem(value: "below", child: Text("Below average")),
                DropdownMenuItem(value: "both", child: Text("Both")),
              ],
              onChanged: (value) {
                setState(() {
                  switch (value) {
                    case "above":
                      aboveAverage = true;
                      belowAverage = false;
                      break;
                    case "below":
                      aboveAverage = false;
                      belowAverage = true;
                      break;
                    case "both":
                      aboveAverage = true;
                      belowAverage = true;
                      break;
                  }
                });
              },
              decoration: InputDecoration(labelText: "Trigger on score"),
            ),
            TextFormField(
              initialValue: changeThreshold.toString(),
              decoration: InputDecoration(labelText: "Change threshold (%)"),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Change threshold is required";
                }
                if (double.tryParse(value) == null || double.parse(value) <= 0) {
                  return "Must be a number greater than 0";
                }
                return null;
              },
              onChanged: (value) {
                if (double.tryParse(value) != null && double.parse(value) > 0) {
                  setState(() {
                    changeThreshold = double.parse(value);
                  });
                }
              },
            ),
            TextFormField(
              initialValue: minimumThreshold?.toString() ?? "",
              decoration: InputDecoration(labelText: "Minimum threshold (%)"),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (double.tryParse(value) == null || double.parse(value) < 0 || double.parse(value) > 100) {
                    return "Must be a number between 0 and 100";
                  }
                }
                return null;
              },
              onChanged: (value) {
                setState(() {
                  minimumThreshold = value.isEmpty ? null : double.tryParse(value);
                });
              },
            ),
            TextFormField(
              initialValue: averageThreshold?.toString() ?? "",
              decoration: InputDecoration(labelText: "Average threshold (%)"),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (double.tryParse(value) == null || double.parse(value) < 0 || double.parse(value) > 100) {
                    return "Must be a number between 0 and 100";
                  }
                }
                return null;
              },
              onChanged: (value) {
                setState(() {
                  averageThreshold = value.isEmpty ? null : double.tryParse(value);
                });
              },
            ),
          ],
        );
      },
    );
  }
}


@JsonSerializable()
class MatchLeadChange extends TickerEventType {
  static const matchLeadChangeName = "matchLeadChange";
  @JsonKey(includeToJson: true)
  final String typeName = matchLeadChangeName;
  MatchLeadChange() : super(matchLeadChangeName);

  factory MatchLeadChange.fromJson(Map<String, dynamic> json) => _$MatchLeadChangeFromJson(json);
  Map<String, dynamic> toJson() => _$MatchLeadChangeToJson(this);
  
  @override
  List<TickerEvent> generateEvents({
    required ScorecardModel scorecard,
    required MatchEntry competitor,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required TickerPriority priority,
    required DateTime updateTime,
  }) {
    var change = changes[competitor]!;

    // two possible cases: shooter gained the lead by dint of his own stage scores, or lost
    // the lead due to someone else placing ahead of him on other stages.
    if(change.newScore.place == 1 && change.oldScore.place != 1) {
      var secondPlace = newScores.entries.firstWhereOrNull((e) => e.value.place == 2);
      String message = "${competitor.getName(suffixes: false).toUpperCase()} (${scorecard.name}) now leads the match";
      if(secondPlace != null) {
        var secondCompetitor = secondPlace.key;
        var secondChange = secondPlace.value;
        var margin = change.newScore.points - secondChange.points;
        var ratioMargin = change.newScore.ratio - secondChange.ratio;
        message += " over ${secondCompetitor.getName(suffixes: false).toUpperCase()} by ${margin.toStringAsFixed(1)} points (${ratioMargin.asPercentage()}%)";
      }
      return [TickerEvent(
        generatedAt: updateTime,
        message: message,
        reason: typeName,
        priority: priority,
      )];
    }
    else if(change.newScore.place != 1 && change.oldScore.place == 1) {
      var firstPlace = newScores.entries.firstWhereOrNull((e) => e.value.place == 1);
      String message = "${competitor.getName(suffixes: false).toUpperCase()} (${scorecard.name}) lost the match lead";
      if(firstPlace != null) {
        var firstCompetitor = firstPlace.key;
        var firstChange = firstPlace.value;
        var margin = firstChange.points - change.newScore.points;
        var ratioMargin = firstChange.ratio - change.newScore.ratio;
        message += " to ${firstCompetitor.getName(suffixes: false).toUpperCase()} by ${margin.toStringAsFixed(1)} points (${ratioMargin.asPercentage()}%)";
      }
      return [TickerEvent(
        generatedAt: updateTime,
        message: message,
        reason: typeName,
        priority: priority,
      )];
    }
    return [];
  }
  
  @override
  String get uiLabel => "Match lead change";

  @override
  Widget? buildSettingsUI(BuildContext context) {
    return null;
  }
}

@JsonSerializable()
class StageLeadChange extends TickerEventType {
  static const stageLeadChangeName = "stageLeadChange";
  @JsonKey(includeToJson: true)
  final String typeName = stageLeadChangeName;

  StageLeadChange() : super(stageLeadChangeName);

  factory StageLeadChange.fromJson(Map<String, dynamic> json) => _$StageLeadChangeFromJson(json);
  Map<String, dynamic> toJson() => _$StageLeadChangeToJson(this);
  
  @override
  List<TickerEvent> generateEvents({
    required ScorecardModel scorecard,
    required MatchEntry competitor,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required TickerPriority priority,
    required DateTime updateTime,
  }) {
    List<TickerEvent> events = [];
    var change = changes[competitor]!;
    if(change.stageScoreChanges.isNotEmpty) {
      for(var stageChange in change.stageScoreChanges.values) {
        if(stageChange.newScore.place == 1 && stageChange.oldScore.place != 1) {
          var secondPlace = newScores.entries.firstWhereOrNull((e) => e.value.stageScores[stageChange.newScore.stage]?.place == 2);
          String message = "${competitor.getName(suffixes: false).toUpperCase()} (${scorecard.name}) now leads stage ${stageChange.newScore.stage.stageId}";
          if(secondPlace != null) {
            var secondCompetitor = secondPlace.key;
            var secondChange = secondPlace.value.stageScores[stageChange.newScore.stage]!;
            var margin = change.newScore.stageScores[stageChange.newScore.stage]!.points - secondChange.points;
            var ratioMargin = change.newScore.stageScores[stageChange.newScore.stage]!.ratio - secondChange.ratio;
            message += " over ${secondCompetitor.getName(suffixes: false).toUpperCase()} by ${margin.toStringAsFixed(1)} points (${ratioMargin.asPercentage()}%)";
          }
          events.add(TickerEvent(
            generatedAt: updateTime,
            message: message,
            reason: typeName,
            priority: priority,
          ));
        }
      }
    }
    return events;
  }
  
  @override
  String get uiLabel => "Stage lead change";

  @override
  Widget? buildSettingsUI(BuildContext context) {
    return null;
  }
}
