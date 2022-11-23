import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_urls_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/loading_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/url_entry_dialog.dart';

/// Choose matches from the match cache, or a list of matches.
class MatchCacheChooserDialog extends StatefulWidget {
  const MatchCacheChooserDialog({Key? key, this.matches}) : super(key: key);

  final List<HitFactorMatch>? matches;

  @override
  State<MatchCacheChooserDialog> createState() => _MatchCacheChooserDialogState();
}

class _MatchCacheChooserDialogState extends State<MatchCacheChooserDialog> {
  MatchCache? cache;

  int matchCacheCurrent = 0;
  int matchCacheTotal = 0;

  bool addedMatch = false;

  List<HitFactorMatch> matches = [];
  List<HitFactorMatch> searchedMatches = [];

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
      matches = [...widget.matches!];
    }
    else {
      matches = cache!.allMatches();
    }
    matches.sort((a, b) => b.date!.compareTo(a.date!));

    if(searchController.text.isNotEmpty) {
      _applySearch();
    }
    else {
      searchedMatches = []..addAll(matches);
    }
  }

  void _applySearch() {
    var search = searchController.text;
    searchedMatches = matches.where((m) => m.name!.toLowerCase().contains(search.toLowerCase())).toList();
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
              if(addedMatch) cache!.save();
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
        if(widget.matches == null) Tooltip(
          child: Text("Cache stats: ${cache!.length} entries, ${(cache!.size / (1024 * 1024)).toStringAsFixed(1)}mb"),
          message: "Note that the cache may contain multiple entries "
        ),
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
                var urls = await showDialog<List<String>>(context: context, builder: (context) => EnterUrlsDialog());

                _addMatches(urls);
              },
            )
          ],
        ),
        SizedBox(height: 10),
        Expanded(child: SizedBox(
          width: max(MediaQuery.of(context).size.width * 0.8, 700),
          child: ListView.separated(
            itemCount: searchedMatches.length,
            itemBuilder: (context, i) {
              return ListTile(
                title: Text(searchedMatches[i].name!, overflow: TextOverflow.ellipsis),
                visualDensity: VisualDensity(vertical: -4),
                onTap: () {
                  Navigator.of(context).pop(searchedMatches[i]);
                  if(addedMatch) cache!.save();
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () async {
                        var match = searchedMatches[i];
                        var deletedFuture = cache!.deleteMatch(match);

                        var deleted = await showDialog<bool>(context: context, builder: (c) => LoadingDialog(title: "Deleting...", waitOn: deletedFuture));
                        if(deleted ?? false) {
                          setState(() {
                            _updateMatches();
                          });
                        }
                      },
                    )
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

  Future<void> _addMatches(List<String>? urls) async {
    if(urls != null) {
      var futures = <Future<HitFactorMatch?>>[];
      for (var url in urls) {
        var hasMatch = await cache!.getMatch(url, localOnly: true);
        if(hasMatch != null) continue;

        futures.add(cache!.getMatch(url));
      }

      var matches = await showDialog<List<HitFactorMatch?>>(
        context: context,
        builder: (context) => LoadingDialog<List<HitFactorMatch?>>(waitOn: Future.wait(futures)),
        barrierDismissible: false,
      );

      if(matches == null) return;
      for(var m in matches) {
        if(m != null) {
          _updateMatches();
          addedMatch = true;
          break;
        }
      }
    }
  }
}
