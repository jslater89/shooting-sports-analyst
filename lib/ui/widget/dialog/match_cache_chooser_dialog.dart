/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/results_file_parser.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/loading_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/url_entry_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

/// Choose matches from the match cache, or a list of matches.
class MatchCacheChooserDialog extends StatefulWidget {
  const MatchCacheChooserDialog({
    Key? key,
    this.matches,
    this.showStats = false,
    this.helpText,
    this.multiple = false,
    this.showIds = false,
  }) : super(key: key);

  final bool showIds;
  final bool showStats;
  final List<PracticalMatch>? matches;
  final String? helpText;
  final bool multiple;

  @override
  State<MatchCacheChooserDialog> createState() => _MatchCacheChooserDialogState();

  static Future<List<MatchCacheIndexEntry>?> show({
    required BuildContext context,
    List<PracticalMatch>? matches,
    bool showStats = false,
    String? helpText,
    bool multiple = false,
    bool showIds = false,
  }) {
    return showDialog(context: context, builder: (context) => MatchCacheChooserDialog(
      showIds: showIds,
      showStats: showStats,
      matches: matches,
      helpText: helpText,
      multiple: multiple,
    ), barrierDismissible: false);
  }
}

class _MatchCacheChooserDialogState extends State<MatchCacheChooserDialog> {
  MatchCache? cache;

  int matchCacheCurrent = 0;
  int matchCacheTotal = 0;

  List<String> addedMatches = [];
  bool alphabeticSort = false;

  List<MatchCacheIndexEntry> matches = [];
  List<MatchCacheIndexEntry> searchedMatches = [];
  Set<MatchCacheIndexEntry> selectedMatches = {};

  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if(!MatchCache.readyNow) {
      _warmCache();
    }
    else {
      cache = MatchCache();
      _updateMatches();
    }

