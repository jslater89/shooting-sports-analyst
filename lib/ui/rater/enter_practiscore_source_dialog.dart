import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/score_list_parser.dart';

class EnterPractiscoreSourceDialog extends StatefulWidget {
  const EnterPractiscoreSourceDialog({Key? key}) : super(key: key);

  @override
  State<EnterPractiscoreSourceDialog> createState() => _EnterPractiscoreSourceDialogState();
}

class _EnterPractiscoreSourceDialogState extends State<EnterPractiscoreSourceDialog> {
  TextEditingController sourceController = TextEditingController();

  String _errorText = "";
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Add Matches From HTML Source"),
      content: SizedBox(
        width: 600,
        child: Container(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              
              Text(_errorText, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).errorColor)),
              Expanded(
                child: SingleChildScrollView(
                  child: TextField(
                    keyboardType: TextInputType.multiline,
                    maxLines: null,
                    decoration: InputDecoration(
                        hintText: "Paste page source here"
                    ),
                    controller: sourceController,
                  ),
                ),
              )
            ],
          ),
        ),
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
            var text = sourceController.text;
            List<String> urls = getMatchResultLinksFromHtml(text);
            List<String> goodUrls = _validate(urls);
            if(goodUrls.length > 0) {
              Navigator.of(context).pop(goodUrls);
            }
            else{
              setState(() {
                _errorText = "No URLs found.";
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
