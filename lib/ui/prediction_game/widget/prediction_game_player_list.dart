/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/route/prediction_game_player_page.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/dialog/new_prediction_player_dialog.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';

class PredictionGamePlayerList extends StatelessWidget {
  const PredictionGamePlayerList({super.key});

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<PredictionGameManagerModel>(context);
    var users = model.predictionGame.users.toList();
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              child: Text("ADD PLAYER"),
              onPressed: () async {
                var player = await NewPredictionPlayerDialog.show(
                  context,
                  predictionGame: model.predictionGame,
                  initialBalance: 50.0,
                  returnInitialTransactionSeparately: false,
                );
                if(player != null) {
                  model.addNewPlayerSync(player);
                }
              },
            )
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemBuilder: (context, index) {
              var user = users[index];
              return ListTile(
                title: Text(user.nickname ?? user.serverUser.value?.username ?? "(no username)"),
                subtitle: Text("Balance: ${user.balance.toStringAsFixed(2)}"),
                trailing: IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () async {
                    var confirm = await ConfirmDialog.show(context, title: "Delete player", content: Text("Are you sure you want to delete this player?"));

                    if(confirm ?? false) {
                      model.deletePlayerSync(user);
                    }
                  },
                ),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (context) =>
                    PredictionGamePlayerPage(managerModel: model, player: user)));
                  model.loadPredictionGame();
                }
              );
            },
            itemCount: users.length,
          ),
        ),
      ],
    );
  }
}