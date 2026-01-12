/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/util.dart';

class TransactionList extends StatelessWidget {
  const TransactionList({super.key});

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<TransactionListModel>(context);
    final forPlayer = model.player != null;
    final forMatchPrep = model.matchPrep != null;
    final showPlayer = !forPlayer;
    final showMatchPrep = !forMatchPrep;
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

        final nameFlex = 2;
        final descriptionFlex = 5;
        final amountFlex = 2;

        String amountString;
        if(type.isCredit) {
          if(amount >= 0) {
            amountString = "${amount.toStringAsFixed(2)}";
          }
          else {
            amountString = "(${(-amount).toStringAsFixed(2)})";
          }
        }
        else {
          if(amount > 0) {
            amountString = "(${amount.toStringAsFixed(2)})";
          }
          else {
            amountString = "${(-amount).toStringAsFixed(2)}";
          }
        }

        String? descriptionString;
        if(wager != null) {
          descriptionString = "${wager.descriptiveString} (${wager.ratingGroup.value?.name ?? "unknown group"})";
        }

        Widget title = Row(
          children: [
            Expanded(flex: nameFlex, child: Text(transaction.type.displayName)),
            Expanded(flex: descriptionFlex, child: Text(descriptionString ?? "", overflow: TextOverflow.ellipsis)),
            Expanded(flex: amountFlex, child: Text(amountString)),
          ],
        );

        List<Widget> subtitleParts = [];
        subtitleParts.add(
          Expanded(flex: 1, child: Text(programmerYmdHmFormat.format(date), overflow: TextOverflow.ellipsis)),
        );
        if(showPlayer && player != null) {
          subtitleParts.add(
            Expanded(flex: 1, child: Text(player.nickname ?? player.serverUser.value?.username ?? "(no username)", overflow: TextOverflow.ellipsis)),
          );
        }
        if(showMatchPrep && matchPrep != null) {
          subtitleParts.add(
            Expanded(flex: 4, child: Text(matchPrep.futureMatch.value!.eventName, overflow: TextOverflow.ellipsis)),
          );
        }
        return ListTile(
          title: title,
          subtitle: Row(children: subtitleParts),
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
    var newTransactions = await managerModel.getTransactions(matchPrep: matchPrep, player: player);
    _setTransactions(newTransactions);
  }

  void _setTransactions(List<PredictionGameTransaction> transactions) {
    this.transactions = transactions;
    notifyListeners();
  }
}