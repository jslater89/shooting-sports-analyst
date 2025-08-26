/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/db_statistics.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_database_manager_help.dart';
import 'package:shooting_sports_analyst/ui/database/match/match_db_list_view.dart';
import 'package:shooting_sports_analyst/ui/database/stats/db_statistics_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/loading_dialog.dart';

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
        return Scaffold(
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
                      builder: (context) => DbStatisticsDialog(stats: stats),
                    );
                  },
                ),
              ),
              Tooltip(
                message: "Migrate matches from old match cache",
                child: IconButton(
                  icon: Icon(Icons.copy),
                  onPressed: () async {
                    listModel.loading = true;

                    var db = AnalystDatabase();
                    var loadingModel = ProgressModel();
                    var future = db.migrateFromMatchCache((progress, total) async {
                      loadingModel.total = total;
                      loadingModel.current = progress;
                      await Future.delayed(Duration.zero);
                    });
                    await LoadingDialog.show(
                      context: context,
                      waitOn: future,
                      progressProvider: loadingModel,
                    );
                    listModel.search(null);
                  },
                ),
              ),
              HelpButton(helpTopicId: matchDatabaseManagerHelpId),
            ],
          ),
          body: MatchDatabaseListView(),
        );
      }
    );
  }
}
