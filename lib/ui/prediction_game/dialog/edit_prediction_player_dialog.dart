/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:shooting_sports_analyst/config/config.dart";
import "package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart";

/// A dialog for editing an existing prediction game player.
///
/// [player] is the player to edit.
class EditPredictionPlayerDialog extends StatefulWidget {
  const EditPredictionPlayerDialog({
    super.key,
    required this.player,
  });

  final PredictionGamePlayer player;

  @override
  State<EditPredictionPlayerDialog> createState() => _EditPredictionPlayerDialogState();

  static Future<PredictionGamePlayer?> show(BuildContext context, {
    required PredictionGamePlayer player,
  }) async {
    return showDialog<PredictionGamePlayer>(
      context: context,
      builder: (context) => EditPredictionPlayerDialog(
        player: player,
      ),
    );
  }
}

class _EditPredictionPlayerDialogState extends State<EditPredictionPlayerDialog> {
  late TextEditingController _nicknameController;
  late TextEditingController _targetBalanceController;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.player.nickname ?? "");
    _targetBalanceController = TextEditingController(
      text: widget.player.topupTargetBalance?.toStringAsFixed(2) ?? "",
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _targetBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text("Edit Prediction Player"),
      content: SizedBox(
        width: 400 * uiScaleFactor,
        child: Column(
          spacing: 8 * uiScaleFactor,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nicknameController,
              decoration: InputDecoration(labelText: "Nickname"),
            ),
            TextField(
              controller: _targetBalanceController,
              decoration: InputDecoration(labelText: "Target balance"),
              keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]*")),
              ],
            ),
            if(_errorMessage != null)
              Text(_errorMessage!),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          child: Text("SAVE"),
          onPressed: () {
            var nickname = _nicknameController.text.trim();
            var targetBalance = _targetBalanceController.text.trim();

            if(nickname.isEmpty) {
              setState(() {
                _errorMessage = "Nickname is required";
              });
              return;
            }

            double? targetBalanceValue;
            if(targetBalance.isNotEmpty) {
              targetBalanceValue = double.tryParse(targetBalance);
              if(targetBalanceValue == null || targetBalanceValue < 0) {
                setState(() {
                  _errorMessage = "Target balance must be a number greater than or equal to 0";
                });
                return;
              }
            }

            setState(() {
              _errorMessage = null;
            });

            widget.player.nickname = nickname;
            widget.player.topupTargetBalance = targetBalanceValue;

            Navigator.of(context).pop(widget.player);
          },
        )
      ]
    );
  }
}
