/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/db_statistics.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_database_manager_help.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/database/match/match_db_list_view.dart';
import 'package:shooting_sports_analyst/ui/database/stats/db_statistics_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/loading_dialog.dart';
import 'package:shooting_sports_analyst/ui/workspace/workspace_label_reporter.dart';
import 'package:url_launcher/url_launcher.dart';

final _log = SSALogger("MatchDatabaseManagerPage");

class MatchDatabaseManagerPage extends StatefulWidget {
  const MatchDatabaseManagerPage({super.key});

  @override
  State<MatchDatabaseManagerPage> createState() => _MatchDatabaseManagerPageState();
}

class _MatchDatabaseManagerPageState extends State<MatchDatabaseManagerPage> {
  var listModel = MatchDatabaseListModel();
  var searchModel = MatchDatabaseSearchModel();

  @override
  void initState() {
    super.initState();

    searchModel.addListener(() {
      listModel.search(searchModel);
    });
    listModel.search(null);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: searchModel),
        ChangeNotifierProvider.value(value: listModel),
      ],
      builder: (context, child) {
        return WorkspaceLabelReporter(
          section: "Database",
          child: Scaffold(
          appBar: AppBar(
            title: Text("Match Database"),
            centerTitle: true,
            actions: [
              Tooltip(
                message: "Show database statistics",
                child: IconButton(
                  icon: Icon(Icons.auto_graph),
                  onPressed: () async {
                    var db = AnalystDatabase();
                    var stats = await db.getBasicDatabaseStatistics();
                    showDialog(
                      context: context,
                      useRootNavigator: false,
                      builder: (context) => DbStatisticsDialog(stats: stats),
                    );
                  },
                ),
              ),
              Tooltip(
                message: "Back up database to file",
                child: IconButton(
                  icon: Icon(Icons.copy),
                  onPressed: () async {
                    final now = DateFormat("yyyy-MM-dd-HH-mm").format(DateTime.now());
                    final fileChoice = await FilePicker.saveFile(
                      dialogTitle: "Backup path",
                      fileName: "analyst-$now.isar",
                      initialDirectory: Directory.current.path,
                    );
                    if(fileChoice != null) {
                      _log.i("Backup file choice: $fileChoice");
                      final backupFile = File(fileChoice);
                      final backupDir = backupFile.parent;
                      final filename = basename(backupFile.path);
                      _log.d("Backup dir: $backupDir, filename: $filename");
                      final db = AnalystDatabase();

                      final start = DateTime.now();
                      final dbFuture = db.saveBackup(backupDir, filename: filename);
                      await LoadingDialog.show(context: context, waitOn: dbFuture, title: "Saving backup...");
                      final end = DateTime.now();
                      _log.i("Backup took ${end.difference(start).inMilliseconds} milliseconds");

                      final uri = Uri.file(backupDir.path);
                      final canLaunchFile = await canLaunchUrl(uri);
                      _log.d("Can launch $uri: $canLaunchFile");
                      final action = canLaunchFile ? SnackBarAction(
                        label: "Open",
                        onPressed: () {
                          launchUrl(uri);
                        },
                      ) : null;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text("Backup saved to ${backupFile.path}"),
                        action: action,
                      ));
                    }
                  },
                ),
              ),
              HelpButton(helpTopicId: matchDatabaseManagerHelpId),
            ],
          ),
          body: MatchDatabaseListView(),
        ),
        );
      }
    );
  }
}
