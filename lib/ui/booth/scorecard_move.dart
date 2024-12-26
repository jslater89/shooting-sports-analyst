// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/booth/controller.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_model.dart';

class ScorecardMoveDialog extends StatelessWidget {
  const ScorecardMoveDialog({super.key, required this.scorecard, required this.validMoves});

  final ScorecardModel scorecard;
  final List<MoveDirection> validMoves;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Move scorecard"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if(validMoves.contains(MoveDirection.up)) IconButton(
            icon: const Icon(Icons.arrow_upward),
            onPressed: () => Navigator.of(context).pop(MoveDirection.up),
          ),
          if(!validMoves.contains(MoveDirection.up)) Container(),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if(validMoves.contains(MoveDirection.left)) IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(MoveDirection.left),
              ),
              if(!validMoves.contains(MoveDirection.left)) Container(),
              if(validMoves.contains(MoveDirection.right)) IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => Navigator.of(context).pop(MoveDirection.right),
              ),
              if(!validMoves.contains(MoveDirection.right)) Container(),
            ],
          ),
          if(validMoves.contains(MoveDirection.down)) IconButton(
            icon: const Icon(Icons.arrow_downward),
            onPressed: () => Navigator.of(context).pop(MoveDirection.down),
          ),
          if(!validMoves.contains(MoveDirection.down)) Container(),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("CANCEL")),
      ],
    );
  }

  static Future<MoveDirection?> show(BuildContext context, {required ScorecardModel scorecard, required List<MoveDirection> validMoves}) {
    return showDialog<MoveDirection>(
      context: context,
      builder: (context) => ScorecardMoveDialog(scorecard: scorecard, validMoves: validMoves),
    );
  }
}
