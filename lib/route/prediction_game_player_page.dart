import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/widget/prediction_game_player_controls.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/widget/transaction_list.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/widget/wager_list.dart';

class PredictionGamePlayerPage extends StatelessWidget {
  const PredictionGamePlayerPage({super.key, required this.managerModel, required this.player});

  final PredictionGameManagerModel managerModel;
  final PredictionGamePlayer player;

  @override
  Widget build(BuildContext context) {
    String title = managerModel.predictionGame.name;
    if(player.nickname != null) {
      title = "$title - ${player.nickname}";
    }
    else if(player.serverUser.value != null) {
      title = "$title - ${player.serverUser.value!.username}";
    }
    var wagerModel = WagerListModel(managerModel: managerModel, player: player);
    var transactionModel = TransactionListModel(managerModel: managerModel, player: player);
    return EmptyScaffold(
      title: title,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: managerModel),
          ChangeNotifierProvider.value(value: wagerModel),
          ChangeNotifierProvider.value(value: transactionModel),
        ],
        builder: (context, child) {
          context.watch<PredictionGameManagerModel>();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: PredictionGamePlayerControls(player: player),
              ),
              Divider(),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text("Wagers", style: Theme.of(context).textTheme.titleMedium),
                          Expanded(child: WagerList()),
                        ],
                      ),
                    ),
                    VerticalDivider(),
                    Expanded(
                      child: Column(
                        children: [
                          Text("Transactions", style: Theme.of(context).textTheme.titleMedium),
                          Expanded(child: TransactionList()),
                        ],
                      ),
                    ),
                  ]
                )
              ),
            ],
          );
        },
      ),
    );
  }
}