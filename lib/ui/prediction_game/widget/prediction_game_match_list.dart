/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/route/match_prep_page.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/dialog/match_prep_wager_dialog.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/ui/prematch/dialog/match_prep_select_dialog.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';

class PredictionGameMatchList extends StatelessWidget {
  const PredictionGameMatchList({super.key});

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<PredictionGameManagerModel>(context);
    var matches = model.getMatchPrepsSync(futureOnly: false, hasPredictionsOnly: false);
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
              var matchResult = match.futureMatch.value!.dbMatch.value;
              var ratings = match.ratingProject.value;

              List<Widget> trailing = [];
              if(matchResult != null) {
                trailing.add(Tooltip(
                  message: "View match scores",
                  child: IconButton(
                    icon: Icon(Icons.scoreboard_outlined),
                    onPressed: () async {
                      var match = await matchResult.hydrate();
                      if(match.isErr()) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to hydrate match.")));
                        return;
                      }
                      Navigator.of(context).push(MaterialPageRoute(builder: (context) => ResultPage(
                        canonicalMatch: match.unwrap(),
                        ratings: ratings,
                      )));
                    }
                  ),
                ));
              }
              trailing.add(Tooltip(
                message: "Process wagers for this match",
                child: IconButton(
                  icon: Icon(Icons.dataset_linked),
                  onPressed: () async {
                    var processedWagers = await MatchPrepWagerDialog.show(
                      context: context,
                      matchPrep: match,
                      predictionGameModel: model,
                    );

                    if(processedWagers?.isNotEmpty ?? false) {
                      model.loadPredictionGame();
                    }
                  }
                ),
              ));
              trailing.add(
                IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () async {
                    var confirm = await ConfirmDialog.show(
                      context,
                      title: "Delete match",
                      content: Text("Are you sure you want to delete this match from the prediction game?\n\nThis will delete all wagers and transactions associated with this match."),
                      positiveButtonLabel: "DELETE MATCH",
                      negativeButtonLabel: "CANCEL",
                    );
                    if(confirm ?? false) {
                      model.deleteMatchPrep(match);
                    }
                  }
                )
              );
              return ListTile(
                title: Text(match.futureMatch.value!.eventName),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (context) => MatchPrepPage(prep: match)));
                },
                subtitle: Text("Action: ${action.toStringAsFixed(2)}  ($projectName)"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: trailing,
                ),
              );
            },
            itemCount: matches.length,
          ),
        ),
      ],
    );
  }
}