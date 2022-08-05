import 'package:flutter/material.dart';

class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({Key? key, this.content}) : super(key: key);

  final Widget? content;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Are you sure?"),
      content: content,
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () { Navigator.of(context).pop(false); },
        ),
        TextButton(
          child: Text("DELETE"),
          onPressed: () { Navigator.of(context).pop(true); },
        )
      ],
    );
  }
}
