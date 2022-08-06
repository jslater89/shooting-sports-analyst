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
            var text = urlController.text.replaceAll("\r","");
            List<String> urls = text.split("\n").map((url) => url.trim()).toList();
            List<String> goodUrls = _validate(urls);
            if(goodUrls.length > 0) {
              Navigator.of(context).pop(goodUrls);
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

  List<String> _validate(List<String> urls) {
    List<String> goodUrls = [];
    for(var url in urls) {
      if(url.trim().isEmpty || !url.startsWith("http")) {
        debugPrint("Skipping non-URL $url");
        continue;
      }
      else if(url.contains("practiscore.com/results/new")) goodUrls.add(url);
      else debugPrint("Bad URL: $url");
    }
    return goodUrls;
  }
}
