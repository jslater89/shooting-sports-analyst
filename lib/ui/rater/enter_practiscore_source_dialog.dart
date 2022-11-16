import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/parser/score_list_parser.dart';

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
      title: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Add Matches From HTML Source"),
          IconButton(
            icon: Icon(Icons.help),
            onPressed: () {
              showDialog(context: context, builder: (context) => AlertDialog(
                title: Text("How-to"),
                content: Text(
                  "Open a Practiscore page, copy the HTML source code, and paste into the text field.\n"
                      "Most pages will require the following steps to view source.\n\n"
                      "Firefox:\n"
                      "\t1. Ctrl+A\n"
                      "\t2. Right click -> View Selection Source\n\n"
                      "Chrome:\n"
                      "\t1. Right click near the result links -> Inspect\n"
                      "\t2. Expand and mouse over HTML elements until the result list is highlighted\n"
                      "\t3. Right click on the HTML element that encloses the result list\n"
                      "\t4. Copy -> Element\n"
                ),
                actions: [
                  TextButton(
                    child: Text("OK"),
                    onPressed: Navigator.of(context).pop,
                  )
                ],
              ));
            },
          )
        ],
      ),
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
