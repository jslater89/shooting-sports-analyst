/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard.dart';
import 'package:shooting_sports_analyst/util.dart';

class WagerDialog extends StatefulWidget {
  const WagerDialog({super.key, required this.predictions, required this.matchId});

  final String matchId;
  final List<AlgorithmPrediction> predictions;

  static Future<List<Wager>?> show(BuildContext context, {required List<AlgorithmPrediction> predictions, required String matchId}) async {
    return showDialog<List<Wager>>(
      context: context,
      builder: (context) => WagerDialog(
        predictions: predictions,
        matchId: matchId
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

  @override
  void initState() {
    super.initState();
    for(var prediction in widget.predictions) {
      _shootersToPredictions[prediction.shooter] = prediction;
    }
  }

  void _updateParlay() {
    if(_legs.length > 1) {
      _parlay = Parlay(legs: _legs, amount: 1);
    } else {
      _parlay = null;
    }
  }

  void _updateWager(int index, Wager newWager) {
    double? bestPossibleOdds;
    var algorithmPrediction = _shootersToPredictions[newWager.prediction.shooter];
    if(algorithmPrediction != null) {
      if(algorithmPrediction.lowPlace < newWager.prediction.bestPlace) {
        // If the algorithm prediction predicts a better place in the worst
        // case scenario than the user prediction's best place, cap the odds
        // at moneyline +25000 (250:1) to capture the rare but possible chance
        // of a competitor DQing or having some other major catastrophe.
        bestPossibleOdds = 251.0;
      }
    }
    Wager wager;
    var newPrediction = newWager.prediction;
    if(bestPossibleOdds != null) {
      wager = Wager(
        prediction: newPrediction,
        probability: PredictionProbability.fromUserPrediction(
          newPrediction,
          _shootersToPredictions,
          bestPossibleOdds: bestPossibleOdds,
          random: Random(widget.matchId.stableHash),
        ),
        amount: newWager.amount,
      );
    }
    else {
      wager = Wager(
        prediction: newPrediction,
        probability: PredictionProbability.fromUserPrediction(
          newPrediction,
          _shootersToPredictions,
          random: Random(widget.matchId.stableHash),
        ),
        amount: newWager.amount,
      );
    }

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
    return AlertDialog(
      title: Text("Check odds"),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._legs.asMap().entries.map((entry) {
                      final index = entry.key;
                      final leg = entry.value;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 13,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.13),
                          child: Text(
                            "${index + 1}",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        title: Text("${leg.prediction.shooter.name} ${leg.prediction.bestPlace.ordinalPlace}-${leg.prediction.worstPlace.ordinalPlace}"),
                        subtitle: Tooltip(
                          message: "Fractional: ${leg.probability.fractionalOdds}\n"
                              "Decimal: ${leg.probability.decimalOdds.toStringAsFixed(3)}\n"
                              "Probabilities: ${leg.probability.probability.asPercentage(decimals: 2, includePercent: true)}/${leg.probability.probabilityWithHouseEdge.asPercentage(decimals: 2, includePercent: true)}",
                          child: Text(
                            "Moneyline: ${leg.probability.moneylineOdds}  -  "
                            "Payout: ${leg.amount.toStringAsFixed(2)} → ${leg.payout.toStringAsFixed(2)}"
                          )
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () async {
                                var newWager = await EditWagerDialog.show(
                                  context,
                                  prediction: leg,
                                  availableCompetitors: widget.predictions,
                                );

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
                  message: "Fractional: ${_parlay!.probability.fractionalOdds}\n"
                      "Decimal: ${_parlay!.probability.decimalOdds.toStringAsFixed(3)}\n"
                      "Probabilities: ${_parlay!.probability.probability.asPercentage(decimals: 2, includePercent: true)}/${_parlay!.probability.probabilityWithHouseEdge.asPercentage(decimals: 2, includePercent: true)}",
                  child: Text(
                    "Moneyline: ${_parlay!.probability.moneylineOdds}  -  "
                    "Payout: ${_parlay!.amount.toStringAsFixed(2)} → ${_parlay!.payout.toStringAsFixed(2)}"
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
                  child: Text("ADD LEG"),
                  onPressed: _legs.length >= 10 ? null : () async {
                    var newWager = await EditWagerDialog.show(
                      context,
                      prediction: Wager(
                        prediction: UserPrediction(
                          shooter: widget.predictions[0].shooter,
                          bestPlace: 1,
                          worstPlace: 3),
                        probability: PredictionProbability(0.5),
                        amount: 10,
                      ),
                      availableCompetitors: widget.predictions,
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
        TextButton(onPressed: () => Navigator.of(context).pop(_legs), child: Text("SAVE")),
      ],
    );
  }
}

class EditWagerDialog extends StatefulWidget {
  const EditWagerDialog({super.key, required this.wager, required this.availableCompetitors});

  final Wager wager;
  final List<AlgorithmPrediction> availableCompetitors;

  static Future<Wager?> show(BuildContext context, {required Wager prediction, required List<AlgorithmPrediction> availableCompetitors}) async {
    return showDialog<Wager>(context: context, builder: (context) => EditWagerDialog(wager: prediction, availableCompetitors: availableCompetitors));
  }

  @override
  State<EditWagerDialog> createState() => _EditWagerDialogState();
}

class _EditWagerDialogState extends State<EditWagerDialog> {

  late Wager _newWager;
  @override
  void initState() {
    _newWager = widget.wager.deepCopy();
    _competitorController = TextEditingController(); // handled by initialSelection
    _bestPlaceController = TextEditingController(text: _newWager.prediction.bestPlace.toString());
    _worstPlaceController = TextEditingController(text: _newWager.prediction.worstPlace.toString());
    _amountController = TextEditingController(text: _newWager.amount.toString());
    super.initState();
  }

  late TextEditingController _competitorController;
  late TextEditingController _bestPlaceController;
  late TextEditingController _worstPlaceController;
  late TextEditingController _amountController;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Edit prediction"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownMenu<ShooterRating>(
            dropdownMenuEntries: widget.availableCompetitors.map((e) =>
              DropdownMenuEntry<ShooterRating>(value: e.shooter, label: e.shooter.name)).toList(),
            initialSelection: _newWager.prediction.shooter,
            enableFilter: true,
            enableSearch: true,
            menuHeight: 500,
            onSelected: (value) {
              if(value != null) {
                _newWager = _newWager.copyWith(
                  prediction: _newWager.prediction.copyWith(shooter: value)
                );
                _competitorController.text = value.name;
              }
            },
            controller: _competitorController,
            label: Text("Competitor"),
          ),
          TextField(
            controller: _bestPlaceController,
            decoration: InputDecoration(labelText: "Best place"),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: (value) {
              var newBestPlace = int.tryParse(value);
              if(newBestPlace != null && newBestPlace <= _newWager.prediction.worstPlace) {
                _newWager = _newWager.copyWith(
                  prediction: _newWager.prediction.copyWith(bestPlace: newBestPlace)
                );
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
              if(newWorstPlace != null && newWorstPlace >= _newWager.prediction.bestPlace) {
                _newWager = _newWager.copyWith(
                  prediction: _newWager.prediction.copyWith(worstPlace: newWorstPlace)
                );
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
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          child: Text("SAVE"),
          onPressed: () {
            var newBestPlace = int.tryParse(_bestPlaceController.text);
            var newWorstPlace = int.tryParse(_worstPlaceController.text);
            if(newBestPlace != null && newWorstPlace != null && newBestPlace <= newWorstPlace) {
              _newWager = _newWager.copyWith(
                prediction: _newWager.prediction.copyWith(bestPlace: newBestPlace, worstPlace: newWorstPlace)
              );
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
