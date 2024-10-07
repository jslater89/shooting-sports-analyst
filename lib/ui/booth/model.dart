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
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';

part 'model.g.dart';

SSALogger _log = SSALogger("BoothModel");

@JsonSerializable(constructor: 'json')
class BroadcastBoothModel with ChangeNotifier {
  BoothTickerModel tickerModel = BoothTickerModel();

  String matchSource;
  String matchId;

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
  
  BroadcastBoothModel.json(this.matchSource, this.matchId);

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
  }
}

@JsonSerializable()
class BoothTickerModel with ChangeNotifier {
  int updateInterval = 300;
  
  DateTime lastUpdateTime = DateTime.now();

  @JsonKey(includeFromJson: false, includeToJson: false)
  DateTime get nextUpdateTime => lastUpdateTime.add(Duration(seconds: updateInterval));

  @JsonKey(includeFromJson: false, includeToJson: false)
  Duration get timeSinceUpdate => DateTime.now().difference(lastUpdateTime);

  @JsonKey(includeFromJson: false, includeToJson: false)
  Duration get timeUntilUpdate => nextUpdateTime.difference(DateTime.now());

  void update(DateTime refreshTime) {
    lastUpdateTime = refreshTime;
    notifyListeners();
  }

  BoothTickerModel({
    this.updateInterval = 300,
    DateTime? lastUpdateTime,
  }) : lastUpdateTime = lastUpdateTime ?? DateTime.now();

  factory BoothTickerModel.fromJson(Map<String, dynamic> json) => _$BoothTickerModelFromJson(json);

  Map<String, dynamic> toJson() => _$BoothTickerModelToJson(this);

  void copyFrom(BoothTickerModel other) {
    updateInterval = other.updateInterval;
    lastUpdateTime = other.lastUpdateTime;
  }
}

@JsonSerializable(constructor: 'json')
class ScorecardModel {
  @JsonKey(includeFromJson: false, includeToJson: false)
  late BroadcastBoothModel parent;

  String name;
  FilterSet scoreFilters;
  DisplayFilters displayFilters;

  ScorecardModel({
    required this.name,
    required this.scoreFilters,
    required this.displayFilters,
    required this.parent,
  });

  // parent is set by the parent model
  ScorecardModel.json(this.name, this.scoreFilters, this.displayFilters);

  ScorecardModel copy() {
    return ScorecardModel(
      name: name,
      scoreFilters: scoreFilters.copy(),
      displayFilters: displayFilters.copy(),
      parent: parent,
    );
  }

  void copyFrom(ScorecardModel other) {
    name = other.name;
    scoreFilters = other.scoreFilters.copy();
    displayFilters = other.displayFilters.copy();
  }

  factory ScorecardModel.fromJson(Map<String, dynamic> json) => _$ScorecardModelFromJson(json);
  Map<String, dynamic> toJson() => _$ScorecardModelToJson(this);

  String toString() => name;
}

@JsonSerializable()
class DisplayFilters {
  FilterSet? filterSet;
  List<int>? entryIds;

  DisplayFilters({
    this.filterSet,
    this.entryIds,
  });

  DisplayFilters copy() {
    return DisplayFilters(
      filterSet: filterSet?.copy(),
      entryIds: entryIds?.toList(),
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

  factory DisplayFilters.fromJson(Map<String, dynamic> json) => _$DisplayFiltersFromJson(json);
  Map<String, dynamic> toJson() => _$DisplayFiltersToJson(this);
}