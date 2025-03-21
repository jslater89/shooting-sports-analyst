/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/sort_mode.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/stage_select_dialog.dart';

var _log = SSALogger("FilterControls");

class FilterControls extends StatefulWidget {
  final Sport sport;

  final SortMode sortMode;

  /// All stages in the current match. Used to populate the stage
  /// filter dialog in what-if mode.
  final List<MatchStage> allStages;

  /// The stages currently scored. Used to populate the stage
  /// select dropdown.
  final List<MatchStage> filteredStages;

  final StageMenuItem currentStage;
  final FilterSet filters;

  final FocusNode? returnFocus;
  
  final Function(SortMode) onSortModeChanged;
  final Function(StageMenuItem) onStageChanged;
  final Function(FilterSet) onFiltersChanged;
  final Function(String) onSearchChanged;
  final Function(List<MatchStage>) onStageSetChanged;

  final bool searchError;
  final bool hasRatings;
  final bool hasFantasyScores;
  //final Function onAdvancedQueryChanged;

  const FilterControls(
    {
      Key? key,
      required this.sport,
      required this.sortMode,
      required this.currentStage,
      required this.allStages,
      required this.filteredStages,
      required this.filters,
      required this.returnFocus,
      required this.searchError,
      required this.onSortModeChanged,
      required this.onStageChanged,
      required this.onStageSetChanged,
      required this.onFiltersChanged,
      required this.onSearchChanged,
      required this.hasRatings,
      required this.hasFantasyScores,
    }) : super(key: key);

  @override
  _FilterControlsState createState() => _FilterControlsState();
}

class _FilterControlsState extends State<FilterControls> {
  TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      widget.onSearchChanged(_searchController.text);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<DropdownMenuItem<SortMode>> _buildSortItems() {
    return [
      for(var mode in widget.sport.resultSortModes)
        DropdownMenuItem<SortMode>(
          child: Text(mode.displayString()),
          value: mode,
        ),
      if(widget.hasRatings) DropdownMenuItem<SortMode>(
        child: Text(SortMode.rating.displayString()),
        value: SortMode.rating,
      ),
      if(widget.hasFantasyScores) DropdownMenuItem<SortMode>(
        child: Text(SortMode.fantasyPoints.displayString()),
        value: SortMode.fantasyPoints,
      ),
    ];
  }

  List<DropdownMenuItem<StageMenuItem>> _buildStageMenuItems() {
    var stageMenuItems = [
      DropdownMenuItem<StageMenuItem>(
        child: Text("Match"),
        value: StageMenuItem.match(),
      )
    ];

    for(MatchStage s in widget.filteredStages) {
      stageMenuItems.add(
          DropdownMenuItem<StageMenuItem>(
              child: Text(s.name),
              value: StageMenuItem(s),
          )
      );
    }

    stageMenuItems.add(
      DropdownMenuItem<StageMenuItem>(
        child: Text("Select stages..."),
        value: StageMenuItem.filter(),
      )
    );

    return stageMenuItems;
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        elevation: 3,
        child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
              child: Wrap(
                direction: Axis.horizontal,
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 300,
                      minWidth: 100,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: TextField(
                        controller: _searchController,
                        autofocus: false,
                        decoration: InputDecoration(
                          helperText: ' ',
                          errorText: widget.searchError ? "Invalid query" : null,
                          hintText: "Quick search",
                          suffixIcon: _searchController.text.length > 0 ?
                            GestureDetector(
                              child: Icon(Icons.cancel),
                              onTap: () {
                                _searchController.text = '';
                              },
                            ) :
                            GestureDetector(
                              child: Icon(Icons.help),
                              onTap: () {
                                _showQueryHelp(size);
                              },
                            )
                        ),
                        onSubmitted: (_t) {
                          widget.returnFocus!.requestFocus();
                        },
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  if(widget.sport.resultSortModes.isNotEmpty) Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Sort by...", style: Theme.of(context).textTheme.caption),
                      DropdownButton<SortMode>(
                        underline: Container(
                          height: 1,
                          color: Colors.black,
                        ),
                        items: _buildSortItems(),
                        onChanged: (SortMode? s) {
                          if(s != null) widget.onSortModeChanged(s);
                        },
                        value: widget.sortMode,
                      ),
                    ],
                  ),
                  if(widget.sport.resultSortModes.isNotEmpty) SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Results for...", style: Theme.of(context).textTheme.caption),
                      DropdownButton<StageMenuItem>(
                        underline: Container(
                          height: 1,
                          color: Colors.black,
                        ),
                        items: _buildStageMenuItems(),
                        onChanged: (StageMenuItem? item) async {
                          if(item == StageMenuItem.filter()) {
                            var stages = await showDialog<List<MatchStage>>(
                              context: context,
                              builder: (context) {
                                var initialState = <MatchStage, bool>{};
                                for(MatchStage s in widget.allStages) {
                                  initialState[s] = widget.filteredStages.contains(s);
                                }
                                return StageSelectDialog(initialState: initialState);
                              }
                            );

                            if(stages != null) {
                              _log.d("Filtered stages: $stages");
                              widget.onStageSetChanged(stages);
                            }
                          }
                          else {
                            if(item != null) widget.onStageChanged(item);
                          }
                        },
                        value: widget.currentStage,
                      ),
                    ],
                  ),
                  SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: TextButton(
                      child: Text("FILTERS"),
                      onPressed: () async {
                        var filters = await showDialog<FilterSet>(context: context, builder: (context) {
                          return FilterDialog(currentFilters: this.widget.filters);
                        });

                        if(filters != null) {
                          widget.onFiltersChanged(filters);
                        }
                      },
                    ),
                  ),
                ],
              ),
            )
        ),
      ),
    );
  }

  void _showQueryHelp(Size screenSize) {
    showDialog(context: context, builder: (BuildContext context) {
      return AlertDialog(
        title: Text("Search Help"),
        content: SizedBox(
          width: screenSize.width * 0.5,
          child: Text("Enter text to search by name.\n"
              "\n"
              "The search box also supports a simple query language. Start your query with a question mark to enter "
              "query mode. Query mode uses groups of search terms linked by the keyword AND. Valid search terms are "
              "division names, classifications, power factors, and shooter names. Shooter names must be enclosed in "
              "double quotes. For instance, '?\"jay\" AND revo' searches for all Jays in Revolver division.\n"
              "\n"
              "Groups of search terms may be separated by the keyword OR. '?lim10 AND b OR prod AND c OR ss AND d' "
              "searches for Limited 10 B-class shooters, Production Cs, and Single Stack Ds.\n"
              "\n"
              "Queries are not case sensitive."),
        ),
      );
    });
  }
}

enum StageMenuItemType {
  stage,
  filter,
  match,
}
class StageMenuItem {
  StageMenuItem(MatchStage stage) : this.stage = stage, this.type = StageMenuItemType.stage;
  StageMenuItem.filter() : this.type = StageMenuItemType.filter;
  StageMenuItem.match() : this.type = StageMenuItemType.match;

  StageMenuItemType type;
  MatchStage? stage;

  @override
  bool operator ==(Object other) {
    if(!(other is StageMenuItem)) return false;
    StageMenuItem o2 = other;

    if(this.type == StageMenuItemType.stage) {
      return this.type == o2.type && this.stage == o2.stage;
    }
    else {
      return this.type == o2.type;
    }
  }

  @override
  int get hashCode => type.hashCode ^ (stage?.hashCode ?? 0);

  @override
  String toString() {
    return "type: $type name: ${this.stage?.name}";
  }
}