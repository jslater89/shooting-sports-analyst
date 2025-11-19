/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/match_query_element.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/loading_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_source_chooser_dialog.dart';

SSALogger _log = SSALogger("MatchDatabaseChooserDialog");

/// Choose matches from the match database, or a list of matches.
class MatchDatabaseChooserDialog extends StatefulWidget {
  const MatchDatabaseChooserDialog({
    Key? key,
    this.matches,
    this.showStats = false,
    this.helpText,
    this.multiple = false,
    this.showIds = false,
    this.sport,
    this.sports,
  }) : super(key: key);

  /// If provided, only matches for this sport will be shown.
  final Sport? sport;
  /// If provided, only matches for these sports will be shown.
  final List<Sport>? sports;
  final bool showIds;
  final bool showStats;
  final List<DbShootingMatch>? matches;
  final String? helpText;
  final bool multiple;

  @override
  State<MatchDatabaseChooserDialog> createState() => _MatchDatabaseChooserDialogState();

  static Future<List<DbShootingMatch>?> show({
    required BuildContext context,
    List<DbShootingMatch>? matches,
    bool showStats = false,
    String? helpText,
    bool multiple = false,
    bool showIds = false,
    Sport? sport,
    List<Sport>? sports,
  }) {
    if(sport != null && sports != null) {
      throw ArgumentError("Cannot provide both sport and sports");
    }
    return showDialog(context: context, builder: (context) => MatchDatabaseChooserDialog(
      showIds: showIds,
      showStats: showStats,
      matches: matches,
      helpText: helpText,
      multiple: multiple,
      sport: sport,
      sports: sports,
    ), barrierDismissible: false);
  }
}

class _MatchDatabaseChooserDialogState extends State<MatchDatabaseChooserDialog> {
  late AnalystDatabase db;

  int page = 0;

  List<Sport>? sports;
  List<String> addedMatches = [];
  bool alphabeticSort = false;

  List<DbShootingMatch> matches = [];
  List<DbShootingMatch> searchedMatches = [];
  Set<int> selectedMatches = {};

  TextEditingController searchController = TextEditingController();
  ScrollController _scrollController = ScrollController();

