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
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/route/match_prep_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

/// MatchPrepList is a database-backed list of match prep(s).
///
/// Requires a [MatchPrepListModel] to be provided.
class MatchPrepList extends StatefulWidget {
  MatchPrepList({super.key, this.onMatchPrepSelected});

  /// A callback to be called when a match prep row is clicked.
  final void Function(MatchPrep)? onMatchPrepSelected;

  @override
  State<MatchPrepList> createState() => _MatchPrepListState();
}

class _MatchPrepListState extends State<MatchPrepList> {
  @override
  void initState() {
    super.initState();
  }

  static const _nameFlex = 3;
  static const _dateFlex = 1;

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchPrepListModel>(
      builder: (context, model, child) => ListView.separated(
        itemCount: model.matchPreps.length,
        separatorBuilder: (context, index) => Divider(),
        itemBuilder: (context, index) {
          var prep = model.matchPreps[index];
          return ListTile(
            title: Row(
              children: [
                Expanded(flex: _nameFlex, child: Text(prep.futureMatch.value!.eventName)),
                Expanded(flex: _dateFlex, child: Text(programmerYmdFormat.format(prep.matchDate))),
              ],
            ),
            subtitle: Text(prep.ratingProject.value!.name),
            onTap: () {
              if(widget.onMatchPrepSelected != null) {
                widget.onMatchPrepSelected!(prep);
              }
              else {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => MatchPrepPage(prep: prep)));
              }
            },
            trailing: IconButton(
              icon: Icon(Icons.delete),
              onPressed: () async {
                var confirm = await ConfirmDialog.show(context, title: "Delete match prep", content: Text("Are you sure you want to delete this match prep?"));
                if(confirm ?? false) {
                  final result = await model.deleteMatchPrep(prep);
                  if(result.isOk()) {
                    model.load();
                  }
                  else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unable to delete: ${result.unwrapErr().message}")));
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }
}


class MatchPrepListModel extends ChangeNotifier {
  MatchPrepListModel({this.singleProject});

  final DbRatingProject? singleProject;
  final db = AnalystDatabase();
  List<MatchPrep> matchPreps = [];

  Future<void> load() async {
    matchPreps = await db.getMatchPreps(singleProject: singleProject);
    notifyListeners();
  }

  Future<Result<void, ResultErr>> deleteMatchPrep(MatchPrep matchPrep) async {
    final result = await db.deleteMatchPrep(matchPrep);
    if(result.isOk()) {
      matchPreps.remove(matchPrep);
      notifyListeners();
      return Result.ok(null);
    }
    else {
      return Result.errFrom(result);
    }
  }
}