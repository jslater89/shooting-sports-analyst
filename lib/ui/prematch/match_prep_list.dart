/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/route/match_prep_page.dart';
import 'package:shooting_sports_analyst/util.dart';

/// MatchPrepList is a database-backed list of match prep(s).
///
/// Requires a [MatchPrepListModel] to be provided.
class MatchPrepList extends StatefulWidget {
  MatchPrepList({super.key, this.onMatchPrepSelected});

  final void Function(MatchPrep)? onMatchPrepSelected;

  @override
  State<MatchPrepList> createState() => _MatchPrepListState();
}

class _MatchPrepListState extends State<MatchPrepList> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchPrepListModel>(
      builder: (context, model, child) => ListView.builder(
        itemCount: model.matchPreps.length,
        itemBuilder: (context, index) {
          var prep = model.matchPreps[index];
          return ListTile(
            title: Text(prep.futureMatch.value!.eventName),
            subtitle: Text("${programmerYmdFormat.format(prep.matchDate)} - ${prep.ratingProject.value!.name}"),
            onTap: () {
              if(widget.onMatchPrepSelected != null) {
                widget.onMatchPrepSelected!(prep);
              }
              else {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => MatchPrepPage(prep: prep)));
              }
            },
          );
        },
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