/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/database/match/widget/match_db_list_view_search.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("MatchDbListView");

class MatchDatabaseListView extends StatefulWidget {
  const MatchDatabaseListView({super.key, this.onMatchSelected, this.flat = false});

  final bool flat;

  /// If provided, this function will be called when a match is selected, instead
  /// of navigating to the result page for that match.
  final void Function(ShootingMatch)? onMatchSelected;

  @override
  State<MatchDatabaseListView> createState() => _MatchDatabaseListViewState();
}

class _MatchDatabaseListViewState extends State<MatchDatabaseListView> {
  static const _flexPadding = 1;
  static const _nameFlex = 8;
  static const _dateFlex = 1;
  static const _levelFlex = 1;
  static const _sportFlex = 1;

  late ScrollController _listController;
  @override
  void initState() {
    super.initState();
    _listController = ScrollController();
    _listController.addListener(() {
      if(!mounted) return;

      var position = _listController.position;
      if(position.hasContentDimensions && position.atEdge && position.pixels != 0) {
        Provider.of<MatchDatabaseListModel>(context, listen: false).loadMore();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _listController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchDatabaseListModel>(
      builder: (context, listModel, child) {
        return Column(
          children: [
            MatchDbListViewSearch(flat: widget.flat),
            _tableHeader(),
            Expanded(
              child: ListView.builder(
                controller: _listController,
                itemBuilder: (context, i) {
                  var match = listModel.searchedMatches[i];
                  return GestureDetector(
                    onTap: () async {
                      var fullMatchResult = match.hydrate();
                      if(fullMatchResult.isErr()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Unable to load match from database"))
                        );
                        _log.w("match db error: ${fullMatchResult.unwrapErr().message}");
                        return;
                      }

                      if(widget.onMatchSelected != null) {
                        widget.onMatchSelected!(fullMatchResult.unwrap());
                      }
                      else {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (context) =>
                          ResultPage(
                            canonicalMatch: fullMatchResult.unwrap(),
                            allowWhatIf: true,
                          ),
                        ));
                      }
                      // TODO: refresh list in case we pulled new match information with a refresh
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

  Widget _tableHeader() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(),
        )
      ),
      child: ScoreRow(
        bold: false,
        hoverEnabled: false,
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

  void changed() {
    notifyListeners();
  }

  void reset() {
    name = null;
    before = null;
    after = null;
    notifyListeners();
  }
}

class MatchDatabaseListModel extends ChangeNotifier {
  MatchDatabaseListModel() : matchDb = AnalystDatabase();

  List<DbShootingMatch> searchedMatches = [];

  MatchDatabaseSearchModel? _currentSearch;
  bool _hasMore = true;
  int _page = 0;

  bool _loading = false;
  bool get loading => _loading;
  set loading(bool v) {
    _loading = v;
    notifyListeners();
  }

  AnalystDatabase matchDb;

  Future<void> search(MatchDatabaseSearchModel? search) async {
    if(loading) return;

    _currentSearch = search;
    _page = 0;
    _hasMore = true;
    loading = true;

    var newMatches = await matchDb.queryMatches(
      name: search?.name,
      before: search?.before,
      after: search?.after,
    );

    searchedMatches = newMatches;
    loading = false;
  }

  Future<void> loadMore() async {
    if(!_hasMore || loading) return;

    loading = true;

    _page += 1;
    var newMatches = await matchDb.queryMatches(
      name: _currentSearch?.name,
      before: _currentSearch?.before,
      after: _currentSearch?.after,
      page: _page,
    );

    if(newMatches.isEmpty) {
      _log.v("match list at page $_page has no more");
      _hasMore = false;
    }
    else {
      _log.v("match list at page $_page has ${newMatches.length} more (${searchedMatches.length + newMatches.length})");
      searchedMatches.addAll(newMatches);
    }

    loading = false;
  }
}