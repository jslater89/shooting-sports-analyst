import 'package:flutter/material.dart';

class EnterUrlsDialog extends StatefulWidget {
  const EnterUrlsDialog({Key? key}) : super(key: key);

  @override
  State<EnterUrlsDialog> createState() => _EnterUrlsDialogState();
}

class _EnterUrlsDialogState extends State<EnterUrlsDialog> {
  TextEditingController urlController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Add Matches"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 600),
          Text("Enter match URLs one per line."),
          TextField(
            keyboardType: TextInputType.multiline,
            maxLines: null,
            decoration: InputDecoration(

            ),
            controller: urlController,
          )
        ],
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop(<String>[]);
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () {
            Navigator.of(context).pop(<String>[]);
          },
        )
      ],
    );
  }
}
