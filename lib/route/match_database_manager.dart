/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uspsa_result_viewer/data/database/match_database.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/sport/match/translator.dart';
import 'package:uspsa_result_viewer/ui/widget/matchdb/match_db_list_view.dart';

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
              IconButton(
                icon: Icon(Icons.copy),
                onPressed: () async {
                  listModel.loading = true;

                  var db = MatchDatabase();
                  db.migrateFromCache((progress, total) async {
                    print("Did a thing");
                  });
                  listModel.search(null);
                },
              )
            ],
          ),
          body: MatchDatabaseListView(),
        );
      }
    );
  }
}
