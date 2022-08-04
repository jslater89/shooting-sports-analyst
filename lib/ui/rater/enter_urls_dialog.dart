import 'package:flutter/material.dart';

class EnterUrlsDialog extends StatefulWidget {
  const EnterUrlsDialog({Key? key}) : super(key: key);

  @override
  State<EnterUrlsDialog> createState() => _EnterUrlsDialogState();
}

class _EnterUrlsDialogState extends State<EnterUrlsDialog> {
  TextEditingController urlController = TextEditingController();

  String _errorText = "";
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Add Matches"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 600),
          Text("Enter match URLs one per line."),
          Text(_errorText, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).errorColor)),
          Expanded(
            child: SingleChildScrollView(
              child: TextField(
                keyboardType: TextInputType.multiline,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: "https://practiscore.com/results/new/..."
                ),
                controller: urlController,
              ),
            ),
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
            List<String> urls = urlController.text.split("\n");
            if(_validate(urls)) {
              Navigator.of(context).pop(urls);
            }
            else{
              setState(() {
                _errorText = "Some URLs failed to validate.";
              });
            }
          },
        )
      ],
    );
  }

  bool _validate(List<String> urls) {
    for(var url in urls) {
      if(!url.contains("practiscore.com/results/new")) return false;
    }
    return true;
  }
}
