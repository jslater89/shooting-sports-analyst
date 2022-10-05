import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_test.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/main.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';

class MatchSelectPage extends StatefulWidget {
  @override
  _MatchSelectPageState createState() => _MatchSelectPageState();
}

class _MatchSelectPageState extends State<MatchSelectPage> {
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
    var matchId = await getMatchId(context, presetUrl: url);
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
      title: "Main Menu",
      operationInProgress: _operationInProgress,
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
            if(HtmlOr.isDesktop) _raterLink(),
          ],
        ) : SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              ..._selectButtons(column: true),
              if(HtmlOr.isDesktop) _raterLink(),
            ]
          ),
        ),
      )
    );
  }

  Widget _raterLink() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pushNamed('/rater');
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.list, size: 230, color: Colors.grey,),
          Text("Click to generate ratings for shooters in a list of matches", style: Theme
              .of(context)
              .textTheme
              .subtitle1!
              .apply(color: Colors.grey)),
        ],
      ),
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
            SizedBox(height: column ? 0 : 50),
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
          var matchId = await getMatchId(context);
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
            SizedBox(height: column ? 0 : 50),
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
}