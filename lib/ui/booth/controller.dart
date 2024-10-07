/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';

SSALogger _log = SSALogger("BoothController");

class BroadcastBoothController {
  BroadcastBoothModel model;

  Timer? _refreshTimer;
  Future<bool> refreshMatch({bool manual = true}) async {
    var source = MatchSourceRegistry().getByCodeOrNull(model.matchSource);
    if(source == null) {
      return false;
    }
    var matchRes = await source.getMatchFromId(model.matchId);
    if(matchRes.isErr()) {
      _log.e("unable to refresh match: ${matchRes.unwrapErr()}");
      return false;
    }

    model.previousMatch = model.latestMatch;
    model.latestMatch = matchRes.unwrap();
    model.tickerModel.lastUpdateTime = DateTime.now();

    // The ticker determines whether the UI updates, so make sure it's updated
    // before we send the UI update.
    model.tickerModel.update();
    model.update();

    return true;
  }
  
  void addScorecardRow() {
    model.scorecards.add([
      ScorecardModel(
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