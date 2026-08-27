/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/widget/wager_list.dart';

class MatchPrepWagerDialog extends StatefulWidget {
  const MatchPrepWagerDialog({super.key, required this.matchPrep, required this.predictionGameModel});

  final MatchPrep matchPrep;
  final PredictionGameManagerModel predictionGameModel;

  static Future<List<DbWager>?> show({
    required BuildContext context,
    required MatchPrep matchPrep,
    required PredictionGameManagerModel predictionGameModel,
    bool useRootNavigator = false,
  }) async {
    return showDialog<List<DbWager>>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (context) => MatchPrepWagerDialog(matchPrep: matchPrep, predictionGameModel: predictionGameModel),
      barrierDismissible: false,
    );
  }

  @override
  State<MatchPrepWagerDialog> createState() => _MatchPrepWagerDialogState();
}

class _MatchPrepWagerDialogState extends State<MatchPrepWagerDialog> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.predictionGameModel,
      builder: (context, child) {
        final wagerModel = WagerListModel(managerModel: widget.predictionGameModel, matchPrep: widget.matchPrep);
        wagerModel.showResolve = true;
        wagerModel.showScores = true;
        wagerModel.showDelete = false;
        return AlertDialog(
          title: Text("Wagers for match"),
          content: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            width: MediaQuery.of(context).size.width * 0.9,
            child: ChangeNotifierProvider.value(value: wagerModel, child: WagerList(
              trailingWidth: 300,
            )),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("DONE")),
          ],
        );
      }
    );
  }
}