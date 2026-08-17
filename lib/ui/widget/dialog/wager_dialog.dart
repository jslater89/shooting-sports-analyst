/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_cache.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_key.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/config.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/wager_updater.dart';
import 'package:shooting_sports_analyst/data/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/maybe_tooltip.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("WagerDialog");

/// Result of a [WagerDialog]. It will be either a list of independent wagers or a parlay.
///
/// [independentWagers] is a list of independent wagers, each of which is a single prediction.
///
/// [parlay] is a parlay of multiple wagers.
class WagerDialogResult {
  final List<Wager>? independentWagers;
  final Parlay? parlay;

  bool get isParlay => parlay != null;
  bool get isIndependentWagers => independentWagers != null;

  WagerDialogResult({this.independentWagers, this.parlay});
}

/// Show a dialog to edit a list of wagers. Pops a [WagerDialogResult].
class WagerDialog extends StatefulWidget {
  static final lruCache = MonteCarloSimulationCache(capacity: 100);

  WagerDialog({
    super.key,
    this.manager,
    this.player,
    required this.predictions,
    this.predictionSet,
    required this.matchId,
    this.matchPrep,
    this.title,
    this.roundToMoneyline = false,
    this.availableBalance,
    this.helpText,
  });

  final PredictionGamePlayer? player;
  final PredictionGameManager? manager;
  final bool roundToMoneyline;
  final double? availableBalance;
  final String? title;
  final String? helpText;
  final String matchId;
  final MatchPrep? matchPrep;
  final PredictionSet? predictionSet;
  final List<AlgorithmPrediction> predictions;

  static Future<WagerDialogResult?> show(BuildContext context, {
    PredictionGamePlayer? player,
    required List<AlgorithmPrediction> predictions,
    required String matchId,
    PredictionSet? predictionSet,
    String? title,
    bool roundToMoneyline = false,
    double? availableBalance,
    String? helpText,
    PredictionGameManager? manager,
    MatchPrep? matchPrep,
  }) async {
    return showDialog<WagerDialogResult>(
      context: context,
      builder: (context) => WagerDialog(
        player: player,
        manager: manager,
        predictions: predictions,
        matchId: matchId,
        predictionSet: predictionSet,
        title: title,
        roundToMoneyline: roundToMoneyline,
        availableBalance: availableBalance,
        helpText: helpText,
        matchPrep: matchPrep,
      ),
      barrierDismissible: false
    );
  }

  @override
  State<WagerDialog> createState() {
    return _WagerDialogState();
  }
}

class _WagerDialogState extends State<WagerDialog> {

  List<Wager> _legs = [];
  Parlay? _parlay;

  Map<ShooterRating, AlgorithmPrediction> _shootersToPredictions = {};
  Map<RatingGroup, int> _competitorCountsByGroup = {};
  Map<ShooterRating, WagerIneligibilityReason> _ineligibleCompetitors = {};

  @override
  void initState() {
    super.initState();
    for(var prediction in widget.predictions) {
      final scoringGroup = prediction.effectiveScoringGroup;
      _shootersToPredictions[prediction.shooter] = prediction;
      _competitorCountsByGroup.increment(scoringGroup);
    }
    _updateIneligibleCompetitors();
  }


  void _updateIneligibleCompetitors() {
    var game = widget.manager?.predictionGame;
    if(game == null) {
      return;
    }
    _ineligibleCompetitors.clear();
    for(var prediction in widget.predictions) {
      var ineligibilityReason = game.checkValidity(prediction, competitorCount: _competitorCountsByGroup[prediction.effectiveScoringGroup]!);
      if(ineligibilityReason != null) {
        _ineligibleCompetitors[prediction.shooter] = ineligibilityReason;
      }
    }
  }

  void _updateParlay() {
    if(_legs.length > 1) {
      _parlay = Parlay(legs: _legs, amount: 1);
      var probability = _parlay!.probability;
      _log.i("Parlay probability: ${probability.moneylineOdds}");
    } else {
      _parlay = null;
    }
  }

