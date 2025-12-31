/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';

/// MatchPrepList is a database-backed list of match prep(s).
///
/// Requires a [MatchPrepListModel] to be provided.
class MatchPrepList extends StatefulWidget {
  const MatchPrepList({super.key});

  @override
  State<MatchPrepList> createState() => _MatchPrepListState();
}

class _MatchPrepListState extends State<MatchPrepList> {
  final model = MatchPrepListModel();

  @override
  void initState() {
    super.initState();
    model.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
        itemBuilder: (context, index) => ListTile(
        title: Text(model.matchPreps[index].futureMatch.value!.eventName),
      ),
    );
  }
}


class MatchPrepListModel extends ChangeNotifier {
  final db = AnalystDatabase();
  List<MatchPrep> matchPreps = [];

  Future<void> load() async {
    matchPreps = await db.getMatchPreps();
    notifyListeners();
  }
}