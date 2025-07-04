/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';

SSALogger _log = SSALogger("MatchDatabaseChooserDialog");

/// Choose matches from the match database, or a list of matches.
class MatchPointerChooserDialog extends StatefulWidget {
  const MatchPointerChooserDialog({
    Key? key,
    required this.matches,
    this.showStats = false,
    this.helpText,
    this.multiple = false,
    this.showIds = false,
  }) : super(key: key);

  final bool showIds;
  final bool showStats;
  final List<MatchPointer> matches;
  final String? helpText;
  final bool multiple;

  @override
  State<MatchPointerChooserDialog> createState() => _MatchPointerChooserDialogState();

  static Future<List<MatchPointer>?> showMultiple({
    required BuildContext context,
    required List<MatchPointer> matches,
    bool showStats = false,
    String? helpText,
    bool showIds = false,
  }) {
    return showDialog(context: context, builder: (context) => MatchPointerChooserDialog(
      showIds: showIds,
      showStats: showStats,
      matches: matches,
      helpText: helpText,
      multiple: true,
    ), barrierDismissible: false);
  }

  static Future<MatchPointer?> showSingle({
    required BuildContext context,
    required List<MatchPointer> matches,
    bool showStats = false,
    String? helpText,
    bool showIds = false,
  }) {
    return showDialog(context: context, builder: (context) => MatchPointerChooserDialog(
      showIds: showIds,
      showStats: showStats,
      matches: matches,
      helpText: helpText,
      multiple: false,
    ), barrierDismissible: false);
  }
}

class _MatchPointerChooserDialogState extends State<MatchPointerChooserDialog> {
  late AnalystDatabase db;

  int matchCacheCurrent = 0;
  int matchCacheTotal = 0;

  List<String> addedMatches = [];
  bool alphabeticSort = false;

  List<MatchPointer> matches = [];
  List<MatchPointer> searchedMatches = [];
  Set<MatchPointer> selectedMatches = {};

  TextEditingController searchController = TextEditingController();

  Timer? _searchDebouncer;
  @override
  void initState() {
    super.initState();
    db = AnalystDatabase();

    searchController.addListener(() {
      _searchDebouncer?.cancel();
      _searchDebouncer = Timer(Duration(milliseconds: 500), () {
        setState(() {
          _applySearch();
        });
      });
    });
    _updateMatches();
  }

  Future<void> _updateMatches() async {
    setState(() {
      matches = [...widget.matches];
    });
    if(searchController.text.isNotEmpty) {
      _applySearch();
    }
    else {
      searchedMatches = [...matches];
    }
    if(alphabeticSort) {
      matches.sort((a, b) => a.name.compareTo(b.name));
    }
    else {
      matches.sort((a, b) => b.date!.compareTo(a.date!));
    }
  }

  void _applySearch() {
    var search = searchController.text;
    searchedMatches = matches.where((m) =>
        m.name.toLowerCase().contains(search.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 700,
          maxHeight: MediaQuery.of(context).size.height,
        ),
        child: _matchSelectBody(),
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
                    Navigator.of(context).pop(null);
                  },
                ),
                if(widget.multiple) TextButton(
                  child: Text("CONFIRM"),
                  onPressed: () {
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
              ),
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
              var name = searchedMatches[i].name;
              if(name.isEmpty) name = "(match name not provided)";
              return ListTile(
                title: Text(name, overflow: TextOverflow.ellipsis),
                subtitle: !widget.showIds ? null
                  : SelectableText("${searchedMatches[i].sourceIds.join(" ")}"),
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
                },
                leading: widget.multiple && selectedMatches.contains(searchedMatches[i]) ? Icon(
                  Icons.check,
                ) : null,
              );
            },
            separatorBuilder: (context, i) => Divider(),
          ),
        ))
      ],
    );
  }
}