  Future<void> _updateWager(int index, Wager newWager) async {
    double? bestPossibleOdds;
    var algorithmPrediction = _shootersToPredictions[newWager.prediction.shooter];
    var userPrediction = newWager.prediction;
    if(algorithmPrediction != null && userPrediction is PlacePrediction) {
      if(algorithmPrediction.lowPlace < userPrediction.bestPlace) {
        // If the algorithm prediction predicts a better place in the worst
        // case scenario than the user prediction's best place, cap the odds
        // at moneyline +25000 (250:1) to capture the rare but possible chance
        // of a competitor DQing or having some other major catastrophe.
        bestPossibleOdds = 251.0;
      }
    }
    Wager wager;
    var newPrediction = newWager.prediction;
    List<MonteCarloSimulationLruKey> cacheKeys = [];
    List<MonteCarloSimulationLruKey> underdogCacheKeys = [];

    MonteCarloSimulationResult? simulationResult;
    MonteCarloSimulationResult? underdogSimulationResult;

    const int trials = 12500;

    // We can only use the simulation cache if we have a prediction set ID.
    final predictionSetId = widget.predictionSet?.id;
    if(predictionSetId != null) {
      for(var number in newPrediction.shooter.knownMemberNumbers) {
        cacheKeys.add(MonteCarloSimulationLruKey(
          predictionSetId: predictionSetId,
          memberNumber: number,
          trials: trials,
          scoringGroupUuid: newPrediction.effectiveScoringGroup.uuid,
        ));
      }

      simulationResult = WagerDialog.lruCache.lookupSync(cacheKeys.first, additionalKeys: cacheKeys.sublist(1));

      if(newPrediction is PercentageSpreadPrediction) {
        for(var number in newPrediction.underdog.knownMemberNumbers) {
          underdogCacheKeys.add(MonteCarloSimulationLruKey(
            predictionSetId: predictionSetId,
            memberNumber: number,
            trials: trials,
            scoringGroupUuid: newPrediction.effectiveScoringGroup.uuid,
          ));
        }

        underdogSimulationResult = WagerDialog.lruCache.lookupSync(underdogCacheKeys.first, additionalKeys: underdogCacheKeys.sublist(1));
      }
    }

    if(newPrediction is PercentageSpreadPrediction) {
      _log.v("Cache hits: ${simulationResult != null}/${underdogSimulationResult != null}");
    }
    else {
      _log.v("Cache hits: ${simulationResult != null}");
    }

    PredictionProbability probability;
    if(newPrediction is PercentageSpreadPrediction) {
      probability = newPrediction.calculateProbability(
        _shootersToPredictions,
        simulationResult: simulationResult,
        underdogSimulationResult: underdogSimulationResult,
        random: Random(widget.matchId.stableHash),
        bestPossibleOdds: bestPossibleOdds ?? PredictionProbability.bestPossibleOddsDefault,
        trials: trials,
      );
    }
    else {
      probability = newPrediction.calculateProbability(
        _shootersToPredictions,
        simulationResult: simulationResult,
        random: Random(widget.matchId.stableHash),
        bestPossibleOdds: bestPossibleOdds ?? PredictionProbability.bestPossibleOddsDefault,
        trials: trials,
      );
    }

    if(probability.ranOwnSimulation && predictionSetId != null) {
      WagerDialog.lruCache.cacheSync(cacheKeys.first, probability.simulationResult!.targetResult, additionalKeys: cacheKeys.sublist(1));
      if(newPrediction is PercentageSpreadPrediction) {
        WagerDialog.lruCache.cacheSync(underdogCacheKeys.first, probability.simulationResult!.underdogResult!, additionalKeys: underdogCacheKeys.sublist(1));
      }
    }

    wager = Wager(
      prediction: newPrediction,
      probability: probability,
      amount: newWager.amount,
    );

    if(widget.player != null && widget.manager != null && widget.matchPrep != null && widget.predictionSet != null) {
      final matchPrep = widget.matchPrep;
      MonteCarloSimulationResult? favoriteMonteCarlo;
      MonteCarloSimulationResult? underdogMonteCarlo;
      if(newPrediction is PercentageSpreadPrediction) {
        favoriteMonteCarlo = probability.simulationResult!.targetResult;
        underdogMonteCarlo = probability.simulationResult!.underdogResult;
      }
      final updater = BayesianWagerUpdater(
        config: BayesianOddsConfig(
          maxLogitShift: -1,
        )
      );
      await updater.updateWagerWithBayesianOddsShift(
        gm: widget.manager!,
        bettor: widget.player!,
        shootersToPredictions: _shootersToPredictions,
        wager: wager,
        matchPrep: matchPrep!,
        predictionSet: widget.predictionSet!,
        subjectMonteCarlo: probability.simulationResult!.targetResult,
        spreadFavoriteMonteCarlo: favoriteMonteCarlo,
        spreadUnderdogMonteCarlo: underdogMonteCarlo,
        cache: WagerDialog.lruCache,
        trials: trials,
      );
    }

    // Going by wager automatically handles the parlay case, since the wager dialog
    // combines all single legs into the parlay.

    if(index == -1) {
      _legs.add(wager);
    }
    else {
      _legs[index] = wager;
    }
    setState(() {
      _updateParlay();
    });
  }


  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var parlayValidity = _parlay != null ? _parlay!.checkValidity(fieldSize: _shootersToPredictions.length) : null;
    bool canAffordIndividualWagers = true;
    bool canAffordParlay = true;

