/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/ui/matchdb/match_db_list_view.dart';

class MatchDbSelectDialog extends StatefulWidget {
  const MatchDbSelectDialog({Key? key}) : super(key: key);

  @override
  State<MatchDbSelectDialog> createState() => _MatchDbSelectDialogState();


  static Future<ShootingMatch?> show(BuildContext context) async {
    return showDialog<ShootingMatch>(context: context, builder: (context) => MatchDbSelectDialog(), barrierDismissible: false);
  }
}

class _MatchDbSelectDialogState extends State<MatchDbSelectDialog> {
  final listModel = MatchDatabaseListModel();
  final searchModel = MatchDatabaseSearchModel();

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
    return AlertDialog(
      title: Text(
        "Select a match",
      ),
      content: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: searchModel),
          ChangeNotifierProvider.value(value: listModel),
        ],
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Expanded(
                child: MatchDatabaseListView(
                  flat: true,
                  onMatchSelected: (match) {
                    Navigator.of(context).pop(match);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("CANCEL"),
        ),
      ],
    );
  }
}
