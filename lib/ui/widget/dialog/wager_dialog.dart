/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

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

  void _updateWager(int index, UserPrediction newPrediction, {double amount = 1.0}) {
    double? bestPossibleOdds;
    var algorithmPrediction = _shootersToPredictions[newPrediction.shooter];
    if(algorithmPrediction != null) {
      if(algorithmPrediction.lowPlace < newPrediction.bestPlace) {
        // If the algorithm prediction predicts a better place in the worst
        // case scenario than the user prediction's best place, cap the odds
        // at moneyline +25000 (250:1) to capture the rare but possible chance
        // of a competitor DQing or having some other major catastrophe.
        bestPossibleOdds = 251.0;
      }
    }
    Wager wager;
    if(bestPossibleOdds != null) {
      wager = Wager(
        prediction: newPrediction,
        probability: PredictionProbability.fromUserPrediction(
          newPrediction, _shootersToPredictions,
          bestPossibleOdds: bestPossibleOdds,
        ),
        amount: amount,
      );
    }
    else {
      wager = Wager(
        prediction: newPrediction,
        probability: PredictionProbability.fromUserPrediction(
          newPrediction, _shootersToPredictions,
        ),
        amount: amount,
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
                          child: Text("Moneyline: ${leg.probability.moneylineOdds}")
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () async {
                                var newPrediction = await EditPredictionDialog.show(
                                  context,
                                  prediction: leg.prediction,
                                  availableCompetitors: widget.predictions,
                                );

                                if (newPrediction != null) {
                                  _updateWager(index, newPrediction);
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
                subtitle: Text("Moneyline: ${_parlay!.probability.moneylineOdds}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
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
                    var newPrediction = await EditPredictionDialog.show(
                      context,
                      prediction: UserPrediction(
                        shooter: widget.predictions[0].shooter,
                        bestPlace: 1,
                        worstPlace: 3),
                      availableCompetitors: widget.predictions,
                    );

                    if(newPrediction != null) {
                      _updateWager(-1, newPrediction);
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

class EditPredictionDialog extends StatefulWidget {
  const EditPredictionDialog({super.key, required this.prediction, required this.availableCompetitors});

  final UserPrediction prediction;
  final List<AlgorithmPrediction> availableCompetitors;

  static Future<UserPrediction?> show(BuildContext context, {required UserPrediction prediction, required List<AlgorithmPrediction> availableCompetitors}) async {
    return showDialog<UserPrediction>(context: context, builder: (context) => EditPredictionDialog(prediction: prediction, availableCompetitors: availableCompetitors));
  }

  @override
  State<EditPredictionDialog> createState() => _EditPredictionDialogState();
}

class _EditPredictionDialogState extends State<EditPredictionDialog> {

  late UserPrediction _newPrediction;
  @override
  void initState() {
    _newPrediction = widget.prediction.copyWith();
    _competitorController = TextEditingController(); // handled by initialSelection
    _bestPlaceController = TextEditingController(text: _newPrediction.bestPlace.toString());
    _worstPlaceController = TextEditingController(text: _newPrediction.worstPlace.toString());
    super.initState();
  }

  late TextEditingController _competitorController;
  late TextEditingController _bestPlaceController;
  late TextEditingController _worstPlaceController;

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
            initialSelection: _newPrediction.shooter,
            enableFilter: true,
            enableSearch: true,
            menuHeight: 500,
            onSelected: (value) {
              if(value != null) {
                _newPrediction = _newPrediction.copyWith(shooter: value);
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
              if(newBestPlace != null && newBestPlace <= _newPrediction.worstPlace) {
                _newPrediction = _newPrediction.copyWith(bestPlace: newBestPlace);
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
                _newPrediction = _newPrediction.copyWith(worstPlace: newWorstPlace);
              }
            },
          ),
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
              _newPrediction = _newPrediction.copyWith(bestPlace: newBestPlace, worstPlace: newWorstPlace);
            }
            Navigator.of(context).pop(_newPrediction);
          }
        )
      ],
    );
  }
}