    if(widget.availableBalance != null) {
      var legSum = _legs.map((e) => e.amount).sum;

      canAffordIndividualWagers = legSum <= widget.availableBalance!;
      if(_parlay != null) {
        var parlaySum = _parlay!.amount;
        canAffordParlay = parlaySum <= widget.availableBalance!;
      }
    }

    final game = widget.manager?.predictionGame;

    return AlertDialog(
      title: Text(widget.title ?? "Check odds"),
      content: SizedBox(
        width: 600 * uiScaleFactor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if(widget.helpText != null)
                      Text(widget.helpText!),
                    ..._legs.asMap().entries.map((entry) {
                      final index = entry.key;
                      final leg = entry.value;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 13,
                          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.13),
                          child: Text(
                            "${index + 1}",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        title: MaybeTooltip(message: leg.tooltipString, child: Text(leg.descriptiveString)),
                        subtitle: Tooltip(
                          message: "Fractional: ${leg.probability.fractionalOdds}\n"
                              "Decimal: ${leg.probability.decimalOdds.toStringAsFixed(3)}\n"
                              "Probabilities: ${leg.probability.probability.asPercentage(decimals: 2, includePercent: true)}/${leg.probability.probabilityWithHouseEdge.asPercentage(decimals: 2, includePercent: true)}",
                          child: Text(
                            "Moneyline: ${leg.probability.moneylineOdds}  -  "
                            "Payout: ${leg.amount.toStringAsFixed(2)} → ${widget.roundToMoneyline ? leg.moneylinePayout.toStringAsFixed(2) : leg.payout.toStringAsFixed(2)}"
                          )
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () async {
                                Wager? newWager;
                                if(leg.prediction is PlacePrediction) {
                                  newWager = await EditPlaceWagerDialog.show(
                                    context,
                                    prediction: leg,
                                    availableCompetitors: widget.predictions,
                                    ineligibleCompetitors: _ineligibleCompetitors,
                                    game: game,
                                  );
                                }
                                else if(leg.prediction is PercentagePrediction) {
                                  newWager = await EditPercentageWagerDialog.show(
                                    context,
                                    prediction: leg,
                                    availableCompetitors: widget.predictions,
                                    ineligibleCompetitors: _ineligibleCompetitors,
                                    game: game,
                                  );
                                }
                                else if(leg.prediction is PercentageSpreadPrediction) {
                                  newWager = await EditSpreadWagerDialog.show(
                                    context,
                                    prediction: leg,
                                    availableCompetitors: widget.predictions,
                                    ineligibleCompetitors: _ineligibleCompetitors,
                                    game: game,
                                  );
                                }

                                if (newWager != null) {
                                  _updateWager(index, newWager);
                                }
                              },
                              icon: Icon(Icons.edit),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete),
                              onPressed: () {
                                setState(() {
                                  _legs.removeAt(index);
                                  _updateParlay();
                                });
                              },
                            )
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            if(_parlay != null)
              ListTile(
                title: Text("${_parlay!.legs.length}-leg parlay"),
                subtitle: Tooltip(
                  message: !parlayValidity!.isValid ? parlayValidity.longDescription : "Fractional: ${_parlay!.probability.fractionalOdds}\n"
                      "Decimal: ${_parlay!.probability.decimalOdds.toStringAsFixed(3)}\n"
                      "Probabilities: ${_parlay!.probability.probability.asPercentage(decimals: 2, includePercent: true)}/${_parlay!.probability.probabilityWithHouseEdge.asPercentage(decimals: 2, includePercent: true)}",
                  child: Text(
                    "Moneyline: ${parlayValidity.isValid ? _parlay!.probability.moneylineOdds : "n/a"}  -  "
                    "${parlayValidity.isValid ? "Payout: ${_parlay!.amount.toStringAsFixed(2)} → ${_parlay!.payout.toStringAsFixed(2)}" : parlayValidity.shortDescription}"
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.edit),
                  onPressed: () async {
                    var newParlay = await EditParlayAmountDialog.show(context, parlay: _parlay!);
                    if(newParlay != null) {
                      setState(() {
                        _parlay = newParlay;
                      });
                    }
                  },
                )
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  child: Text("CLEAR"),
                  onPressed: () => setState(() {
                    _legs.clear();
                    _parlay = null;
                  }),
                ),
                TextButton(
                  child: Text("ADD PLACE LEG"),
                  onPressed: _legs.length >= 10 ? null : () async {
                    var newWager = await EditPlaceWagerDialog.show(
                      context,
                      prediction: Wager(
                        prediction: PlacePrediction(
                          shooter: widget.predictions[0].shooter,
                          bestPlace: 1,
                          worstPlace: 3),
                        probability: PredictionProbability(0.5),
                        amount: 10,
                      ),
                      availableCompetitors: widget.predictions,
                      ineligibleCompetitors: _ineligibleCompetitors,
                      game: game,
                    );

                    if(newWager != null) {
                      _updateWager(-1, newWager);
                    }
                  }
                ),
                TextButton(
                  child: Text("ADD PERCENTAGE LEG"),
                  onPressed: _legs.length >= 10 ? null : () async {
                    var newWager = await EditPercentageWagerDialog.show(
                      context,
                      prediction: Wager(
                        prediction: PercentagePrediction(
                          shooter: widget.predictions[0].shooter,
                          ratio: 0.95,
                        ),
                        probability: PredictionProbability(0.5),
                        amount: 10,
                      ),
                      availableCompetitors: widget.predictions,
                      ineligibleCompetitors: _ineligibleCompetitors,
                      game: game,
                    );
                    if(newWager != null) {
                      _updateWager(-1, newWager);
                    }
                  }
                ),
                TextButton(
                  child: Text("ADD SPREAD LEG"),
                  onPressed: _legs.length >= 10 ? null : () async {
                    var newWager = await EditSpreadWagerDialog.show(
                      context,
                      prediction: Wager(
                        prediction: PercentageSpreadPrediction(
                          shooter: widget.predictions[0].shooter,
                          underdog: widget.predictions[1].shooter,
                          ratioSpread: 0.05,
                        ),
                        probability: PredictionProbability(0.5),
                        amount: 10,
                      ),
                      availableCompetitors: widget.predictions,
                      ineligibleCompetitors: _ineligibleCompetitors,
                      game: game,
                    );
                    if(newWager != null) {
                      _updateWager(-1, newWager);
                    }
                  }
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        if(_parlay != null && _parlay!.checkValidity(fieldSize: _shootersToPredictions.length).isValid)
          MaybeTooltip(
            message: !canAffordParlay ? "You cannot afford this parlay (available balance: ${widget.availableBalance!.toStringAsFixed(2)})" : null,
            child: TextButton(
              onPressed: canAffordParlay ? () => Navigator.of(context).pop(WagerDialogResult(parlay: _parlay!)) : null,
              child: Text("SAVE PARLAY")
            ),
          ),
        if(_legs.isNotEmpty)
          MaybeTooltip(
            message: !canAffordIndividualWagers ? "You cannot afford ${_legs.length == 1 ? "this wager" : "these individual wagers"} (available balance: ${widget.availableBalance!.toStringAsFixed(2)})" : null,
            child: TextButton(
              onPressed: canAffordIndividualWagers ? () => Navigator.of(context).pop(WagerDialogResult(independentWagers: _legs)) : null,
              child: Text("SAVE${_legs.length == 1 ? "" : " INDEPENDENT WAGERS"}")
            ),
          ),
      ],
    );
  }
}

class EditPlaceWagerDialog extends StatefulWidget {
  const EditPlaceWagerDialog({
    super.key,
    required this.wager,
    required this.availableCompetitors,
    required this.ineligibleCompetitors,
    this.game,
  });

