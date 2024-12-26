// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/html_or/fake_html.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/booth/score_utils.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_model.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'ticker_criteria.g.dart';

SSALogger _log = SSALogger("TickerCriteria");

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
    required int displayedCompetitorCount,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required DateTime updateTime,
  }) {
    var events = <TickerEvent>[];
    for(var mapEntry in changes.entries) {
      var e = type.generateEvents(
        scorecard: scorecard,
        competitor: mapEntry.key,
        displayedCompetitors: displayedCompetitorCount,
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
    Disqualification.disqualificationName => Disqualification.fromJson(json),
    NewShooterScore.newShooterScoreName => NewShooterScore.fromJson(json),
    _ => throw Exception("Unknown TickerEventType: ${json["typeName"]}"),
  };

  Map<String, dynamic> toJson();
  List<TickerEvent> generateEvents({
    required ScorecardModel scorecard,
    required MatchEntry competitor,
    required int displayedCompetitors,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required TickerPriority priority,
    required DateTime updateTime,
  });

  String get uiLabel;

  bool get hasSettingsUI => false;
  Widget? buildSettingsUI(BuildContext context, BroadcastBoothModel boothModel);
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
    required int displayedCompetitors,
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
              relevantCompetitorEntryId: competitor.entryId,
              relevantCompetitorEntryUuid: competitor.sourceId,
              relevantCompetitorCount: newScores.length,
              displayedCompetitorCount: displayedCompetitors,
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
  Widget? buildSettingsUI(BuildContext context, BroadcastBoothModel boothModel) {
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
    required int displayedCompetitors,
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
        relevantCompetitorEntryId: competitor.entryId,
        relevantCompetitorEntryUuid: competitor.sourceId,
        generatedAt: updateTime,
        relevantCompetitorCount: newScores.length,
        displayedCompetitorCount: displayedCompetitors,
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
        relevantCompetitorEntryId: competitor.entryId,
        relevantCompetitorEntryUuid: competitor.sourceId,
        relevantCompetitorCount: newScores.length,
        displayedCompetitorCount: displayedCompetitors,
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
  Widget? buildSettingsUI(BuildContext context, BroadcastBoothModel boothModel) {
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
    required int displayedCompetitors,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required TickerPriority priority,
    required DateTime updateTime,
  }) {
    List<TickerEvent> events = [];
    var change = changes[competitor]!;
    if(change.stageScoreChanges.isNotEmpty) {
      for(var stageChange in change.stageScoreChanges.values) {
        // If the old score is null, this is the first score for this stage, so don't show a 'gained the lead'
        // message.
        if(stageChange.newScore.place == 1 && (stageChange.oldScore?.place ?? 1) != 1) {
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
            relevantCompetitorEntryId: competitor.entryId,
            relevantCompetitorEntryUuid: competitor.sourceId,
            relevantCompetitorCount: newScores.length,
            displayedCompetitorCount: displayedCompetitors,
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
  Widget? buildSettingsUI(BuildContext context, BroadcastBoothModel boothModel) {
    return null;
  }
}

@JsonSerializable()
class Disqualification extends TickerEventType {
  static const disqualificationName = "disqualification";
  @JsonKey(includeToJson: true)
  final String typeName = disqualificationName;

  Disqualification() : super(disqualificationName);

  factory Disqualification.fromJson(Map<String, dynamic> json) => _$DisqualificationFromJson(json);
  Map<String, dynamic> toJson() => _$DisqualificationToJson(this);

  @override
  List<TickerEvent> generateEvents({
    required ScorecardModel scorecard,
    required MatchEntry competitor,
    required int displayedCompetitors,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required TickerPriority priority,
    required DateTime updateTime,
  }) {
    var change = changes[competitor]!;

    // DQs can be reported in two ways: either the shooter's match entry has a DQ marker in
    // the new score but not the old one, which we might see if watching a match live, or
    // the shooter has a DQ in one of the new raw scores but none of the old ones, which we
    // are more likely to see in time warp.
    if(
      !change.oldScore.shooter.dq && change.newScore.shooter.dq
      || !change.oldScore.stageScores.values.any((e) => e.score.dq) && change.newScore.stageScores.values.any((e) => e.score.dq)
    ) {
      var newStage = change.newScore.stageScores.keys.firstWhereOrNull((e) =>
        change.newScore.stageScores[e]!.score.dq
      );

      var message = "${competitor.name.toUpperCase()} (${scorecard.name}) was disqualified";
      if(newStage != null) {
        message += " on stage ${newStage.stageId}";
      }
      return [TickerEvent(
        relevantCompetitorEntryId: competitor.entryId,
        relevantCompetitorEntryUuid: competitor.sourceId,
        relevantCompetitorCount: newScores.length,
        displayedCompetitorCount: displayedCompetitors,
        generatedAt: updateTime,
        message: message,
        reason: typeName,
        priority: priority,
      )];
    }
    return [];
  }

  @override
  String get uiLabel => "Disqualification";

  @override
  Widget? buildSettingsUI(BuildContext context, BroadcastBoothModel boothModel) {
    return null;
  }
}

@JsonSerializable()
class NewShooterScore extends TickerEventType {
  static const newShooterScoreName = "newShooterScore";
  @JsonKey(includeToJson: true)
  final String typeName = newShooterScoreName;

  NewShooterScore({required this.shooterUuid, required this.shooterName}) : super(newShooterScoreName);

  String shooterUuid;
  String shooterName;

  factory NewShooterScore.fromJson(Map<String, dynamic> json) => _$NewShooterScoreFromJson(json);
  Map<String, dynamic> toJson() => _$NewShooterScoreToJson(this);

  @override
  List<TickerEvent> generateEvents({
    required ScorecardModel scorecard,
    required MatchEntry competitor,
    required int displayedCompetitors,
    required Map<MatchEntry, MatchScoreChange> changes,
    required Map<MatchEntry, RelativeMatchScore> newScores,
    required TickerPriority priority,
    required DateTime updateTime,
  }) {
    var change = changes[competitor]!;
    var stageChanges = change.stageScoreChanges;

    var scoreMessage = "";
    if(stageChanges.isNotEmpty) {
      if(stageChanges.length == 1) {
        var stageChange = stageChanges.values.first;
        scoreMessage = " (${stageChange.newScore.ratio.asPercentage()}%) on stage ${stageChange.newScore.stage.stageId}";

        var oldStageRatios = change.oldScore.stageScores.values.where((e) => !e.score.dnf).map((e) => e.ratio);
        if(oldStageRatios.isNotEmpty) {
          var average = oldStageRatios.average;
          var difference = stageChange.newScore.ratio - average;
          var differenceChar = difference > 0 ? "+" : "";
          scoreMessage += " (${differenceChar}${difference.asPercentage()}%)";
        }
      }
      else {
        scoreMessage = " on multiple stages";
      }
    }

    if(competitor.sourceId != null) {
      if(competitor.sourceId == shooterUuid) {
        return [TickerEvent(
          relevantCompetitorEntryId: competitor.entryId,
          relevantCompetitorEntryUuid: competitor.sourceId,
          relevantCompetitorCount: newScores.length,
          displayedCompetitorCount: displayedCompetitors,
          generatedAt: updateTime,
          message: "${shooterName.toUpperCase()} (${scorecard.name}) has a new score${scoreMessage}",
          reason: typeName,
          priority: priority,
        )];
      }
    }
    else if("${competitor.entryId}" == shooterUuid) {
      return [];
    }
    
    // no change found
    return [];
  }

  @override
  bool get hasSettingsUI => true;

  @override
  Widget? buildSettingsUI(BuildContext context, BroadcastBoothModel boothModel) {
    var match = boothModel.latestMatch;
    var textController = TextEditingController(text: shooterName);
    return StatefulBuilder(
      builder: (context, setState) {
        return TypeAheadField<MatchEntry>(
          textFieldConfiguration: TextFieldConfiguration(
            controller: textController,
            decoration: InputDecoration(labelText: "Competitor"),
          ),
          suggestionsCallback: (pattern) async {
            return match.shooters.where((e) => e.name.toLowerCase().contains(pattern.toLowerCase()));
          },
          itemBuilder: (context, MatchEntry entry) => ListTile(
            title: Text(entry.name)
          ),
          onSuggestionSelected: (MatchEntry entry) {
            setState(() {
              shooterUuid = entry.sourceId ?? "${entry.entryId}";
              shooterName = entry.name;
            });
            textController.text = entry.name;
          },
        );
      }
    );
  }
  
  @override
  String get uiLabel => "$shooterName scores";
}
