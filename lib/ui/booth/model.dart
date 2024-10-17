/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/booth/global_card_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/booth/score_utils.dart';
import 'package:shooting_sports_analyst/ui/booth/ticker_criteria.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'model.g.dart';

SSALogger _log = SSALogger("BoothModel");

@JsonSerializable(constructor: 'json')
class BroadcastBoothModel with ChangeNotifier {
  BoothTickerModel tickerModel = BoothTickerModel();

  @JsonKey(defaultValue: 1)
  int nextScorecardId = 1;

  /// Get the next available scorecard id.
  int get nextValidScorecardId {
    while(scorecards.any((row) => row.any((scorecard) => scorecard.id == nextScorecardId))) {
      nextScorecardId++;
    }
    return nextScorecardId;
  }

  String matchSource;
  String matchId;

  @JsonKey(includeFromJson: false, includeToJson: false)
  bool get inTimewarp => timewarpScoresBefore != null;

  DateTime? timewarpScoresBefore;

  @JsonKey(defaultValue: false)
  bool calculateTimewarpTickerEvents = false;

  /// The time of the last update to the ticker model.
  @JsonKey(fromJson: GlobalScorecardSettingsModel.maybeFromJson)
  GlobalScorecardSettingsModel globalScorecardSettings = GlobalScorecardSettingsModel();

  List<List<ScorecardModel>> scorecards = [];
  int get scorecardCount => scorecards.map((row) => row.length).reduce((a, b) => a + b);

  bool get ready => _readyCompleter.isCompleted;
  Future<void> get readyFuture => _readyCompleter.future;
  Completer<void> _readyCompleter = Completer<void>();

  BroadcastBoothModel({
    required ShootingMatch match,
  }) :
    _latestMatch = match,
    matchId = match.sourceIds.first,
    matchSource = match.sourceCode {
      _readyCompleter.complete();
    }
  
  BroadcastBoothModel.json(this.matchSource, this.matchId, this.globalScorecardSettings);

  @JsonKey(includeFromJson: false, includeToJson: false)
  ShootingMatch get latestMatch => _latestMatch;

  set latestMatch(ShootingMatch value) {
    _latestMatch = value;
    if (!_readyCompleter.isCompleted) {
      _log.i("Broadcast booth match loaded");
      _readyCompleter.complete();
    }
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  late ShootingMatch _latestMatch;

  @JsonKey(includeFromJson: false, includeToJson: false)
  ShootingMatch? previousMatch;

  void update() {
    notifyListeners();
  }

  factory BroadcastBoothModel.fromJson(Map<String, dynamic> json) {
    var model = _$BroadcastBoothModelFromJson(json);
    model.scorecards.forEach((row) {
      row.forEach((scorecard) {
        scorecard.parent = model;
        if(scorecard.id == 0) {
          scorecard.id = model.nextScorecardId++;
        }
      });
    });
    return model;
  }

  Map<String, dynamic> toJson() => _$BroadcastBoothModelToJson(this);

  Future<void> copyFrom(BroadcastBoothModel other, {bool resetLastUpdateTime = false}) async {
    _readyCompleter = Completer<void>();
    tickerModel.copyFrom(other.tickerModel);
    if(resetLastUpdateTime) {
      tickerModel.lastUpdateTime = DateTime.now();
    }
    matchSource = other.matchSource;
    matchId = other.matchId;
    scorecards = other.scorecards.map((row) => row.map((scorecard) => scorecard.copy()..parent = this).toList()).toList();
    timewarpScoresBefore = other.timewarpScoresBefore;
    calculateTimewarpTickerEvents = other.calculateTimewarpTickerEvents;
    globalScorecardSettings = other.globalScorecardSettings.copy();
  }
}

@JsonSerializable()
class BoothTickerModel with ChangeNotifier {
  static final defaultTickerCriteria = [
    TickerEventCriterion(
      type: MatchLeadChange(),
      priority: TickerPriority.high,
    ),
    TickerEventCriterion(
      type: Disqualification(),
      priority: TickerPriority.high,
    ),
    TickerEventCriterion(
      type: StageLeadChange(),
      priority: TickerPriority.medium,
    ),
    TickerEventCriterion(
      type: ExtremeScore.above(changeThreshold: 10.0, minimumThreshold: 90.0),
      priority: TickerPriority.low,
    ),
    TickerEventCriterion(
      type: ExtremeScore.below(changeThreshold: 20.0, averageThreshold: 75.0),
      priority: TickerPriority.low,
    ),
  ];