  final Wager wager;
  final List<AlgorithmPrediction> availableCompetitors;
  final PredictionGame? game;
  final Map<ShooterRating, WagerIneligibilityReason> ineligibleCompetitors;

  static Future<Wager?> show(BuildContext context, {
    required Wager prediction,
    required List<AlgorithmPrediction> availableCompetitors,
    required Map<ShooterRating, WagerIneligibilityReason> ineligibleCompetitors,
    PredictionGame? game,
  }) async {
    return showDialog<Wager>(
      context: context,
      builder: (context) =>
        EditPlaceWagerDialog(
          wager: prediction,
          availableCompetitors: availableCompetitors,
          ineligibleCompetitors: ineligibleCompetitors,
          game: game,
        ),
    );
  }

  @override
  State<EditPlaceWagerDialog> createState() => _EditPlaceWagerDialogState();
}

class _EditPlaceWagerDialogState extends State<EditPlaceWagerDialog> {

  late Wager _newWager;
  late PlacePrediction _newPrediction;
  @override
  void initState() {
    _newWager = widget.wager.deepCopy();
    if(_newWager.prediction is! PlacePrediction) {
      throw ArgumentError("Prediction is not a place prediction");
    }
    _newPrediction = _newWager.prediction as PlacePrediction;
    _competitorController = TextEditingController(); // handled by initialSelection
    _bestPlaceController = TextEditingController(text: _newPrediction.bestPlace.toString());
    _worstPlaceController = TextEditingController(text: _newPrediction.worstPlace.toString());
    _amountController = TextEditingController(text: _newWager.amount.toString());
    super.initState();
  }

