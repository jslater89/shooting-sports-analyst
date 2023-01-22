import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';

class EnterUrlsDialog extends StatefulWidget {
  const EnterUrlsDialog({
    Key? key, required this.cache, this.existingUrls = const [],
  }) : super(key: key);

  final MatchCache cache;
  final List<String> existingUrls;

  @override
  State<EnterUrlsDialog> createState() => _EnterUrlsDialogState();
}

// TODO: copy member number dialog, start downloading matches here on entry, update display with match names
class _EnterUrlsDialogState extends State<EnterUrlsDialog> {
  TextEditingController urlController = TextEditingController();

  List<String> matchUrls = [];
  Map<String, String> displayNames = {};

  String _errorText = "";
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Add matches"),
      scrollable: true,
      content: SizedBox(
        width: 600,
        child: Container(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Enter match URLs. Press Enter or click the plus button to submit each one."),
              Text(_errorText, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).errorColor)),
              SizedBox(
                width: 500,
                child: TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                      hintText: "https://practiscore.com/results/new/...",
                      suffix: IconButton(
                        icon: Icon(Icons.add),
                        onPressed: () {
                          submit(urlController.text);
                        },
                      )
                  ),
                  onSubmitted: (input) {
                    submit(input);
                  },
                ),
              ),
              SizedBox(height: 8),
              for(var url in matchUrls) SizedBox(
                width: 500,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(child: Text(displayNames[url] ?? url, overflow: TextOverflow.fade)),
                    SizedBox(width: 10),
                    IconButton(
                      icon: Icon(Icons.remove),
                      onPressed: () {
                        setState(() {
                          matchUrls.remove(url);
                        });
                      },
                    )
                  ],
                ),
              ),
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
            Navigator.of(context).pop(matchUrls);
          },
        )
      ],
    );
  }

  void submit(String url) {
    if(!validate(url)) return;

    fetchName(url);
    setState(() {
      displayNames[url] = url;
      matchUrls.add(url);
    });
    urlController.clear();
  }

  void fetchName(String url) async {
    var res = await widget.cache.getMatch(url);
    if(res.isOk()) {
      var match = res.unwrap();
      setState(() {
        displayNames[url] = match.name ?? "$url (missing name)";
      });
    }
    else {
      var err = res.unwrapErr();
      if(err.unrecoverable) {
        var matchId = url
            .split("/")
            .last;
        setState(() {
          displayNames[url] = "URL invalid: ${err.message.toLowerCase()} (id: $matchId)";
        });
      }
    }
  }

  bool validate(String url) {
    if(url.trim().isEmpty || !url.startsWith("http")) {
      setState(() {
        _errorText = "Invalid URL (include https)";
      });
      return false;
    }
    else if(!url.contains("practiscore.com/results/new")) {
      setState(() {
        _errorText = "Invalid URL (must contain 'practiscore.com/results/new')";
      });
      return false;
    }
    else if(matchUrls.contains(url) || widget.existingUrls.contains(url)) {
      setState(() {
        _errorText = "Project already uses match";
      });
      return false;
    }
    else {
      setState(() {
        _errorText = "";
      });
      return true;
    }
  }
}
