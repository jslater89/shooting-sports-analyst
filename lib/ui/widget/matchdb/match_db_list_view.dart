/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uspsa_result_viewer/data/database/match_database.dart';
import 'package:uspsa_result_viewer/data/database/schema/match.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:uspsa_result_viewer/ui/widget/score_row.dart';
import 'package:uspsa_result_viewer/util.dart';

class MatchDatabaseListView extends StatefulWidget {
  const MatchDatabaseListView({super.key});

  @override
  State<MatchDatabaseListView> createState() => _MatchDatabaseListViewState();
}

class _MatchDatabaseListViewState extends State<MatchDatabaseListView> {
  static const _flexPadding = 1;
  static const _nameFlex = 8;
  static const _dateFlex = 1;
  static const _levelFlex = 1;
  static const _sportFlex = 1;

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchDatabaseListModel>(
      builder: (context, listModel, child) {
        if(listModel.loading) {
          return Center(child: Text("Loading..."));
        }
        return Column(
          children: [
            _header(),
            Expanded(
              child: ListView.builder(
                itemBuilder: (context, i) {
                  var match = listModel.searchedMatches[i];
                  return GestureDetector(
                    onTap: () {
                      var fullMatchResult = match.hydrate();
                      if(fullMatchResult.isErr()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Unable to load match from database"))
                        );
                        print("match db error: ${fullMatchResult.unwrapErr().message}");
                        return;
                      }
                      Navigator.of(context).push(MaterialPageRoute(builder: (context) =>
                          ResultPage(
                            canonicalMatch: fullMatchResult.unwrap(),
                            allowWhatIf: true,
                          ),
                      ));
                    },
                    child: ScoreRow(
                      index: i,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: Row(
                          children: [
                            Expanded(flex: _flexPadding, child: Container()),
                            Expanded(flex: _sportFlex, child: Text(match.sportName)),
                            Expanded(flex: _nameFlex, child: Text(match.eventName)),
                            Expanded(flex: _dateFlex, child: Text(programmerYmdFormat.format(match.date))),
                            Expanded(flex: _levelFlex, child: Text(match.matchLevelName ?? "")),
                            Expanded(flex: _flexPadding, child: Container()),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                itemCount: listModel.searchedMatches.length,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(),
        )
      ),
      child: ScoreRow(
        bold: false,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: Row(
            children: [
              Expanded(flex: _flexPadding, child: Container()),
              Expanded(flex: _sportFlex, child: Text("Sport")),
              Expanded(flex: _nameFlex, child: Text("Event Name")),
              Expanded(flex: _dateFlex, child: Text("Date")),
              Expanded(flex: _levelFlex, child: Text("Event Level")),
              Expanded(flex: _flexPadding, child: Container()),
            ],
          ),
        ),
      ),
    );
  }
}

class MatchDatabaseSearchModel extends ChangeNotifier {
  MatchDatabaseSearchModel();

  String? name;
  DateTime? before;
  DateTime? after;
}

class MatchDatabaseListModel extends ChangeNotifier {
  MatchDatabaseListModel() : matchDb = MatchDatabase();

  List<DbShootingMatch> searchedMatches = [];
  bool _loading = false;
  bool get loading => _loading;
  set loading(bool v) {
    _loading = v;
    notifyListeners();
  }

  MatchDatabase matchDb;

  Future<void> search(MatchDatabaseSearchModel? search) async {
    _loading = true;
    notifyListeners();

    var newMatches = await matchDb.query(
      name: search?.name,
      before: search?.before,
      after: search?.after,
    );

    _loading = false;
    searchedMatches = newMatches;
    notifyListeners();
  }

}