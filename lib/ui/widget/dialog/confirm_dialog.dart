import 'package:flutter/material.dart';

class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({Key? key, this.content, this.title, this.positiveButtonLabel, this.negativeButtonLabel}) : super(key: key);

  final Widget? content;
  final String? title;
  final String? positiveButtonLabel;
  final String? negativeButtonLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title ?? "Are you sure?"),
      content: content,
      actions: [
        TextButton(
          child: Text(negativeButtonLabel ?? "CANCEL"),
          onPressed: () { Navigator.of(context).pop(false); },
        ),
        TextButton(
          child: Text(positiveButtonLabel ?? "DELETE"),
          onPressed: () { Navigator.of(context).pop(true); },
        )
      ],
    );
  }
}
