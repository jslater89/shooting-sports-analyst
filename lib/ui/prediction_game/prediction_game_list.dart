/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';

class PredictionGameList extends StatefulWidget {
  const PredictionGameList({super.key});

  @override
  State<PredictionGameList> createState() => _PredictionGameListState();
}

class _PredictionGameListState extends State<PredictionGameList> {
  @override
  Widget build(BuildContext context) {
    return Consumer<PredictionGameListModel>(
      builder: (context, model, child) {
        return ListView.builder(
          itemBuilder: (context, index) => ListTile(
            title: Text("Prediction Game $index")
          ),
          itemCount: model.predictionGames.length,
        );
      }
    );
  }
}

class PredictionGameListModel extends ChangeNotifier {
  final db = AnalystDatabase();
  List<PredictionGame> predictionGames = [];

  Future<void> load() async {
    predictionGames = await db.getPredictionGames();
    notifyListeners();
  }
}