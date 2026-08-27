/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';

class TopupPlayerDialog extends StatefulWidget {
  const TopupPlayerDialog({super.key, required this.player});

  final PredictionGamePlayer player;

  @override
  State<TopupPlayerDialog> createState() => _TopupPlayerDialogState();

  static Future<double?> show(BuildContext context, {required PredictionGamePlayer player, bool useRootNavigator = false}) async {
    return showDialog<double>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (context) => TopupPlayerDialog(player: player),
    );
  }
}

class _TopupPlayerDialogState extends State<TopupPlayerDialog> {
  late TextEditingController _amountController;
  bool topUp = true;

  double? _parsedAmount;
  double? _addingAmount;

  void _updateAddingAmount() {
    _parsedAmount = double.tryParse(_amountController.text);
    if(_parsedAmount == null) {
      _addingAmount = null;
      return;
    }
    if(topUp) {
      _addingAmount = _parsedAmount! - widget.player.balance;
    }
    else {
      _addingAmount = _parsedAmount!;
    }
  }

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.player.topupTargetBalance?.toStringAsFixed(2) ?? "");
    _updateAddingAmount();
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    String helpString;
    if(topUp) {
      helpString = "Set the player's balance to the given amount.";
    }
    else {
      helpString = "Add the given amount to the player's balance.";
    }
    return AlertDialog(
      title: Text("Top up player"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8 * uiScaleFactor,
        children: [
          Text(helpString),
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            value: topUp,
            title: Text("Top up"),
            onChanged: (value) {
              setState(() {
                topUp = value ?? true;
                _updateAddingAmount();
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
              setState(() {
                _updateAddingAmount();
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          onPressed: _addingAmount == null ? null : () => Navigator.of(context).pop(_addingAmount),
          child: Text("ADD ${_addingAmount?.toStringAsFixed(2) ?? "0.00"}"),
        ),
      ],
    );
  }
}