  late TextEditingController _competitorController;
  late TextEditingController _bestPlaceController;
  late TextEditingController _worstPlaceController;
  late TextEditingController _amountController;

  WagerIneligibilityReason? ineligibilityReason() {
    return widget.ineligibleCompetitors[_newPrediction.shooter];
  }

  @override
  Widget build(BuildContext context) {
    final ineligibilityReason = this.ineligibilityReason();
    bool isEligible = ineligibilityReason == null;
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text("Edit place prediction"),
      content: SizedBox(
        width: 300 * uiScaleFactor,
        child: Column(
          spacing: 8 * uiScaleFactor,
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownMenu<ShooterRating>(
              dropdownMenuEntries: widget.availableCompetitors.map((e) =>
                DropdownMenuEntry<ShooterRating>(value: e.shooter, label: e.shooter.name)).toList(),
              initialSelection: _newPrediction.shooter,
              enableFilter: true,
              enableSearch: true,
              menuHeight: 500,
              onSelected: (value) {
                if(value != null) {
                  setState(() {
                    _newPrediction = _newPrediction.copyWith(shooter: value);
                    _newWager = _newWager.copyWith(prediction: _newPrediction);
                  });
                  _competitorController.text = value.name;
                }
              },
              controller: _competitorController,
              label: Text("Competitor"),
            ),
            if(!isEligible)
              Text(ineligibilityReason.uiDescription(widget.game), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            TextField(
              controller: _bestPlaceController,
              decoration: InputDecoration(labelText: "Best place"),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (value) {
                var newBestPlace = int.tryParse(value);
                if(newBestPlace != null && newBestPlace <= _newPrediction.worstPlace) {
                  setState(() {
                    _newPrediction = _newPrediction.copyWith(bestPlace: newBestPlace);
                    _newWager = _newWager.copyWith(prediction: _newPrediction);
                  });
                }
              },
            ),
            TextField(
              controller: _worstPlaceController,
              decoration: InputDecoration(labelText: "Worst place"),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (value) {
                var newWorstPlace = int.tryParse(value);
                if(newWorstPlace != null && newWorstPlace >= _newPrediction.bestPlace) {
                  setState(() {
                    _newPrediction = _newPrediction.copyWith(worstPlace: newWorstPlace);
                    _newWager = _newWager.copyWith(prediction: _newPrediction);
                  });
                }
              },
            ),
            TextField(
              controller: _amountController,
              decoration: InputDecoration(labelText: "Amount"),
              keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]*")),
              ],
              onChanged: (value) {
                var newAmount = double.tryParse(value);
                if(newAmount != null && newAmount > 0) {
                  _newWager = _newWager.copyWith(amount: newAmount);
                }
              },
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          child: Text("SAVE"),
          onPressed: !isEligible ? null : () {
            var newBestPlace = int.tryParse(_bestPlaceController.text);
            var newWorstPlace = int.tryParse(_worstPlaceController.text);
            if(newBestPlace != null && newWorstPlace != null && newBestPlace <= newWorstPlace) {
              setState(() {
                _newPrediction = _newPrediction.copyWith(bestPlace: newBestPlace, worstPlace: newWorstPlace);
                _newWager = _newWager.copyWith(prediction: _newPrediction);
              });
            }
            var newAmount = double.tryParse(_amountController.text);
            if(newAmount != null && newAmount > 0) {
              _newWager = _newWager.copyWith(amount: newAmount);
            }
            Navigator.of(context).pop(_newWager);
          }
        )
      ],
    );
  }
}