  int updateInterval = 300;

  /// Whether to play a notification sound when the match updates.
  bool updateBell;

  /// The volume of the update bell sound, between 0 and 1.
  double updateBellVolume;

  DateTime lastUpdateTime = DateTime.now();

  bool paused;

  /// Criteria for ticker events that apply to all scorecards.
  @JsonKey(defaultValue: [])
  List<TickerEventCriterion> globalTickerCriteria = [];

  int tickerSpeed;

  @JsonKey(includeFromJson: false, includeToJson: false)
  DateTime get nextUpdateTime => lastUpdateTime.add(Duration(seconds: updateInterval));

  @JsonKey(includeFromJson: false, includeToJson: false)
  Duration get timeSinceUpdate => DateTime.now().difference(lastUpdateTime);

  @JsonKey(includeFromJson: false, includeToJson: false)
  Duration get timeUntilUpdate => nextUpdateTime.difference(DateTime.now());

  /// Time warp ticker events are generated when scores are updated in a time warp, so
  /// we don't need to save them.
  @JsonKey(includeFromJson: false, includeToJson: false, defaultValue: [])
  List<TickerEvent> timewarpTickerEvents = [];

  /// Live ticker events are generated by the standard update process, and also don't
  /// need to be saved because time warp ticker events serve the same purpose.
  @JsonKey(includeFromJson: false, includeToJson: false, defaultValue: [])
  List<TickerEvent> liveTickerEvents = [];

  /// True if the ticker has new events, and the ticker row should be updated.
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool hasNewEvents = false;

  void update() {
    notifyListeners();
  }

  BoothTickerModel({
    this.updateInterval = 300,
    this.paused = false,
    DateTime? lastUpdateTime,
    this.tickerSpeed = 30,
    List<TickerEventCriterion>? globalTickerCriteria,
    this.updateBell = false,
    this.updateBellVolume = .75,
  }) : lastUpdateTime = lastUpdateTime ?? DateTime.now(), globalTickerCriteria = globalTickerCriteria ?? defaultTickerCriteria;

  factory BoothTickerModel.fromJson(Map<String, dynamic> json) => _$BoothTickerModelFromJson(json);

  Map<String, dynamic> toJson() => _$BoothTickerModelToJson(this);

  void copyFrom(BoothTickerModel other) {
    updateInterval = other.updateInterval;
    lastUpdateTime = other.lastUpdateTime;
    globalTickerCriteria = other.globalTickerCriteria;
    tickerSpeed = other.tickerSpeed;
    paused = other.paused;
    timewarpTickerEvents = other.timewarpTickerEvents;
    updateBell = other.updateBell;
    updateBellVolume = other.updateBellVolume;
    hasNewEvents = other.hasNewEvents;
  }

  BoothTickerModel copy() => BoothTickerModel.fromJson(toJson());
}

@JsonSerializable()
class TickerEvent {
  DateTime generatedAt;
  /// The message to be shown to the user.
  String message;
  /// The ticker event type name, e.g. [ExtremeScore.extremeScoreName]
  String reason;
  /// The entry ID of the competitor that is most relevant to this ticker
  /// event. Generally, the competitor whose score changed.
  int relevantCompetitorEntryId;
  /// The number of other competitors that are also relevant to this ticker
  /// event. When discarding duplicate ticker events for the same real event,
  /// the ticker event relating to the largest number of competitors is
  /// generally the one we want to show.
  int relevantCompetitorCount;
  /// The priority of the ticker event.
  TickerPriority priority;

  TickerEvent({
    required this.generatedAt,
    required this.message,
    required this.reason,
    required this.relevantCompetitorEntryId,
    this.relevantCompetitorCount = 1,
    this.priority = TickerPriority.medium,
  });

