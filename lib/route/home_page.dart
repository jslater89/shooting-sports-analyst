import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'package:flutter/foundation.dart';
import 'package:fluttericon/rpg_awesome_icons.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/main.dart';
import 'package:uspsa_result_viewer/route/elo_tuner_page.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/match_cache_chooser_dialog.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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

    var extraActions = <Widget>[];
    if(!kIsWeb && kDebugMode) {
      extraActions.add(Tooltip(
        richMessage: TextSpan(
          children: [
            TextSpan(text: "Stand back! I'm going to try "),
            TextSpan(text: "science!", style: TextStyle(fontStyle: FontStyle.italic)),
          ]
        ),
        child: IconButton(
          icon: Icon(RpgAwesome.bubbling_potion),
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (context) => EloTunerPage()));
          },
        ),
      ));
    }

    return EmptyScaffold(
      title: "Main Menu",
      actions: extraActions,
      operationInProgress: _operationInProgress,
      child: _launchingFromParam ? Center(child: Text("Launching...")) : SizedBox(
        height: size.height,
        width: size.width,
        child: size.width > 800 ? Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _selectButtons(column: false),
            ),
            SizedBox(height: 50),
            if(HtmlOr.isDesktop) _desktopLinks(column: false),
          ],
        ) : SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              ..._selectButtons(column: true),
              if(HtmlOr.isDesktop) _desktopLinks(column: true),
            ]
          ),
        ),
      )
    );
  }

  Widget _desktopLinks({required bool column}) {
    var children = [
      GestureDetector(
        onTap: () async {
          PracticalMatch? match = await showDialog<PracticalMatch>(
            context: context, builder: (context) => MatchCacheChooserDialog(showStats: true, showIds: true),
            barrierDismissible: false,
          );
          if(match != null) {
            Navigator.of(context).push(MaterialPageRoute(builder: (context) => ResultPage(canonicalMatch: match)));
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dataset, size: 230, color: Colors.grey,),
            Text("View and manage matches in the match cache", style: Theme
                .of(context)
                .textTheme
                .subtitle1!
                .apply(color: Colors.grey)),
          ],
        ),
      ),
      GestureDetector(
        onTap: () {
          Navigator.of(context).pushNamed('/rater');
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights, size: 230, color: Colors.grey,),
            Text("Click to generate ratings for shooters in a list of matches", style: Theme
                .of(context)
                .textTheme
                .subtitle1!
                .apply(color: Colors.grey)),
          ],
        ),
      ),
    ];
    if(column) {
      return Column(
        children: [
          ...children,
          SizedBox(height: 50)
        ]
      );
    }
    else {
      return Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children.map((e) => Expanded(child: e)).toList(),
      );
    }
  }

  List<Widget> _selectButtons({bool column = false}) {
    var children = <Widget>[
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
            Text("Click to download a report.txt file from Practiscore", style: Theme
                .of(context)
                .textTheme
                .subtitle1!
                .apply(color: Colors.grey)),
          ],
        ),
      ),
    ];

    if(!column) {
      children = children.map((e) => Expanded(child: e)).toList();
    }

    return children;
  }

  Future<void> _uploadResultsFile(Function(String?) onFileContents) async {
    HtmlOr.pickAndReadFile(context, onFileContents);
  }
}