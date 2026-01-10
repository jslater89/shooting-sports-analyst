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
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';

class TransactionList extends StatelessWidget {
  const TransactionList({super.key});

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<TransactionListModel>(context);
    final forPlayer = model.player != null;
    final forMatchPrep = model.matchPrep != null;
    return ListView.builder(
      itemCount: model.transactions.length,
      itemBuilder: (context, index) {
        var transaction = model.transactions[index];
        var matchPrep = transaction.wager.value?.matchPrep.value;
        var wager = transaction.wager.value;
        var player = transaction.user.value;
        var amount = transaction.amount;
        var type = transaction.type;
        var date = transaction.created;

        final nameFlex = 4;
        final amountFlex = 1;

        String amountString;
        if(type.isCredit) {
          amountString = "${amount.toStringAsFixed(2)}";
        }
        else {
          amountString = "(${amount.toStringAsFixed(2)})";
        }

        Widget title = Row(
          children: [
            Expanded(flex: nameFlex, child: Text(transaction.type.displayName)),
            Expanded(flex: amountFlex, child: Text(amountString)),
          ],
        );

        List<String> subtitleParts = [];
        if(wager != null) {
          subtitleParts.add("${wager.descriptiveString} (${wager.ratingGroup.value?.name ?? "unknown group"})");
        }
        if(matchPrep != null && !forMatchPrep) {
          var limitedPrepName = matchPrep.futureMatch.value!.eventName;
          if(limitedPrepName.length > 50) {
            limitedPrepName = "${limitedPrepName.substring(0, 50)}...";
          }
          subtitleParts.add(limitedPrepName);
        }
        if(player != null && !forPlayer) {
          subtitleParts.add(player.nickname ?? player.serverUser.value?.username ?? "(no username)");
        }
        String subtitle = "";
        if(subtitleParts.isNotEmpty) {
          subtitle = subtitleParts.join(" - ");
        }
        return ListTile(
          title: title,
          subtitle: Text(subtitle),
        );
      },
    );
  }
}

/// A model for a [TransactionList].
///
/// Can be filtered by player and/or match prep.
class TransactionListModel extends ChangeNotifier {
  TransactionListModel({required this.managerModel, PredictionGamePlayer? player, MatchPrep? matchPrep}) {
    playerId = player?.id;
    matchPrepId = matchPrep?.id;
    loadTransactions();
    managerModel.addListener(loadTransactions);
  }

  @override
  void dispose() {
    managerModel.removeListener(loadTransactions);
    super.dispose();
  }

  PredictionGameManagerModel managerModel;
  int? playerId;
  int? matchPrepId;

  PredictionGamePlayer? get player => playerId != null ? managerModel.getPlayerById(playerId!) : null;
  MatchPrep? get matchPrep => matchPrepId != null ? managerModel.getMatchPrepById(matchPrepId!) : null;

  List<PredictionGameTransaction> transactions = [];

  Future<void> loadTransactions() async {
    var newTransactions = <PredictionGameTransaction>[];
    if(player != null) {
      newTransactions = await player!.transactions.filter().sortByCreatedDesc().findAll();
      if(matchPrep != null) {
        newTransactions = newTransactions.where((transaction) => transaction.wager.value?.matchPrep.value!.id == matchPrep!.id).toList();
      }
    }
    else {
      newTransactions = managerModel.manager.predictionGame.transactions.toList();
      if(matchPrep != null) {
        newTransactions = newTransactions.where((transaction) => transaction.wager.value?.matchPrep.value!.id == matchPrep!.id).toList();
      }
    }
    _setTransactions(newTransactions);
  }

  void _setTransactions(List<PredictionGameTransaction> transactions) {
    this.transactions = transactions;
    notifyListeners();
  }
}