/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/widget/prediction_game_house_stats.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/widget/prediction_game_match_list.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/widget/prediction_game_player_list.dart';

// ignore: unused_element
var _log = SSALogger("PredictionGameManager");

class PredictionGameManagerUI extends StatelessWidget {
  const PredictionGameManagerUI({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PredictionGameManagerModel>(
      builder: (context, model, child) {
        return Column(
          children: [
            PredictionGameHouseStats(),
            Divider(),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: PredictionGamePlayerList()),
                  VerticalDivider(),
                  Expanded(child: PredictionGameMatchList()),
                ],
              ),
            ),
          ],
        );
      }
    );
  }
}

class PredictionGameManagerModel extends ChangeNotifier {
  PredictionGameManagerModel({required PredictionGame predictionGame}) {
    manager = PredictionGameManager(predictionGame: predictionGame);
    loadPredictionGame();
  }

  PredictionGame get predictionGame => manager.predictionGame;
  late PredictionGameManager manager;

  Future<List<PredictionGameTransaction>> getTransactions({
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) async {
    return manager.getTransactions(matchPrep: matchPrep, player: player);
  }

  List<PredictionGameTransaction> getTransactionsSync({
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) {
    return manager.getTransactionsSync(matchPrep: matchPrep, player: player);
  }

  Future<List<DbWager>> getWagers({
    bool openOnly = false,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) async {
    return manager.getWagers(openOnly: openOnly, matchPrep: matchPrep, player: player);
  }

  List<DbWager> getWagersSync({
    bool openOnly = false,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) {
    return manager.getWagersSync(openOnly: openOnly, matchPrep: matchPrep, player: player);
  }

  Future<void> addMatchPrep(MatchPrep matchPrep) async {
    await manager.addMatchPrep(matchPrep);
    notifyListeners();
  }

  // Future<void> processWagersForMatch(MatchPrep matchPrep) async {
  //   await manager.processWagersForMatch(matchPrep);
  //   notifyListeners();
  // }

  Future<void> savePlayer(PredictionGamePlayer player, {List<PredictionGameTransaction>? newTransactions}) async {
    await manager.savePlayer(player, newTransactions: newTransactions);
    notifyListeners();
  }

  void savePlayerSync(PredictionGamePlayer player) {
    manager.savePlayerSync(player);
    notifyListeners();
  }

  Future<void> deletePlayer(PredictionGamePlayer player) async {
    await manager.deletePlayer(player);
    notifyListeners();
  }

  void deletePlayerSync(PredictionGamePlayer player) {
    manager.deletePlayerSync(player);
    notifyListeners();
  }

  Future<void> saveParlay(PredictionGamePlayer player, MatchPrep matchPrep, PredictionSet predictionSet, Parlay parlay) async {
    var dbWager = DbWager.fromParlay(parlay);
    dbWager.matchPrep.value = matchPrep;
    dbWager.predictionSet.value = predictionSet;
    dbWager.game.value = predictionGame;
    dbWager.user.value = player;

    await manager.addWager(dbWager);
    notifyListeners();
  }

  Future<void> saveIndependentWagers(PredictionGamePlayer player, MatchPrep matchPrep, PredictionSet predictionSet, List<Wager> wagers) async {
    for(var wager in wagers) {
      var dbWager = DbWager.fromWager(wager);
      dbWager.matchPrep.value = matchPrep;
      dbWager.predictionSet.value = predictionSet;
      dbWager.game.value = predictionGame;
      dbWager.user.value = player;
      await manager.addWager(dbWager);
    }
    notifyListeners();
  }

  Future<void> loadPredictionGame() async {
    await manager.loadPredictionGame();
    notifyListeners();
  }

  void loadPredictionGameSync() {
    manager.loadPredictionGameSync();
    notifyListeners();
  }

  Future<void> addWager(DbWager wager) async {
    await manager.addWager(wager);
    notifyListeners();
  }

  void addWagerSync(DbWager wager) {
    manager.addWagerSync(wager);
    notifyListeners();
  }

  Future<void> removeWager(DbWager wager) async {
    await manager.removeWager(wager);
    notifyListeners();
  }

  void removeWagerSync(DbWager wager) {
    manager.removeWagerSync(wager);
    notifyListeners();
  }

  PredictionGamePlayer? getPlayerById(int id) {
    return predictionGame.users.where((user) => user.id == id).firstOrNull;
  }

  MatchPrep? getMatchPrepById(int id) {
    return predictionGame.matchPreps.where((matchPrep) => matchPrep.id == id).firstOrNull;
  }

  Future<void> resolveWager(DbWager wager, DbWagerStatus status) async {
    await manager.resolveWager(wager, status);
    notifyListeners();
  }

  void resolveWagerSync(DbWager wager, DbWagerStatus status) {
    manager.resolveWagerSync(wager, status);
    notifyListeners();
  }

  Future<void> auditUserBalance(PredictionGamePlayer player) async {
    await manager.auditUserBalance(player);
    notifyListeners();
  }

  void auditUserBalanceSync(PredictionGamePlayer player) {
    manager.auditUserBalanceSync(player);
    notifyListeners();
  }
}
