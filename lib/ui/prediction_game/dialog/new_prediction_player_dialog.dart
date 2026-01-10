import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';

/// A dialog for creating a new prediction game player. Pops either
/// a PredictionGamePlayer or a tuple of (PredictionGamePlayer, PredictionGameTransaction)
/// depending on [returnInitialTransactionSeparately].
///
/// [predictionGame] is the game this player is participating in.
///
/// [initialBalance] will populate the initial balance field.
///
/// [returnInitialTransactionSeparately] determines whether the initial transaction should be
/// returned separately from the player, or included in the player object. If using synchronous
/// database calls, use [returnInitialTransactionSeparately] = false.
class NewPredictionPlayerDialog extends StatefulWidget {
  const NewPredictionPlayerDialog({
    super.key,
    required this.predictionGame,
    required this.initialBalance,
    this.returnInitialTransactionSeparately = true,
  });

  final PredictionGame predictionGame;
  final double initialBalance;
  final bool returnInitialTransactionSeparately;

  @override
  State<NewPredictionPlayerDialog> createState() => _NewPredictionPlayerDialogState();

  static Future<PredictionGamePlayer?> show(BuildContext context, {
    required PredictionGame predictionGame,
    double initialBalance = 50.0,
    bool returnInitialTransactionSeparately = true,
  }) async {
    return showDialog<PredictionGamePlayer>(
      context: context,
      builder: (context) => NewPredictionPlayerDialog(
        predictionGame: predictionGame,
        initialBalance: initialBalance,
        returnInitialTransactionSeparately: returnInitialTransactionSeparately,
      ),
    );
  }
}

class _NewPredictionPlayerDialogState extends State<NewPredictionPlayerDialog> {
  late TextEditingController _nameController;
  late TextEditingController _balanceController;

  String? _errorMessage;


  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _balanceController = TextEditingController(text: widget.initialBalance.toStringAsFixed(2));
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text("New prediction player"),
      content: SizedBox(
        width: 400 * uiScaleFactor,
        child: Column(
          spacing: 8 * uiScaleFactor,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: "Name"),
            ),
            TextField(
              controller: _balanceController,
              decoration: InputDecoration(labelText: "Balance"),
              keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]*")),
              ],
            ),
            // TODO: select server user
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          child: Text("SAVE"),
          onPressed: () {
            var name = _nameController.text.trim();
            var balance = double.tryParse(_balanceController.text);
            if(name.isEmpty || balance == null || balance < 0) {
              return;
            }
            var predictionPlayer = PredictionGamePlayer();
            predictionPlayer.nickname = name;
            predictionPlayer.balance = balance;
            predictionPlayer.game.value = widget.predictionGame;

            var initialTransaction = PredictionGameTransaction(
              type: PredictionGameTransactionType.topUp,
              amount: balance,
              created: DateTime.now(),
            );
            initialTransaction.game.value = widget.predictionGame;

            if(widget.returnInitialTransactionSeparately) {
              Navigator.of(context).pop((predictionPlayer, initialTransaction));
            }
            else {
              predictionPlayer.transactions.add(initialTransaction);
              Navigator.of(context).pop(predictionPlayer);
            }
          },
        )
      ]
    );
  }
}