  Timer? _searchDebouncer;
  @override
  void initState() {
    super.initState();
    db = AnalystDatabase();

    if(widget.sport != null) {
      sports = [widget.sport!];
    }
    else {
      sports = widget.sports;
    }
    searchController.addListener(() {
      _searchDebouncer?.cancel();
      _searchDebouncer = Timer(Duration(milliseconds: 500), () {
        setState(() {
          _applySearch();
        });
      });
    });
    _updateMatches();

    _scrollController.addListener(() {
      if(_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
        var position = _scrollController.position;
        if(position.hasContentDimensions && position.atEdge && position.pixels != 0) {
          setState(() {
            page += 1;
          });
          _updateMatches();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    searchController.dispose();
    _searchDebouncer?.cancel();
    super.dispose();
  }

  Future<List<int>> _getAllMatchIdsMatchingSearch() async {
    var matchIds = <int>[];
    if(widget.matches != null) {
      var matches = [...widget.matches!];

      if(searchController.text.isNotEmpty) {
        var search = searchController.text;
        matches = matches.where((m) =>
          m.eventName.toLowerCase().contains(search.toLowerCase())).toList();
      }

      if(alphabeticSort) {
        matches.sort((a, b) => a.eventName.compareTo(b.eventName));
      }
      else {
        matches.sort((a, b) => b.date.compareTo(a.date));
      }

      matchIds = matches.map((m) => m.id).toList();
    }
    else {
      matchIds = await db.queryMatchIds(
        name: searchController.text.isNotEmpty ? searchController.text : null,
        sports: sports,
        pageSize: 100000,
        sort: alphabeticSort ? const NameSort() : const DateSort(),
      );
    }

    return matchIds;
  }

  Future<void> _updateMatches() async {
    if(widget.matches != null) {
      setState(() {
        matches = [...widget.matches!];
      });
      if(searchController.text.isNotEmpty) {
        _applySearch();
      }
      else {
        searchedMatches = [...matches];
      }
      if(alphabeticSort) {
        matches.sort((a, b) => a.eventName.compareTo(b.eventName));
      }
      else {
        matches.sort((a, b) => b.date.compareTo(a.date));
      }
    }
    else {
      if(page > 0) {
        var newMatches = await db.queryMatches(
          name: searchController.text.isNotEmpty ? searchController.text : null,
          sport: widget.sport,
          sort: alphabeticSort ? const NameSort() : const DateSort(),
          page: page,
        );
        matches.addAll(newMatches);
      }
      else {
        matches = await db.queryMatches(
          name: searchController.text.isNotEmpty ? searchController.text : null,
          sport: widget.sport,
          sort: alphabeticSort ? const NameSort() : const DateSort(),
        );
      }
      searchedMatches = [...matches];
    }

    setState(() {

    });
  }

  void _applySearch() {
    if(widget.matches != null) {
      var search = searchController.text;
      searchedMatches = matches.where((m) =>
          m.eventName.toLowerCase().contains(search.toLowerCase())).toList();
    }
    else {
      page = 0;
      _updateMatches();
    }

    _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ThemeColors.backgroundColor(context),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Select match"),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: () {
              Navigator.of(context).pop();
            },
          )
        ],
      ),
      content: Container(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 700,
            maxHeight: MediaQuery.of(context).size.height,
          ),
          child: _matchSelectBody(),
        ),
      ),
      actions: [
        if(widget.multiple) Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                TextButton(
                  child: Text("SELECT NONE"),
                  onPressed: () {
                    setState(() {
                      selectedMatches.clear();
                    });
                  },
                ),
                Tooltip(
                  message: "Select all matches currently visible in the list, not including additional pages.",
                  child: TextButton(
                    child: Text("SELECT LOADED"),
                    onPressed: () {
                      setState(() {
                        selectedMatches.addAll(searchedMatches.map((m) => m.id));
                      });
                    },
                  ),
                ),
                Tooltip(
                  message: "Select all matches that match the current search, including additional pages.",
                  child: TextButton(
                    child: Text("SELECT ALL"),
                    onPressed: () async {
                      var allMatchIds = await _getAllMatchIdsMatchingSearch();
                      setState(() {
                        selectedMatches.addAll(allMatchIds);
                      });
                    },
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if(widget.multiple) TextButton(
                  child: Text("CANCEL"),
                  onPressed: () {
                    Navigator.of(context).pop(null);
                  },
                ),
                if(widget.multiple) TextButton(
                  child: Text("CONFIRM"),
                  onPressed: () async {
                    List<DbShootingMatch> selected = [];
                    for(var id in selectedMatches) {
                      var match = await AnalystDatabase().getMatch(id);
                      if(match != null) {
                        selected.add(match);
                      }
                    }
                    Navigator.of(context).pop(selected);
                  },
                )
              ],
            )
          ],
        ),
      ],
    );
  }

  Widget _matchSelectBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if(widget.showStats) Tooltip(
          child: Text("Database stats: TODO matches\n"
              "TODO mb"),
          message: "Note that the cache may contain multiple entries for each match, one for each PractiScore "
              "ID format."
        ),
        if(widget.showStats) SizedBox(height: 5),
        if(widget.helpText != null) Text(
          widget.helpText!
        ),
        if(widget.helpText != null) SizedBox(height: 5),
        if(widget.multiple) Text(
          "${selectedMatches.length} matches selected"
        ),
        if(widget.multiple) SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 400,
              child: TextField(
                decoration: InputDecoration(
                  labelText: "Search"
                ),
                controller: searchController,
                onSubmitted: (value) {
                  _applySearch();
                },
              ),
            ),
            if(widget.matches == null) IconButton(
              icon: Icon(Icons.add),
              onPressed: () async {
                var result = await MatchSourceChooserDialog.show(
                  context,
                  MatchSourceRegistry().sources,
                  descriptionText: "Enter a link to a Practiscore results page.",
                  hintText: "https://practiscore.com/results/new/...",
                  initialSearch: searchController.text,
                  onMatchDownloaded: (match) {
                    // We don't need to refresh the match list here, because we will once we leave
                    // the dialog.
                    setState(() {
                      if(match.databaseId != null) {
                        selectedMatches.add(match.databaseId!);
                        _log.v("Added match ${match.name} (${match.sourceIds}) (${match.databaseId}) to selected matches");
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Downloaded and selected ${match.name}")));

                      }
                      else {
                        _log.w("Downloaded match ${match.name} (${match.sourceIds}) has no database ID");
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Downloaded ${match.name}, but saving failed")));
                      }
                    });
                  },
                );
                if(result == null) {
                  // Update matches, because we might have done the long-press-download trick
                  _updateMatches();
                  return;
                }
                var (_, match) = result;

                var saveResult = await db.saveMatch(match);
                if(saveResult.isErr()) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saveResult.unwrapErr().message)));
                  return;
                }
                await _updateMatches();
                setState(() {
                  selectedMatches.add(saveResult.unwrap().id);
                });
              },
            ),
            Tooltip(
              message: alphabeticSort ?
                  "Switch to date sort." :
                  "Switch to alphabetic sort.",
              child: IconButton(
                icon: alphabeticSort ? Icon(Icons.sort_by_alpha) : Icon(Icons.sort),
                onPressed: () {
                  setState(() {
                    alphabeticSort = !alphabeticSort;
                  });
                  _updateMatches();
                },
              ),
            )
          ],
        ),
        SizedBox(height: 10),
        Expanded(child: SizedBox(
          width: max(MediaQuery.of(context).size.width * 0.8, 700),
          child: ListView.separated(
            controller: _scrollController,
            itemCount: searchedMatches.length,
            itemBuilder: (context, i) {
              var name = searchedMatches[i].eventName;
              if(name.isEmpty) name = "(match name not provided)";
              return ListTile(
                title: Text(name, overflow: TextOverflow.ellipsis),
                subtitle: !widget.showIds ? null
                  : SelectableText("${searchedMatches[i].sourceIds.join(" ")}"),
                visualDensity: VisualDensity(vertical: -4),
                onTap: () {
                  if(widget.multiple) {
                    if(selectedMatches.contains(searchedMatches[i].id)) {
                      setState(() {
                        selectedMatches.remove(searchedMatches[i].id);
                      });
                    }
                    else {
                      setState(() {
                        selectedMatches.add(searchedMatches[i].id);
                      });
                    }
                  }
                  else {
                    Navigator.of(context).pop(searchedMatches[i]);
                  }
                },
                leading: widget.multiple && selectedMatches.contains(searchedMatches[i].id) ? Icon(
                  Icons.check,
                ) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.refresh),
                      onPressed: () async {
                        var match = searchedMatches[i];
                        var result = await LoadingDialog.show(
                          context: context,
                          waitOn: MatchSource.reloadMatch(match),
                        );

                        if(result != null && result.isOk()) {
                          _log.i("Refreshed ${result.unwrap().name} (${result.unwrap().sourceIds})");
                          if(mounted) setState(() {
                            _updateMatches();
                          });
                        }
                        else {
                          _log.d("Unable to refresh match: ${result?.unwrapErr()}");
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () async {
                        var match = searchedMatches[i];
                        var deletedFuture = db.deleteMatch(match.id);
                        selectedMatches.remove(match.id);

                        var deleted = await LoadingDialog.show(context: context, waitOn: deletedFuture);
                        if(deleted != null && deleted.isOk()) {
                          setState(() {
                            _updateMatches();
                          });
                        }
                        else {
                          _log.d("Unable to delete match: ${deleted?.unwrapErr()}");
                        }
                      },
                    ),
                  ],
                ),
              );
            },
            separatorBuilder: (context, i) => Divider(),
          ),
        ))
      ],
    );
  }
}
