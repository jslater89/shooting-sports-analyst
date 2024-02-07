/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';

class StageSelectDialog extends StatefulWidget {
  final Map<MatchStage, bool?> initialState;

  const StageSelectDialog({Key? key, required this.initialState}) : super(key: key);

  @override
  _StageSelectDialogState createState() => _StageSelectDialogState();
}

class _StageSelectDialogState extends State<StageSelectDialog> {
  late Map<MatchStage, bool?> state;

  @override
  void initState() {
    state = widget.initialState;
    super.initState();
  }

  void _toggle(MatchStage s, bool? value) {
    setState(() {
      state[s] = value;
    });
    //debugPrint("Filtered stages: $state");
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [
      Text("Select stages to include in scoring."),
      SizedBox(height: 10),
    ]..addAll(
      state.keys.map(
        (MatchStage s) => CheckboxListTile(value: state[s], onChanged: (v) => _toggle(s, v), title: Text(s.name),)
      )
    );

    return AlertDialog(
      title: Text("Select Stages"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
      actions: [
        TextButton(
          child: Text("ALL"),
          onPressed: () {
            setState(() {
              state.keys.forEach((stage) => state[stage] = true);
            });

          },
        ),
        TextButton(
          child: Text("NONE"),
          onPressed: () {
            setState(() {
              state.keys.forEach((stage) => state[stage] = false);
            });
          },
        ),
        SizedBox(width: 50),
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop(null);
          },
        ),
        TextButton(
          child: Text("APPLY"),
          onPressed: () {
            Navigator.of(context).pop(state.keys.toList()..retainWhere((stage) => state[stage]!));
          },
        )
      ],
    );
  }
}