  factory TickerEvent.fromJson(Map<String, dynamic> json) => _$TickerEventFromJson(json);
  Map<String, dynamic> toJson() => _$TickerEventToJson(this);
}

enum TickerPriority {
  low,
  medium,
  high;

  String get uiLabel {
    switch(this) {
      case TickerPriority.low:
        return "Low";
      case TickerPriority.medium:
        return "Medium";
      case TickerPriority.high:
        return "High";
    }
  }

  TextStyle? get textStyle {
    final mediumPriorityStyle = TextStyle(fontWeight: FontWeight.w500);
    final highPriorityStyle = TextStyle(fontWeight: FontWeight.w600, color: const Color.fromARGB(255, 109, 7, 0));
    switch(this) {
      case TickerPriority.low:
        return null;
      case TickerPriority.medium:
        return mediumPriorityStyle;
      case TickerPriority.high:
        return highPriorityStyle;
    }
  }
}

@JsonSerializable(constructor: 'json')
class ScorecardModel {
  @JsonKey(includeFromJson: false, includeToJson: false)
  late BroadcastBoothModel parent;

  @JsonKey(defaultValue: 0)
  int id;
  String name;
  FilterSet scoreFilters;
  DisplayFilters displayFilters;

  // Time warp settings
  DateTime? scoresAfter;
  DateTime? scoresBefore;

  @JsonKey(defaultValue: MatchPredictionMode.none)
  MatchPredictionMode predictionMode;

  ScorecardModel({
    required this.id,
    required this.name,
    required this.scoreFilters,
    required this.displayFilters,
    required this.parent,
    this.scoresAfter,
    this.scoresBefore,
    this.predictionMode = MatchPredictionMode.none,
  });

  // parent is set by the parent model
  ScorecardModel.json(
    this.id,
    this.name,
    this.scoreFilters,
    this.displayFilters,
    {
      required this.predictionMode,
      this.scoresAfter,
      this.scoresBefore,
    }
  );

  ScorecardModel copy() {
    return ScorecardModel(
      id: id,
      name: name,
      scoreFilters: scoreFilters.copy(),
      displayFilters: displayFilters.copy(),
      parent: parent,
      scoresAfter: scoresAfter,
      scoresBefore: scoresBefore,
      predictionMode: predictionMode,
    );
  }

  void copyFrom(ScorecardModel other) {
    name = other.name;
    scoreFilters = other.scoreFilters.copy();
    displayFilters = other.displayFilters.copy();
    scoresAfter = other.scoresAfter;
    scoresBefore = other.scoresBefore;
    predictionMode = other.predictionMode;
  }

  void copyGlobalSettingsFrom(GlobalScorecardSettingsModel settings) {
    predictionMode = settings.predictionMode;
  }

  factory ScorecardModel.fromJson(Map<String, dynamic> json) => _$ScorecardModelFromJson(json);
  Map<String, dynamic> toJson() => _$ScorecardModelToJson(this);

  String toString() => name;
}

@JsonSerializable()
class DisplayFilters {
  FilterSet? filterSet;
  List<int>? entryIds;
  int? topN;

  DisplayFilters({
    this.filterSet,
    this.entryIds,
    this.topN,
  });

  DisplayFilters copy() {
    return DisplayFilters(
      filterSet: filterSet?.copy(),
      entryIds: entryIds?.toList(),
      topN: topN,
    );
  }

  List<MatchEntry> apply(ShootingMatch match) {
    if(filterSet == null && entryIds == null) {
      return [];
    }

    List<MatchEntry> entries;
    if(filterSet != null) {
      entries = match.applyFilterSet(filterSet!);
    } else {
      entries = [...match.shooters];
    }

    if(entryIds != null) {
      entries.retainWhere((e) => entryIds!.contains(e.entryId));
    }

    return entries;
  }

  bool get isEmpty => filterSet == null && entryIds == null && topN == null;

  factory DisplayFilters.fromJson(Map<String, dynamic> json) => _$DisplayFiltersFromJson(json);
  Map<String, dynamic> toJson() => _$DisplayFiltersToJson(this);
}