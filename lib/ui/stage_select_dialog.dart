import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';

class StageSelectDialog extends StatefulWidget {
  final Map<Stage, bool?> initialState;

  const StageSelectDialog({Key? key, required this.initialState}) : super(key: key);

  @override
  _StageSelectDialogState createState() => _StageSelectDialogState();
}

class _StageSelectDialogState extends State<StageSelectDialog> {
  late Map<Stage, bool?> state;

  @override
  void initState() {
    state = widget.initialState;
    super.initState();
  }

  void _toggle(Stage s, bool? value) {
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
        (Stage s) => CheckboxListTile(value: state[s], onChanged: (v) => _toggle(s, v), title: Text(s.name),)
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
        FlatButton(
          child: Text("ALL"),
          onPressed: () {
            setState(() {
              state.keys.forEach((stage) => state[stage] = true);
            });

          },
        ),
        FlatButton(
          child: Text("NONE"),
          onPressed: () {
            setState(() {
              state.keys.forEach((stage) => state[stage] = false);
            });
          },
        ),
        SizedBox(width: 50),
        FlatButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop(null);
          },
        ),
        FlatButton(
          child: Text("APPLY"),
          onPressed: () {
            Navigator.of(context).pop(state.keys.toList()..retainWhere((stage) => state[stage]!));
          },
        )
      ],
    );
  }
}
