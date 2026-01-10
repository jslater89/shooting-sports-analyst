/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/wager_dialog.dart';

final _log = SSALogger("PredictionGamePlayerControls");

class PredictionGamePlayerControls extends StatefulWidget {
  const PredictionGamePlayerControls({super.key, required this.player});

  final PredictionGamePlayer player;

  @override
  State<PredictionGamePlayerControls> createState() => _PredictionGamePlayerControlsState();
}

class _PredictionGamePlayerControlsState extends State<PredictionGamePlayerControls> {
  MatchPrep? selectedMatchPrep;
  PredictionSet? selectedPredictionSet;
  RatingGroup? selectedRatingGroup;
  List<MatchPrep> validMatchPreps = [];
  List<RatingGroup> validRatingGroups = [];
  TextEditingController matchPrepNameController = TextEditingController();
  TextEditingController ratingGroupNameController = TextEditingController();
  Map<RatingGroup, List<AlgorithmPrediction>> algorithmPredictionCache = {};

  List<AlgorithmPrediction> getPredictionsForGroup(RatingGroup group) {
    if(algorithmPredictionCache.containsKey(group)) {
      return algorithmPredictionCache[group]!;
    }
    var predictions = selectedMatchPrep?.latestPredictionSet()?.algorithmPredictions.where((p) => p.group.value == group).toList();
    algorithmPredictionCache[group] = predictions?.map((p) => p.hydrate()).nonNulls.toList() ?? [];
    return algorithmPredictionCache[group]!;
  }


  @override
  void initState() {
    var model = context.read<PredictionGameManagerModel>();
    validMatchPreps = model.predictionGame.matchPreps.where((m) => m.latestPredictionSet() != null).toList();
    if(validMatchPreps.isNotEmpty) {
      _selectMatchPrep(model, validMatchPreps.first);
    }
    super.initState();
  }

  @override
  void dispose() {
    matchPrepNameController.dispose();
    ratingGroupNameController.dispose();
    super.dispose();
  }


  void _selectMatchPrep(PredictionGameManagerModel model, MatchPrep p) {
    var predictionSet = p.latestPredictionSet();
    if(predictionSet != null) {
      setState(() {
        selectedMatchPrep = p;
        selectedPredictionSet = predictionSet;
        validRatingGroups = model.predictionGame.availableRatingGroups(p)[predictionSet] ?? [];
        if(selectedRatingGroup != null && !validRatingGroups.contains(selectedRatingGroup!)) {
          selectedRatingGroup = validRatingGroups.firstOrNull;
          ratingGroupNameController.text = selectedRatingGroup?.name ?? "";
        }
        else if(selectedRatingGroup == null) {
          selectedRatingGroup = validRatingGroups.firstOrNull;
          ratingGroupNameController.text = selectedRatingGroup?.name ?? "";
        }
        algorithmPredictionCache.clear();
      });
    }
  }

  void _saveParlay(PredictionGamePlayer player, PredictionGameManagerModel model, Parlay parlay) {
    model.saveParlay(player, selectedMatchPrep!, selectedPredictionSet!, parlay);
  }

  void _saveIndependentWagers(PredictionGamePlayer player, PredictionGameManagerModel model, List<Wager> wagers) {
    model.saveIndependentWagers(player, selectedMatchPrep!, selectedPredictionSet!, wagers);
  }

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<PredictionGameManagerModel>(context);
    var player = model.getPlayerById(widget.player.id)!;
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 8 * uiScaleFactor,
      children: [
        Text("Balance: ${player.balance.toStringAsFixed(2)}"),
        DropdownMenu<MatchPrep>(
          width: 300 * uiScaleFactor,
          dropdownMenuEntries: validMatchPreps.map((e) => DropdownMenuEntry(value: e, label: e.futureMatch.value!.eventName)).toList(),
          initialSelection: selectedMatchPrep,
          onSelected: (value) {
            if(value != null) {
              _selectMatchPrep(model, value);
            }
          },
        ),
        DropdownMenu<RatingGroup>(
          width: 300 * uiScaleFactor,
          dropdownMenuEntries: validRatingGroups.map((e) => DropdownMenuEntry(value: e, label: e.name)).toList(),
          initialSelection: selectedRatingGroup,
          onSelected: (value) {
            if(value != null) {
              setState(() {
                selectedRatingGroup = value;
              });
            }
          },
        ),
        TextButton(
          child: Row(
            children: [
              Icon(Icons.casino),
              Text("Wager"),
            ],
          ),
          onPressed: () async {
            if(selectedMatchPrep == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Please select a match prep to wager on.")),
              );
              return;
            }
            if(selectedRatingGroup == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Please select a rating group to wager on.")),
              );
              return;
            }
            var predictions = getPredictionsForGroup(selectedRatingGroup!);
            predictions.sort((a, b) => b.shooter.rating.compareTo(a.shooter.rating));

            var result = await WagerDialog.show(
              context,
              predictions: predictions,
              matchId: selectedMatchPrep!.futureMatch.value!.matchId,
              title: "Odds for ${selectedRatingGroup!.name}",
            );

            if(result != null) {
              if(result.isParlay) {
                _log.i("Saving ${result.parlay!.legs.length}-leg parlay");
                _saveParlay(player, model, result.parlay!);
              }
              else if(result.isIndependentWagers) {
                _log.i("Saving ${result.independentWagers!.length} independent wagers");
                _saveIndependentWagers(player, model, result.independentWagers!);
              }
            }

          },
        ),
        TextButton(
          child: Row(
            children: [
              Icon(Icons.add),
              Text("Top up"),
            ],
          ),
          onPressed: () {

          },
        ),
        TextButton(
          child: Row(
            children: [
              Icon(Icons.security),
              Text("Audit"),
            ],
          ),
          onPressed: () {

          },
        )
      ],
    );
  }
}