class EditPercentageWagerDialog extends StatefulWidget {
  const EditPercentageWagerDialog({
    super.key,
    required this.wager,
    required this.availableCompetitors,
    required this.ineligibleCompetitors,
    this.game,
  });

  final Wager wager;
  final List<AlgorithmPrediction> availableCompetitors;
  final Map<ShooterRating, WagerIneligibilityReason> ineligibleCompetitors;
  final PredictionGame? game;

  static Future<Wager?> show(BuildContext context, {
    required Wager prediction,
    required List<AlgorithmPrediction> availableCompetitors,
    required Map<ShooterRating, WagerIneligibilityReason> ineligibleCompetitors,
    PredictionGame? game,
  }) async {
    return showDialog<Wager>(
      context: context,
      builder: (context) =>
      EditPercentageWagerDialog(
        wager: prediction,
        availableCompetitors: availableCompetitors,
        ineligibleCompetitors: ineligibleCompetitors,
      ),
    );
  }

  @override
  State<EditPercentageWagerDialog> createState() => _EditPercentageWagerDialogState();
}

class _EditPercentageWagerDialogState extends State<EditPercentageWagerDialog> {

  late Wager _newWager;
  late PercentagePrediction _newPrediction;
  WagerIneligibilityReason? ineligibilityReason() {
    return widget.ineligibleCompetitors[_newPrediction.shooter];
  }
  @override
  void initState() {
    _newWager = widget.wager.deepCopy();
    if(_newWager.prediction is! PercentagePrediction) {
      throw ArgumentError("Prediction is not a percentage prediction");
    }
    _newPrediction = _newWager.prediction as PercentagePrediction;
    _competitorController = TextEditingController(); // handled by initialSelection
    _percentageController = TextEditingController(text: _newPrediction.percentage.toStringAsFixed(1));
    _amountController = TextEditingController(text: _newWager.amount.toString());
    super.initState();
  }

  late TextEditingController _competitorController;
  late TextEditingController _percentageController;
  late TextEditingController _amountController;

  @override
  Widget build(BuildContext context) {
    final ineligibilityReason = this.ineligibilityReason();
    bool isEligible = ineligibilityReason == null;
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text("Edit percentage prediction"),
      content: Column(
        spacing: 8 * uiScaleFactor,
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownMenu<ShooterRating>(
            dropdownMenuEntries: widget.availableCompetitors.map((e) =>
              DropdownMenuEntry<ShooterRating>(value: e.shooter, label: e.shooter.name)).toList(),
            initialSelection: _newPrediction.shooter,
            enableFilter: true,
            enableSearch: true,
            menuHeight: 500,
            onSelected: (value) {
              if(value != null) {
                setState(() {
                  _newPrediction = _newPrediction.copyWith(shooter: value);
                  _newWager = _newWager.copyWith(prediction: _newPrediction);
                });
                _competitorController.text = value.name;
              }
            },
            controller: _competitorController,
            label: Text("Competitor"),
          ),
          if(!isEligible)
            Text(ineligibilityReason.uiDescription(widget.game), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextField(
            controller: _percentageController,
            decoration: InputDecoration(
              labelText: "Percentage",
              prefixText: _newPrediction.above ? "≥" : "≤",
              suffixText: "%"),
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]*")),
            ],
            onChanged: (value) {
              var newPercentage = double.tryParse(value);
              if(newPercentage != null && newPercentage >= 0 && newPercentage <= 100) {
                setState(() {
                  _newPrediction = _newPrediction.copyWith(ratio: newPercentage / 100);
                  _newWager = _newWager.copyWith(prediction: _newPrediction);
                });
              }
            },
          ),
          TextField(
            controller: _amountController,
            decoration: InputDecoration(labelText: "Amount"),
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]*")),
            ],
            onChanged: (value) {
              var newAmount = double.tryParse(value);
              if(newAmount != null && newAmount > 0) {
                _newWager = _newWager.copyWith(amount: newAmount);
              }
            },
          ),
          CheckboxListTile(
            value: _newPrediction.above,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text("Above ${_newPrediction.ratio.asPercentage(decimals: 1, includePercent: true)}?"),
            onChanged: (value) {
              setState(() {
                _newPrediction = _newPrediction.copyWith(above: value ?? true);
              });
            },
          )
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          child: Text("SAVE"),
          onPressed: !isEligible ? null : () {
            var newPercentage = double.tryParse(_percentageController.text);
            if(newPercentage != null && newPercentage >= 0 && newPercentage <= 100) {
              setState(() {
                _newPrediction = _newPrediction.copyWith(ratio: newPercentage / 100);
                _newWager = _newWager.copyWith(prediction: _newPrediction);
              });
            }
            var newAmount = double.tryParse(_amountController.text);
            if(newAmount != null && newAmount > 0) {
              _newWager = _newWager.copyWith(amount: newAmount);
            }
            Navigator.of(context).pop(_newWager);
          }
        )
      ],
    );
  }
}

