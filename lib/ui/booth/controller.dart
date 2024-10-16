/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:collection/collection.dart';
import 'package:mutex/mutex.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/ui/booth/global_card_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';

SSALogger _log = SSALogger("BoothController");

class BroadcastBoothController {
  BroadcastBoothModel model;
  final player = AudioPlayer();

  Future<void> loadFrom(BroadcastBoothModel newModel) async {
    await model.copyFrom(newModel, resetLastUpdateTime: true);
    
    // these will be rebuilt if the model is in timewarp
    // live ticker events will be cleared/recreated in refreshMatch
    model.tickerModel.timewarpTickerEvents.clear();
    
    await refreshMatch();
  }

  Timer? _refreshTimer;
  Future<bool> refreshMatch({bool manual = true}) async {
    var source = MatchSourceRegistry().getByCodeOrNull(model.matchSource);
    if(source == null) {
      return false;
    }
    var matchRes = await source.getMatchFromId(model.matchId, options: PSv2MatchFetchOptions(
      downloadScoreLogs: true,
    ));
    if(matchRes.isErr()) {
      _log.e("unable to refresh match: ${matchRes.unwrapErr()}");
      return false;
    }

    if(model.ready) {
      model.previousMatch = model.latestMatch;
    }
    model.latestMatch = matchRes.unwrap();
    model.tickerModel.lastUpdateTime = DateTime.now();
    model.tickerModel.liveTickerEvents.clear();

    // The ticker determines whether the UI updates, so make sure it's updated
    // before we send the UI update.
    model.tickerModel.update();
    model.update();

    if(model.tickerModel.updateBell) {
      player.play(AssetSource("audio/update-bell.mp3"));
    }

    _scheduleTickerReset();

    return true;
  }

  Timer? _tickerHasNewEventsTimer;
  Timer? _tickerResetTimer;
  void addTickerEvents(List<TickerEvent> events) {
    if(events.isEmpty) {
      return;
    }

    _tickerResetTimer?.cancel();
    _tickerResetTimer = null;

    if(model.inTimewarp && model.calculateTimewarpTickerEvents) {
      model.tickerModel.timewarpTickerEvents.addAll(events);
      _log.v("Timewarp ticker events: ${model.tickerModel.timewarpTickerEvents.length}");
    }
    else {
      model.tickerModel.liveTickerEvents.addAll(events);
      _log.v("Live ticker events: ${model.tickerModel.liveTickerEvents.length}");
    }
    
    if(_tickerHasNewEventsTimer == null) {
      _tickerHasNewEventsTimer = Timer(const Duration(milliseconds: 250), () {
        _log.i("Dispatching ticker update");
        _deduplicateTickerEvents();
        model.tickerModel.hasNewEvents = true;
        model.tickerModel.update();
        _tickerHasNewEventsTimer = null;
      });
    }
  }

  // Reset the ticker after a short delay, in case no events come in.
  // If events do come in, [addTickerEvents] will clear the timer.
  void _scheduleTickerReset() {
    _tickerResetTimer = Timer(const Duration(milliseconds: 500), () {
      _log.i("No-event ticker reset timer fired");
      model.tickerModel.hasNewEvents = true;
      model.tickerModel.update();
      model.update();
    });
  }

  void _deduplicateTickerEvents() {
    List<TickerEvent> eventList = [];
    if(model.inTimewarp) {
      eventList.addAll(model.tickerModel.timewarpTickerEvents);
    }
    else {
      eventList.addAll(model.tickerModel.liveTickerEvents);
    }

    Map<_TickerEventEquality, List<TickerEvent>> eventMap = {};
    for(var event in eventList) {
      var key = _TickerEventEquality(event);
      if(eventMap[key] == null) {
        eventMap[key] = [];
      }
      eventMap[key]!.add(event);
    }
    
    List<TickerEvent> outputEvents = [];
    for(var events in eventMap.values) {
      if(events.length == 1) {
        outputEvents.add(events[0]);
      }
      else {
        // Take the event with the most relevant competitors.
        outputEvents.add(events.reduce((a, b) =>
          a.relevantCompetitorCount > b.relevantCompetitorCount ? a : b
        ));
      }
    }

    outputEvents.sort((a, b) {
      if(a.priority != b.priority) {
        return b.priority.index.compareTo(a.priority.index);
      }
      return b.relevantCompetitorCount.compareTo(a.relevantCompetitorCount);
    });

    if(model.inTimewarp) {
      model.tickerModel.timewarpTickerEvents.clear();
      model.tickerModel.timewarpTickerEvents.addAll(outputEvents);
    }
    else {
      model.tickerModel.liveTickerEvents.clear();
      model.tickerModel.liveTickerEvents.addAll(outputEvents);
    }
  }
  
  void addScorecardRow() {
    model.scorecards.add([
      ScorecardModel(
        id: model.nextValidScorecardId,
        name: "New scorecard",
        scoreFilters: FilterSet(model.latestMatch.sport, empty: true)..mode = FilterMode.or,
        displayFilters: DisplayFilters(),
        parent: model,
      )
    ]);
    model.update();
  }

  void addScorecardColumn(List<ScorecardModel> scorecardRow) {
    var row = model.scorecards.firstWhereOrNull((row) => row == scorecardRow);
    if(row != null) {
      row.add(ScorecardModel(
        id: model.nextValidScorecardId,
        name: "New scorecard",
        scoreFilters: FilterSet(model.latestMatch.sport, empty: true)..mode = FilterMode.or,
        displayFilters: DisplayFilters(),
        parent: model,
      ));
    }
    else {
      _log.w("Could not find scorecard row to add column");
    }
    model.update();
  }

