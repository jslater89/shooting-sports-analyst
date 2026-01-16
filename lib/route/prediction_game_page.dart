/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';

class PredictionGamePage extends StatefulWidget {
  const PredictionGamePage({super.key, required this.predictionGame});

  final PredictionGame predictionGame;

  @override
  State<PredictionGamePage> createState() => _PredictionGamePageState();
}

class _PredictionGamePageState extends State<PredictionGamePage> {
  late PredictionGameManagerModel _model;

  @override
  void initState() {
    super.initState();
    _model = PredictionGameManagerModel(predictionGame: widget.predictionGame);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _model,
      child: EmptyScaffold(
        title: _model.predictionGame.name,
        child: PredictionGameManagerUI(),
      ),
    );
  }
}
