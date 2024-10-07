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