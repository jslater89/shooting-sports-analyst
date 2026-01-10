/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';

/// A list of wagers for a prediction game, match prep, or prediction game player.
///
/// Requires a [WagerListModel] to be provided.
class WagerList extends StatelessWidget {
  const WagerList({super.key});

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<WagerListModel>(context);
    bool canManage = model.player != null;
    bool showPlayer = model.player == null;
    bool showMatchName = model.matchPrep == null;

    var listView = ListView.builder(
      itemCount: model.wagers.length,
      itemBuilder: (context, index) {
        var wager = model.wagers[index];
        var matchPrepName = wager.matchPrep.value!.futureMatch.value!.eventName;
        var playerName = wager.user.value!.nickname ?? wager.user.value!.serverUser.value?.username ?? "(no username)";
        var hydratedWager = wager.hydrate();
        var prediction = "${hydratedWager.descriptiveString} (${wager.ratingGroup.value?.name ?? "unknown group"})";
        var tooltipString = hydratedWager.parlayDescription;

        bool showTooltip = wager.isParlay;

        Widget descriptionText = Text(prediction);
        if(showTooltip) {
          descriptionText = Tooltip(
            message: tooltipString,
            child: descriptionText,
          );
        }

        var moneylineOdds = hydratedWager.probability.moneylineOdds;
        var stake = hydratedWager.amount;
        var payout = hydratedWager.payout;

        var subtitleText = "${moneylineOdds} - ${stake.toStringAsFixed(2)} → ${payout.toStringAsFixed(2)}";
        if(showMatchName) {
          var limitedPrepName = matchPrepName;
          if(matchPrepName.length > 50) {
            limitedPrepName = "${matchPrepName.substring(0, 50)}...";
          }
          subtitleText = "$limitedPrepName | $subtitleText";
        }
        if(showPlayer) {
          subtitleText = "$playerName | $subtitleText";
        }

        return ListTile(
          title: descriptionText,
          subtitle: Text(subtitleText),
          trailing: !canManage ? null : IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              model.removeWager(wager);
            },
          ),
        );
      },
    );

    if(!canManage) {
      return listView;
    }
    else {
      return Column(
        children: [
          Expanded(child: listView),
        ],
      );
    }
  }
}

/// A model for a [WagerList].
///
/// If [matchPrep] is provided, the wagers will be filtered to only include wagers for that match prep.
///
/// If [player] is provided, the wagers will be filtered to only include wagers for that player, and
/// the widget will also include UI to manage the player's wagers.
class WagerListModel extends ChangeNotifier {
  WagerListModel({required this.managerModel, PredictionGamePlayer? player, MatchPrep? matchPrep, this.openOnly = false}) {
    playerId = player?.id;
    matchPrepId = matchPrep?.id;
    loadWagers();
    managerModel.addListener(loadWagers);
  }

  @override
  void dispose() {
    managerModel.removeListener(loadWagers);
    super.dispose();
  }

  PredictionGameManagerModel managerModel;
  int? playerId;
  int? matchPrepId;
  bool openOnly;

  PredictionGamePlayer? get player => playerId != null ? managerModel.getPlayerById(playerId!) : null;
  MatchPrep? get matchPrep => matchPrepId != null ? managerModel.getMatchPrepById(matchPrepId!) : null;

  List<DbWager> wagers = [];

  Future<void> loadWagers() async {
    if(player != null) {
      var newWagers = await player!.wagers.filter().findAll();
      if(matchPrep != null) {
        newWagers = newWagers.where((wager) => wager.matchPrep.value!.id == matchPrep!.id).toList();
      }
      if(openOnly) {
        newWagers = newWagers.where((wager) => wager.status == DbWagerStatus.pending).toList();
      }
      _setWagers(newWagers);
    }
    else {
      var gameWagers = managerModel.manager.predictionGame.wagers.toList();
      if(matchPrep != null) {
        gameWagers = gameWagers.where((wager) => wager.matchPrep.value!.id == matchPrep!.id).toList();
      }
      if(openOnly) {
        gameWagers = gameWagers.where((wager) => wager.status == DbWagerStatus.pending).toList();
      }
      _setWagers(gameWagers);
    }
  }

  void _setWagers(List<DbWager> wagers) {
    this.wagers = wagers;
    notifyListeners();
  }

  Future<void> addWager(DbWager wager) async {
    if(wager.user.value == null) {
      throw ArgumentError("Wager has no user");
    }
    await managerModel.addWager(wager);
    notifyListeners();
  }

  Future<void> removeWager(DbWager wager) async {
    await managerModel.removeWager(wager);
    notifyListeners();
  }

  Future<void> setMatchPrep(MatchPrep? matchPrep) async {
    matchPrepId = matchPrep?.id;
    loadWagers();
    notifyListeners();
  }

  Future<void> setPlayer(PredictionGamePlayer? player) async {
    playerId = player?.id;
    loadWagers();
    notifyListeners();
  }
}