class EditSpreadWagerDialog extends StatefulWidget {
  const EditSpreadWagerDialog({
    super.key,
    required this.wager,
    required this.availableCompetitors,
    required this.ineligibleCompetitors,
    this.game,
  });

  final Wager wager;
  final List<AlgorithmPrediction> availableCompetitors;
  final Map<ShooterRating, WagerIneligibilityReason> ineligibleCompetitors;
  final PredictionGame? game;

  static Future<Wager?> show(BuildContext context, {
    required Wager prediction,
    required List<AlgorithmPrediction> availableCompetitors,
    required Map<ShooterRating, WagerIneligibilityReason> ineligibleCompetitors,
    PredictionGame? game,
  }) async {
    return showDialog<Wager>(
      context: context,
      builder: (context) => EditSpreadWagerDialog(
        wager: prediction,
        availableCompetitors: availableCompetitors,
        ineligibleCompetitors: ineligibleCompetitors,
        game: game,
      ),
    );
  }

  @override
  State<EditSpreadWagerDialog> createState() => _EditSpreadWagerDialogState();
}

class _EditSpreadWagerDialogState extends State<EditSpreadWagerDialog> {

  late Wager _newWager;
  late PercentageSpreadPrediction _newPrediction;
  @override
  void initState() {
    _newWager = widget.wager.deepCopy();
    if(_newWager.prediction is! PercentageSpreadPrediction) {
      throw ArgumentError("Prediction is not a percentage prediction");
    }
    _newPrediction = _newWager.prediction as PercentageSpreadPrediction;
    _underdogController = TextEditingController();
    _favoriteController = TextEditingController();
    _spreadController = TextEditingController(text: _newPrediction.percentageSpread.toStringAsFixed(2));
    _amountController = TextEditingController(text: _newWager.amount.toString());
    super.initState();
  }

  late TextEditingController _favoriteController;
  late TextEditingController _underdogController;
  late TextEditingController _spreadController;
  late TextEditingController _amountController;

  WagerIneligibilityReason? favoriteIneligibilityReason() {
    return widget.ineligibleCompetitors[_newPrediction.favorite];
  }
  WagerIneligibilityReason? underdogIneligibilityReason() {
    return widget.ineligibleCompetitors[_newPrediction.underdog];
  }