  void removeScorecard(ScorecardModel scorecard) {
    var row = model.scorecards.firstWhereOrNull((row) => row.contains(scorecard));
    if(row != null) {
      row.remove(scorecard);
      if(row.isEmpty) {
        model.scorecards.remove(row);
      }
    }
    else {
      _log.w("Could not find scorecard ${scorecard.name} to remove");
    }
    model.update();
  }

  void scorecardEdited(ScorecardModel original, ScorecardModel edited) {
    original.copyFrom(edited);
    model.update();
  }

  List<MoveDirection> validMoves(ScorecardModel scorecard) {
    var row = model.scorecards.firstWhereOrNull((row) => row.contains(scorecard));
    if(row == null) {
      _log.w("Could not find scorecard ${scorecard.name} to move");
      return [];
    }
    var index = model.scorecards.indexOf(row);
    var indexInRow = row.indexOf(scorecard);
    var moves = <MoveDirection>[];

    // For vertical movement, we only allow moves to existing rows.
    if(index < model.scorecards.length - 1) {
      moves.add(MoveDirection.down);
    }
    if(index > 0) {
      moves.add(MoveDirection.up);
    }

    // For side-to-side movement, we only allow swaps with existing scorecards.
    if(indexInRow > 0) {
      moves.add(MoveDirection.left);
    }
    if(indexInRow < row.length - 1) {
      moves.add(MoveDirection.right);
    }

    return moves;
  }

  void timewarp(DateTime? scoresBefore, {bool calculateTickerEvents = true}) {
    for(var row in model.scorecards) {
      for(var scorecard in row) {
        scorecard.scoresBefore = scoresBefore;
      }
    }
    model.timewarpScoresBefore = scoresBefore;
    model.tickerModel.timewarpTickerEvents.clear();
    model.calculateTimewarpTickerEvents = calculateTickerEvents;

    _scheduleTickerReset();
    model.update();
  }

  void globalScorecardSettingsEdited(GlobalScorecardSettingsModel settings) {
    model.globalScorecardSettings = settings;
    for(var row in model.scorecards) {
      for(var scorecard in row) {
        scorecard.copyGlobalSettingsFrom(settings);
      }
    }
    model.update();
  }

  bool moveScorecard(ScorecardModel scorecard, MoveDirection direction) {
    var row = model.scorecards.firstWhereOrNull((row) => row.contains(scorecard));
    if(row == null) {
      _log.w("Could not find scorecard ${scorecard.name} to move");
      return false;
    }
    var rowIndex = model.scorecards.indexOf(row);
    var colIndex = row.indexOf(scorecard);

    var result = false;

    // For vertical moves, insert into the row at our current index, or at the end.
    if(direction == MoveDirection.up) {
      if(rowIndex == 0) {
        return false;
      }
      row.remove(scorecard);

      var newRow = model.scorecards[rowIndex - 1];
      if(colIndex >= newRow.length) {
        newRow.add(scorecard);
      }
      else {
        newRow.insert(colIndex, scorecard);
      }
      result = true;
    }
    else if(direction == MoveDirection.down) {
      if(rowIndex == model.scorecards.length - 1) {
        return false;
      }
      row.remove(scorecard);

      var newRow = model.scorecards[rowIndex + 1];
      if(colIndex >= newRow.length) {
        newRow.add(scorecard);
      }
      else {
        newRow.insert(colIndex, scorecard);
      }
      result = true;
    }
    else if(direction == MoveDirection.left) {
      if(colIndex == 0) {
        return false;
      }
      
      row.remove(scorecard);
      var targetCol = colIndex - 1;
      if(targetCol >= row.length) {
        row.add(scorecard);
      }
      else {
        row.insert(targetCol, scorecard);
      }
      result = true;
    }
    else if(direction == MoveDirection.right) {
      if(colIndex == row.length - 1) {
        return false;
      }
      row.remove(scorecard);

      var targetCol = colIndex + 1;
      if(targetCol >= row.length) {
        row.add(scorecard);
      }
      else {
        row.insert(targetCol, scorecard);
      }
      result = true;
    }
    if(result) {
      model.update();
    }
    return result;
  }

  void tickerEdited(BoothTickerModel edited) {
    model.tickerModel.copyFrom(edited);
    model.update();
  }

  void toggleUpdatePause() {
    model.tickerModel.paused = !model.tickerModel.paused;
    model.tickerModel.update();
  }

  BroadcastBoothController(this.model) {
    // The refresh timer checks if the next update should have happened and refreshes if so.
    _refreshTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if(!model.tickerModel.paused && model.tickerModel.timeUntilUpdate.isNegative) {
        refreshMatch(manual: false);
      }
    });
  }

  void dispose() {
    _refreshTimer?.cancel();
  }
}

enum MoveDirection {
  up,
  down,
  left,
  right,
}

class _TickerEventEquality {
  TickerEvent t;

  _TickerEventEquality(this.t);

  // For our purposes, two ticker events are equal if they have the same
  // priority and reason, and concern the same competitor.
  bool operator ==(Object other) {
    if(other is _TickerEventEquality) {
      return t.priority == other.t.priority && t.reason == other.t.reason && t.relevantCompetitorEntryId == other.t.relevantCompetitorEntryId;
    }
    return false;
  }

  int get hashCode => Object.hashAll([t.priority, t.reason, t.relevantCompetitorEntryId]);

}