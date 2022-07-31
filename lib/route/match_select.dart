import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'package:uspsa_result_viewer/html_or/html_or.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/main.dart';
import 'package:uspsa_result_viewer/route/practiscore_url.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';

class MatchSelectPage extends StatefulWidget {
  @override
  _MatchSelectPageState createState() => _MatchSelectPageState();
}

class _MatchSelectPageState extends State<MatchSelectPage> {
  late BuildContext _innerContext;
  bool _operationInProgress = false;
  bool _launchingFromParam = false;

  @override
  void initState() {
    super.initState();

    if(globals.practiscoreId != null) {
      _launchingFromParam = true;
      _launchPresetPractiscore(url: "https://practiscore.com/results/new/${globals.practiscoreId}");
    }
    else if(globals.practiscoreUrl != null) {
      _launchingFromParam = true;
      _launchPresetPractiscore(url: globals.practiscoreUrl);
    }
    else if(globals.resultsFileUrl != null) {
      _launchingFromParam = true;
      _launchNonPractiscoreFile(url: globals.resultsFileUrl!);
    }
  }

  void _launchPresetPractiscore({String? url}) async {
    var matchId = await _getMatchId(presetUrl: url);
    if(matchId != null) {
      HtmlOr.navigateTo(context, "/web/$matchId");
    }
  }

  void _launchNonPractiscoreFile({required String url}) async {
    var urlBytes = Base64Codec.urlSafe().encode(url.codeUnits);
    HtmlOr.navigateTo(context, "/webfile/$urlBytes");
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    return EmptyScaffold(
      operationInProgress: _operationInProgress,
      onInnerContextAssigned: (context) {
        _innerContext = context;
      },
      child: _launchingFromParam ? Center(child: Text("Launching...")) : SizedBox(
        height: size.height,
        width: size.width,
        child: size.width > 750 ? Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _selectButtons(column: false),
            ),
            SizedBox(height: 50),
            GestureDetector(
              child: Column(
                children: [
                  Icon(Icons.list, size: 230, color: Colors.grey,),
                  Text("Click to generate ratings for shooters in a list of matches", style: Theme
                      .of(context)
                      .textTheme
                      .subtitle1!
                      .apply(color: Colors.grey)),
                ],
              ),
            )
          ],
        ) : SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              ..._selectButtons(column: true),
              GestureDetector(
                onTap: () {

                },
                child: Column(
                  children: [
                    Icon(Icons.list, size: 230, color: Colors.grey,),
                    Text("Click to generate ratings for shooters in a list of matches", style: Theme
                        .of(context)
                        .textTheme
                        .subtitle1!
                        .apply(color: Colors.grey)),
                  ],
                ),
              )
            ]
          ),
        ),
      )
    );
  }

  List<Widget> _selectButtons({bool column = false}) {
    return [
      GestureDetector(
        onTap: () async {
          _uploadResultsFile((contents) async {
            if(contents != null) {
              await Navigator.of(context).pushNamed('/local', arguments: contents);
            }
            else {
              debugPrint("Null file contents");
            }
          });
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: column ? 0 : 150),
            Icon(Icons.cloud_upload, size: 230, color: Colors.grey,),
            Text("Click to upload a report.txt file from your device", style: Theme
                .of(context)
                .textTheme
                .subtitle1!
                .apply(color: Colors.grey)),
          ],
        ),
      ),
      GestureDetector(
        onTap: () async {
          setState(() {
            _operationInProgress = true;
          });
          var matchId = await _getMatchId();
          setState(() {
            _operationInProgress = false;
          });

          if(matchId != null) {
            await Navigator.of(context).pushNamed('/web/$matchId');
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: column ? 0 : 150),
            Icon(Icons.cloud_download, size: 230, color: Colors.grey,),
            Text("Click to download a report.txt file from PractiScore", style: Theme
                .of(context)
                .textTheme
                .subtitle1!
                .apply(color: Colors.grey)),
          ],
        ),
      ),
    ];
  }

  Future<void> _uploadResultsFile(Function(String?) onFileContents) async {
    HtmlOr.pickAndReadFile(context, onFileContents);
  }

  Future<String?> _getMatchId({String? presetUrl}) async {
    var matchUrl = presetUrl ?? await showDialog<String>(context: context, builder: (context) {
      var controller = TextEditingController();
      return AlertDialog(
        title: Text("Enter PractiScore match URL"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Copy the URL to the match's PractiScore results page and paste it in the field below.",
              softWrap: true,),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "https://practiscore.com/results/new/...",
              ),
            ),
          ],
        ),
        actions: [
          FlatButton(
              child: Text("CANCEL"),
              onPressed: () {
                Navigator.of(context).pop();
              }
          ),
          FlatButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.of(context).pop(controller.text);
              }
          ),
        ],
      );
    });

    if(matchUrl == null) {
      return null;
    }

    var matchId = processMatchUrl(matchUrl, context: _innerContext);

    return matchId;
  }
}