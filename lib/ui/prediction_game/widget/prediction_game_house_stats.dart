/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/util.dart';

class PredictionGameHouseStats extends StatelessWidget {
  const PredictionGameHouseStats({super.key});

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<PredictionGameManagerModel>(context);
    var wagers = model.predictionGame.wagers.toList();
    var players = model.predictionGame.users.toList();

    // We care about a few things:
    // 1. The house's position on closed wagers (amount wagered, amount paid)
    // 2. The amount of wagers currently outstanding (amount wagered, house risk)
    // 3. Net revenue on closed wagers

    // Open wagers are wagers that have not yet resolved.
    var openWagers = wagers.where((wager) => !wager.status.isResolved).toList();

    // Closed wagers can be voided, won, or lost.
    var voidedWagers = wagers.where((wager) => wager.status == DbWagerStatus.voided).toList();
    var wonWagers = wagers.where((wager) => wager.status == DbWagerStatus.won).toList();
    var lostWagers = wagers.where((wager) => wager.status == DbWagerStatus.lost).toList();

    var unvoidedClosedWagers = wonWagers + lostWagers;

    var totalUnvoidedWagered = unvoidedClosedWagers.map((wager) => wager.amount).sum;
    var totalUnvoidedPaidOut = unvoidedClosedWagers.map((wager) {
      if(wager.status == DbWagerStatus.won) {
        return wager.payout();
      }
      else {
        return 0;
      }
    }).sum;
    var houseNet = totalUnvoidedWagered - totalUnvoidedPaidOut;

    // Voided wagers are always net zero (void means the user is refunded)
    var voidedAmount = voidedWagers.map((wager) => wager.amount).sum;

    var totalOpenWagered = openWagers.map((wager) => wager.amount).sum;
    var totalOpenHouseRisk = openWagers.map((wager) => wager.payout()).sum;
    var totalOpenBettorProfit = totalOpenHouseRisk - totalOpenWagered;
    var openHouseNet = totalOpenHouseRisk - totalOpenWagered;

    double profitPercentage = totalUnvoidedWagered > 0 ? (houseNet / totalUnvoidedWagered) : 0;
    int? averageOpenOdds;
    if(totalOpenWagered != 0 && totalOpenBettorProfit != 0) {
      if(totalOpenBettorProfit > totalOpenWagered) {
        // positive moneyline: profit per dollar wagered * 100
        averageOpenOdds = (totalOpenBettorProfit / totalOpenWagered * 100).round();
      }
      else {
        // negative moneyline: -100 / (profit per dollar wagered)
        // profit is negative, so we negate it to get a positive denominator
        averageOpenOdds = (-100 / (totalOpenBettorProfit / totalOpenWagered)).round();
      }
    }
    var averageOpenOddsString = averageOpenOdds != null ?
      "${averageOpenOdds > 0 ? "+" : "-"}${averageOpenOdds.abs()}" :
      "n/a";

    double totalPlayerBankroll = players.map((player) => player.balance).sum;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text("Total open wagers: ${totalOpenWagered.toStringAsFixed(2)}")),
              Expanded(child: Text("Total open risk: ${totalOpenHouseRisk.toStringAsFixed(2)}")),
              Expanded(child: Text("Open net: ${openHouseNet.toStringAsFixed(2)} ($averageOpenOddsString)")),
              Expanded(child: Text("Total player bankroll: ${totalPlayerBankroll.toStringAsFixed(2)}")),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text("Total closed wagers: ${totalUnvoidedWagered.toStringAsFixed(2)}")),
              Expanded(child: Text("Total player winnings: ${totalUnvoidedPaidOut.toStringAsFixed(2)}")),
              Expanded(child: Text("House net: ${houseNet.toStringAsFixed(2)} (${profitPercentage.asPercentage(decimals: 1, includePercent: true)})")),
              Expanded(child: Text("Total voided: ${voidedAmount.toStringAsFixed(2)}")),
            ],
          )
        ],
      ),
    );
  }
}