  @override
  Widget build(BuildContext context) {
    final favoriteIneligibilityReason = this.favoriteIneligibilityReason();
    final underdogIneligibilityReason = this.underdogIneligibilityReason();
    bool isFavoriteEligible = favoriteIneligibilityReason == null;
    bool isUnderdogEligible = underdogIneligibilityReason == null;
    bool isEligible = isFavoriteEligible && isUnderdogEligible;

    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var spreadPrefix = _newPrediction.favoriteCovers ? "≥" : "≤";
    return AlertDialog(
      title: Text("Edit percentage spread prediction"),
      content: Column(
        spacing: 8 * uiScaleFactor,
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownMenu<ShooterRating>(
            dropdownMenuEntries: widget.availableCompetitors.map((e) =>
              DropdownMenuEntry<ShooterRating>(value: e.shooter, label: e.shooter.name)).toList(),
            initialSelection: _newPrediction.favorite,
            enableFilter: true,
            enableSearch: true,
            menuHeight: 500,
            onSelected: (value) {
              if(value != null) {
                setState(() {
                  _newPrediction = _newPrediction.copyWith(shooter: value);
                  _newWager = _newWager.copyWith(prediction: _newPrediction);
                });
                _favoriteController.text = value.name;
              }
            },
            controller: _favoriteController,
            label: Text("Favorite"),
          ),
          if(!isFavoriteEligible)
            Text(favoriteIneligibilityReason.uiDescription(widget.game), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextField(
            controller: _spreadController,
            decoration: InputDecoration(labelText: "Spread", prefixText: spreadPrefix, suffixText: "%"),
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]*")),
            ],
            onChanged: (value) {
              var newSpread = double.tryParse(value);
              if(newSpread != null && newSpread >= 0 && newSpread <= 100) {
                setState(() {
                  _newPrediction = _newPrediction.copyWith(ratioSpread: newSpread / 100);
                  _newWager = _newWager.copyWith(prediction: _newPrediction);
                });
              }
            },
          ),
          if(!isUnderdogEligible)
            Text(underdogIneligibilityReason.uiDescription(widget.game), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          SizedBox(height: 10),
          DropdownMenu<ShooterRating>(
            dropdownMenuEntries: widget.availableCompetitors.map((e) =>
              DropdownMenuEntry<ShooterRating>(value: e.shooter, label: e.shooter.name)).toList(),
            initialSelection: _newPrediction.underdog,
            enableFilter: true,
            enableSearch: true,
            menuHeight: 500,
            onSelected: (value) {
              if(value != null) {
                setState(() {
                  _newPrediction = _newPrediction.copyWith(underdog: value);
                  _newWager = _newWager.copyWith(prediction: _newPrediction);
                });
                _underdogController.text = value.name;
              }
            },
            controller: _underdogController,
            label: Text("Underdog"),
          ),
          CheckboxListTile(
            value: _newPrediction.favoriteCovers,
            title: Text("${_newPrediction.favorite.name} covers?"),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) {
              setState(() {
                _newPrediction = _newPrediction.copyWith(favoriteCovers: value ?? true);
                _newWager = _newWager.copyWith(prediction: _newPrediction);
              });
            },
          ),
          TextField(
            controller: _amountController,
            decoration: InputDecoration(labelText: "Amount"),
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]*")),
            ],
            onChanged: (value) {
              var newAmount = double.tryParse(value);
              if(newAmount != null && newAmount > 0) {
                _newWager = _newWager.copyWith(amount: newAmount);
              }
            },
          )
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          child: Text("SAVE"),
          onPressed: !isEligible ? null : () {
            if(_newPrediction.shooter == _newPrediction.underdog) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Favorite and underdog cannot be the same shooter.")),
              );
              return;
            }
            var newSpread = double.tryParse(_spreadController.text);
            if(newSpread != null && newSpread >= 0 && newSpread <= 100) {
              setState(() {
                _newPrediction = _newPrediction.copyWith(ratioSpread: newSpread / 100);
                _newWager = _newWager.copyWith(prediction: _newPrediction);
              });
            }
            var newAmount = double.tryParse(_amountController.text);
            if(newAmount != null && newAmount > 0) {
              _newWager = _newWager.copyWith(amount: newAmount);
            }
            Navigator.of(context).pop(_newWager);
          }
        )
      ],
    );
  }
}

class EditParlayAmountDialog extends StatefulWidget {
  const EditParlayAmountDialog({super.key, required this.parlay});

  final Parlay parlay;

  static Future<Parlay?> show(BuildContext context, {required Parlay parlay}) async {
    return showDialog<Parlay>(context: context, builder: (context) => EditParlayAmountDialog(parlay: parlay));
  }

  @override
  State<EditParlayAmountDialog> createState() => _EditParlayAmountDialogState();
}

class _EditParlayAmountDialogState extends State<EditParlayAmountDialog> {
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.parlay.amount.toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Edit parlay amount"),
      content: TextField(
        controller: _amountController,
        decoration: InputDecoration(labelText: "Amount"),
        keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]*")),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          child: Text("SAVE"),
          onPressed: () {
            var newAmount = double.tryParse(_amountController.text);
            if(newAmount != null && newAmount > 0) {
              Navigator.of(context).pop(widget.parlay.copyWith(amount: newAmount));
            }
            else {
              Navigator.of(context).pop(widget.parlay);
            }
          },
        ),
      ],
    );
  }
}