    searchController.addListener(() {
      setState(() {
        _applySearch();
      });
    });
  }

  void _warmCache() async {
    matchCacheProgressCallback = (current, total) async {
      setState(() {
        matchCacheCurrent = current;
        matchCacheTotal = total;
      });
      await Future.delayed(Duration(milliseconds: 1));
    };
    await MatchCache().ready;
    setState(() {
      cache = MatchCache();
      _updateMatches();
    });
  }

  void _updateMatches() {
    if(widget.matches != null) {
      matches = [];
      for(var m in widget.matches!) {
        var idxEntry = cache!.indexEntryFor(m);
        if(idxEntry != null) {
          matches.add(idxEntry);
        }
      }
    }
    else {
      matches = cache!.allIndexEntries();
    }

    if(alphabeticSort) {
      matches.sort((a, b) => a.matchName.compareTo(b.matchName));
    }
    else {
      matches.sort((a, b) => b.matchDate.compareTo(a.matchDate));
    }

    if(searchController.text.isNotEmpty) {
      _applySearch();
    }
    else {
      searchedMatches = []..addAll(matches);
    }
  }

  void _applySearch() {
    var search = searchController.text;
    searchedMatches = matches.where((m) => m.matchName.toLowerCase().contains(search.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(cache != null ? "Select match" : "Loading match cache"),
          IconButton(
            icon: Icon(Icons.close),
            // Don't allow premature closing
            onPressed: cache != null ? () {
              Navigator.of(context).pop();
              cache!.save(forceResave: addedMatches);
            } : null,
          )
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 700,
          maxHeight: MediaQuery.of(context).size.height,
        ),
        child: cache != null ? _matchSelectBody() : _loadingIndicatorBody()
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
                TextButton(
                  child: Text("SELECT ALL"),
                  onPressed: () {
                    setState(() {
                      selectedMatches.addAll(searchedMatches);
                    });
                  },
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
                    cache!.save(forceResave: addedMatches);
                    Navigator.of(context).pop(null);
                  },
                ),
                if(widget.multiple) TextButton(
                  child: Text("CONFIRM"),
                  onPressed: () {
                    cache!.save(forceResave: addedMatches);
                    Navigator.of(context).pop(selectedMatches.toList());
                  },
                )
              ],
            )
          ],
        ),
      ],
    );
  }

  Widget _loadingIndicatorBody() {
    return Padding(
      padding: const EdgeInsets.all(0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 64),
          Text("Loading match cache...", style: Theme.of(context).textTheme.subtitle1),
          if(matchCacheTotal > 0)
            SizedBox(height: 16),
          if(matchCacheTotal > 0)
            LinearProgressIndicator(
              value: matchCacheCurrent / matchCacheTotal,
            ),
          SizedBox(height: 64),
        ],
      ),
    );
  }

  Widget _matchSelectBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if(widget.showStats) Tooltip(
          child: Text("Cache stats: ${cache!.cacheLength} entries, ${cache!.uniqueMatches} matches\n"
              "Index stats: ${cache!.uniqueIndexEntries} entries, ${(cache!.size / (1024 * 1024)).toStringAsFixed(1)}mb"),
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
              ),
            ),
            if(widget.matches == null) IconButton(
              icon: Icon(Icons.add),
              onPressed: () async {
                var url = await showDialog<String>(context: context, builder: (context) => UrlEntryDialog(
                  descriptionText: "Enter a link to a Practiscore results page.",
                  hintText: "https://practiscore.com/results/new/..."
                ));

                if(url != null) {
                  var result = await cache!.getMatch(url, localOnly: true);
                  if(result.isOk()) return;

                  var resultFuture = cache!.getMatch(url);
                  var res2 = await showDialog<Result<PracticalMatch, MatchGetError>>(context: context, builder: (c) => LoadingDialog(waitOn: resultFuture));
                  if(res2 != null) {
                    if(res2.isOk()) {
                      setState(() {
                        _updateMatches();
                        addedMatches.add(res2.unwrap().practiscoreId);
                      });
                    }
                    else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res2.unwrapErr().message)));
                    }
                  }
                }
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
            itemCount: searchedMatches.length,
            itemBuilder: (context, i) {
              var name = searchedMatches[i].matchName;
              if(name.isEmpty) name = "(match name not provided)";
              return ListTile(
                title: Text(name, overflow: TextOverflow.ellipsis),
                subtitle: !widget.showIds ? null
                  : SelectableText("${searchedMatches[i].ids.join(" ")}"),
                visualDensity: VisualDensity(vertical: -4),
                onTap: () {
                  if(widget.multiple) {
                    if(selectedMatches.contains(searchedMatches[i])) {
                      setState(() {
                        selectedMatches.remove(searchedMatches[i]);
                      });
                    }
                    else {
                      setState(() {
                        selectedMatches.add(searchedMatches[i]);
                      });
                    }
                  }
                  else {
                    Navigator.of(context).pop(searchedMatches[i]);
                  }
                  cache!.save(forceResave: addedMatches);
                },
                leading: widget.multiple && selectedMatches.contains(searchedMatches[i]) ? Icon(
                  Icons.check,
                ) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.refresh),
                      onPressed: () async {
                        var match = searchedMatches[i];
                        var url = MatchCache().getIndexUrl(match)!; // can't be in this dialog unless in cache
                        print("refreshing: $url");

                        var deleted = await cache!.deleteIndexEntry(match);
                        if(!deleted) {
                          print("Unable to delete!");
                        }

                        var result = await LoadingDialog.show(context: context, waitOn: MatchCache().getMatch(url, forceUpdate: true));

                        if(result.isOk()) {
                          print("Refreshed ${result.unwrap().name} (${result.unwrap().practiscoreId} ${result.unwrap().practiscoreIdShort})");
                          cache!.save();
                          if(mounted) setState(() {
                            _updateMatches();
                          });
                        }
                        else debugPrint("Unable to get match: ${result.unwrapErr()}");
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () async {
                        var match = searchedMatches[i];
                        var deletedFuture = cache!.deleteIndexEntry(match);

                        var deleted = await showDialog<bool>(context: context, builder: (c) => LoadingDialog(title: "Deleting...", waitOn: deletedFuture));
                        if(deleted ?? false) {
                          setState(() {
                            _updateMatches();
                          });
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
