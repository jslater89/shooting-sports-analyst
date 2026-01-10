/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/ui/prematch/dialog/match_prep_select_dialog.dart';

class PredictionGameMatchList extends StatelessWidget {
  const PredictionGameMatchList({super.key});

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<PredictionGameManagerModel>(context);
    var matches = model.predictionGame.matchPreps.toList();
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              child: Text("ADD MATCH"),
              onPressed: () async {
                var matchPrep = await MatchPrepSelectDialog.show(context);
                if(matchPrep != null) {
                  model.addMatchPrep(matchPrep);
                }
              },
            )
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemBuilder: (context, index) {
              var match = matches[index];
              var action = model.predictionGame.wagers
                .where((wager) => wager.matchPrep.value!.id == match.id)
                .map((wager) => wager.amount)
                .sum;
              var projectName = match.ratingProject.value!.name;
              return ListTile(
                title: Text(match.futureMatch.value!.eventName),
                subtitle: Text("Action: ${action.toStringAsFixed(2)}  ($projectName)"),
              );
            },
            itemCount: matches.length,
          ),
        ),
      ],
    );
  }
}