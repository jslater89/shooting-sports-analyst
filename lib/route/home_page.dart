/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/application_preferences.dart';
import 'package:shooting_sports_analyst/data/database/extensions/future_match.dart';
import 'package:shooting_sports_analyst/data/help/help_registry.dart';
import 'package:shooting_sports_analyst/data/help/welcome_dialogs.dart';
import 'package:shooting_sports_analyst/data/source/prematch/future_match_source_registry.dart';
import 'package:shooting_sports_analyst/data/source/match_source_registry.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/main.dart';
import 'package:shooting_sports_analyst/route/broadcast_booth_page.dart';
import 'package:shooting_sports_analyst/route/match_database_manager.dart';
import 'package:shooting_sports_analyst/route/match_prep_list_page.dart';
import 'package:shooting_sports_analyst/route/practiscore_url.dart';
import 'package:shooting_sports_analyst/route/prediction_game_list_page.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/app_settings.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_file_import_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_or_future_match_source_chooser_dialog.dart';

var _log = SSALogger("HomePage");

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

    Future.delayed(Duration.zero, () {
      _showWelcomeDialog();
    });
  }

  void _showWelcomeDialog() {
    var prefs = AnalystDatabase().getPreferencesSync();
    final resolvedWelcomeDialog = WelcomeDialogEntry.resolve(
      welcome80: prefs.welcome80Shown,
      welcome80Beta: prefs.welcome80BetaShown,
      welcome100: prefs.welcome100Shown,
    );

    if(resolvedWelcomeDialog != null) {
      final hasHelpTopic = HelpTopicRegistry().getTopic(resolvedWelcomeDialog.helpId) != null;
      if(!hasHelpTopic) {
        _log.w("No help topic found for welcome dialog ${resolvedWelcomeDialog.humanVersion}, skipping");
        return;
      }
      _log.i("Showing ${resolvedWelcomeDialog.humanVersion} welcome dialog");
      WelcomeDialogEntry.markShown(prefs, resolvedWelcomeDialog);
      AnalystDatabase().savePreferencesSync(prefs);
      HelpDialog.show(context, initialTopic: resolvedWelcomeDialog.helpId);
    }
  }

  void _launchPresetPractiscore({String? url}) async {
    // var matchId = await getMatchId(context, presetUrl: url);
    //if(matchId != null) {
    //  HtmlOr.navigateTo(context, "/web/report-uspsa/$matchId");
    //}
  }

  void _launchNonPractiscoreFile({required String url}) async {
    var urlBytes = Base64Codec.urlSafe().encode(url.codeUnits);
    HtmlOr.navigateTo(context, "/webfile/report-uspsa/$urlBytes");
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    var extraActions = <Widget>[
      Tooltip(
        message: "Open app settings",
        child: IconButton(
          icon: Icon(Icons.settings),
          onPressed: () async {
            var config = await AppSettingsDialog.show(context);
            if(config != null) {
              ChangeNotifierConfigLoader().setConfigs(config);
            }
          },
        ),
      ),
    ];
    // if(!kIsWeb && kDebugMode) {
    //   extraActions.add(Tooltip(
    //     richMessage: TextSpan(
    //       children: [
    //         TextSpan(text: "Stand back! I'm going to try "),
    //         TextSpan(text: "science!", style: TextStyle(fontStyle: FontStyle.italic)),
    //       ]
    //     ),
    //     child: IconButton(
    //       icon: Icon(RpgAwesome.bubbling_potion),
    //       onPressed: () {
    //         Navigator.of(context).push(MaterialPageRoute(builder: (context) => MatchHeatGraphPage(project)));
    //       },
    //     ),
    //   ));
    // }

    return EmptyScaffold(
      title: "Main Menu",
      actions: extraActions,
      operationInProgress: _operationInProgress,
      child: _launchingFromParam ? Center(child: Text("Launching...")) : SizedBox(
        height: size.height,
        width: size.width,
        child: size.width > 800 ? Padding(
          padding: const EdgeInsets.all(8.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 30),
                Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _selectButtons(column: false),
                ),
                SizedBox(height: 60),
                if(HtmlOr.isDesktop) _desktopLinks(column: false),
                if(HtmlOr.isDesktop) SizedBox(height: 60),
                if(HtmlOr.isDesktop) ..._additionalLinks(column: false),
                SizedBox(height: 30),
              ],
            ),
          ),
        ) : SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              ..._selectButtons(column: true),
              if(HtmlOr.isDesktop) _desktopLinks(column: true),
              if(HtmlOr.isDesktop) ..._additionalLinks(column: true)
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
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => MatchDatabaseManagerPage()));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dataset, size: 230, color: Colors.grey,),
            Text("View and manage matches in the match database", style: Theme
                .of(context)
                .textTheme
                .titleMedium!
                .apply(color: Colors.grey),
                textAlign: TextAlign.center,
                ),
          ],
        ),
      ),
      GestureDetector(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => BroadcastBoothPage(match: null)));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cell_tower, size: 230, color: Colors.grey,),
            Text("Enter broadcast mode", style: Theme
                .of(context)
                .textTheme
                .titleMedium!
                .apply(color: Colors.grey),
                textAlign: TextAlign.center,
                ),
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
            Text("Generate ratings for shooters in a list of matches", style: Theme
                .of(context)
                .textTheme
                .titleMedium!
                .apply(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
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
      return Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children.map((e) => Expanded(child: e)).toList(),
          ),
        ],
      );
    }
  }

  List<Widget> _additionalLinks({required bool column}) {
    var children = <Widget>[
      GestureDetector(
        onTap: () async {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => PredictionGameListPage()));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_score, size: 230, color: Colors.grey,),
            Text("View prediction games", style: Theme
                .of(context)
                .textTheme
                .titleMedium!
                .apply(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    ];

    return children;
  }

  List<Widget> _selectButtons({bool column = false}) {
    var children = <Widget>[
      GestureDetector(
        onTap: () async {
          await MatchFileImportDialog.show(context);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.save_alt, size: 230, color: Colors.grey,),
            Text("Import a match file from your device", style: Theme
                .of(context)
                .textTheme
                .titleMedium!
                .apply(color: Colors.grey),
                textAlign: TextAlign.center,
                ),
          ],
        ),
      ),
      GestureDetector(
        onTap: () async {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => MatchPrepListPage()));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 230, color: Colors.grey,),
            Text("Prepare for a future match", style: Theme
                .of(context)
                .textTheme
                .titleMedium!
                .apply(color: Colors.grey),
                textAlign: TextAlign.center,
                ),
          ],
        ),
      ),

      GestureDetector(
        onTap: () async {
          var response = await MatchOrFutureMatchSourceChooserDialog.show(
            context: context,
            matchSources: MatchSourceRegistry().sources,
            futureMatchSources: FutureMatchSourceRegistry().sources,
          );
          if(response == null) {
            return;
          }
          var matchOrFutureMatch = response;
          if(matchOrFutureMatch.isMatch()) {
            var (source, match) = matchOrFutureMatch.unwrapMatch();
            Navigator.of(context).push(MaterialPageRoute(builder: (context) => PractiscoreResultPage(match: match, sourceId: source.code)));
          }
          else {
            var futureMatch = matchOrFutureMatch.unwrapFutureMatch();
            await AnalystDatabase().saveFutureMatch(futureMatch);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Downloaded future match ${futureMatch.eventName}")));
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_download, size: 230, color: Colors.grey,),
            Text("Download matches from Internet sources", style: Theme
                .of(context)
                .textTheme
                .titleMedium!
                .apply(color: Colors.grey),
                textAlign: TextAlign.center,
                ),
          ],
        ),
      ),
    ];

    if(!column) {
      children = children.map((e) => Expanded(child: e)).toList();
    }

    return children;
  }
}
