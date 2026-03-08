/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/dialog/edit_prediction_player_dialog.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/dialog/topup_player_dialog.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/widget/wager_list.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/wager_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/maybe_tooltip.dart';
import 'package:shooting_sports_analyst/util.dart';

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
    validMatchPreps = model.getMatchPrepsSync(futureOnly: false, hasPredictionsOnly: true);
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

    bool canWager = selectedMatchPrep?.matchDate.isAfter(DateTime.now()) ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8 * uiScaleFactor,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8 * uiScaleFactor,
          children: [
            Text("Balance: ${player.balance.toStringAsFixed(2)}"),
            TextButton(
              child: Row(
                spacing: 4 * uiScaleFactor,
                children: [
                  Icon(Icons.add),
                  Text("Top up"),
                ],
              ),
              onPressed: () async {
                var result = await TopupPlayerDialog.show(context, player: player);
                if(result != null) {
                  player.balance = result;
                  await model.savePlayer(player);
                }
              },
            ),
            TextButton(
              child: Row(
                spacing: 4 * uiScaleFactor,
                children: [
                  Icon(Icons.security),
                  Text("Audit"),
                ],
              ),
              onPressed: () {
                model.auditUserBalance(player);
              },
            ),
            TextButton(
              child: Row(
                spacing: 4 * uiScaleFactor,
                children: [
                  Icon(Icons.edit),
                  Text("Edit"),
                ],
              ),
              onPressed: () async {
                var result = await EditPredictionPlayerDialog.show(context, player: player);
                if(result != null) {
                  await model.savePlayer(result);
                }
              },
            )
          ],
        ),
        PredictionGamePlayerStats(player: player),
        SizedBox(height: 4 * uiScaleFactor),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8 * uiScaleFactor,
          children: [
            DropdownMenu<MatchPrep>(
              width: 400 * uiScaleFactor,
              label: Text("Match"),
              dropdownMenuEntries: validMatchPreps.map((e) => DropdownMenuEntry(
                value: e,
                label: "${e.futureMatch.value!.eventName} - ${e.ratingProject.value!.name}"
              )).toList(),
              initialSelection: selectedMatchPrep,
              onSelected: (value) {
                if(value != null) {
                  _selectMatchPrep(model, value);
                }
              },
            ),
            DropdownMenu<RatingGroup>(
              width: 200 * uiScaleFactor,
              label: Text("Group"),
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
            MaybeTooltip(
              message: canWager ? null : "Match has already begun",
              child: TextButton(
                child: Row(
                  children: [
                    Icon(Icons.casino),
                    Text("Wager"),
                  ],
                ),
                onPressed: (!canWager && !kDebugMode) ? null : () async {
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
                    player: player,
                    predictions: predictions,
                    predictionSet: selectedPredictionSet,
                    matchId: selectedMatchPrep!.futureMatch.value!.matchId,
                    roundToMoneyline: true,
                    title: "Odds for ${selectedRatingGroup!.name}",
                    helpText: "Current match: ${selectedMatchPrep!.futureMatch.value!.eventName}",
                    availableBalance: player.balance,
                    manager: model.manager,
                    matchPrep: selectedMatchPrep,
                  );

                  if(result != null) {
                    if(result.isParlay) {
                      _log.i("Saving ${result.parlay!.legs.length}-leg parlay");
                      _saveParlay(player, model, result.parlay!);
                    }
                    else if(result.isIndependentWagers) {
                      _saveIndependentWagers(player, model, result.independentWagers!);
                    }
                  }
                },
              ),
            ),
            Consumer<WagerListModel>(
              builder: (context, wagerModel, child) => ClickableLink(
                decorateTextColor: false,
                onTap: () {
                  wagerModel.openOnly = !(wagerModel.openOnly);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: !wagerModel.openOnly,
                      onChanged: (value) {
                        wagerModel.openOnly = !(value ?? false);
                      },
                    ),
                    Text("Show all wagers"),
                  ],
                )
              ),
            )
          ],
        )
      ],
    );
  }
}

class PredictionGamePlayerStats extends StatelessWidget {
  const PredictionGamePlayerStats({super.key, required this.player});

  final PredictionGamePlayer player;

  @override
  Widget build(BuildContext context) {
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var wagers = player.wagers.toList();

    var unvoidedWagers = wagers.where((wager) => wager.status != DbWagerStatus.voided).toList();
    var wonWagers = unvoidedWagers.where((wager) => wager.status == DbWagerStatus.won).toList();
    var totalWagered = unvoidedWagers.map((wager) => wager.amount).sum;
    var totalWon = wonWagers.map((wager) => wager.payout()).sum;
    var winPercentage = unvoidedWagers.length > 0 ? (wonWagers.length / unvoidedWagers.length) : 0;

    return Row(
      spacing: 8 * uiScaleFactor,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Wagered: ${totalWagered.toStringAsFixed(2)}"),
        Text("Won: ${totalWon.toStringAsFixed(2)}"),
        Text("Accuracy: ${winPercentage.toDouble().asPercentage(decimals: 1, includePercent: true)}"),
      ],
    );
  }
}
