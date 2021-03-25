import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/sort_mode.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';
import 'package:uspsa_result_viewer/ui/stage_select_dialog.dart';

class FilterControls extends StatefulWidget {
  final SortMode sortMode;

  /// All stages in the current match. Used to populate the stage
  /// filter dialog in what-if mode.
  final List<Stage> allStages;

  /// The stages currently scored. Used to populate the stage
  /// select dropdown.
  final List<Stage> filteredStages;

  final StageMenuItem currentStage;
  final FilterSet filters;

  final FocusNode? returnFocus;
  
  final Function(SortMode) onSortModeChanged;
  final Function(StageMenuItem) onStageChanged;
  final Function(FilterSet) onFiltersChanged;
  final Function(String) onSearchChanged;
  final Function(List<Stage>) onStageSetChanged;

  final bool searchError;
  //final Function onAdvancedQueryChanged;

  const FilterControls(
    {
      Key? key,
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
      DropdownMenuItem<SortMode>(
        child: Text(SortMode.score.displayString()),
        value: SortMode.score,
      ),
      DropdownMenuItem<SortMode>(
        child: Text(SortMode.time.displayString()),
        value: SortMode.time,
      ),
      DropdownMenuItem<SortMode>(
        child: Text(SortMode.alphas.displayString()),
        value: SortMode.alphas,
      ),
      DropdownMenuItem<SortMode>(
        child: Text(SortMode.availablePoints.displayString()),
        value: SortMode.availablePoints,
      ),
      DropdownMenuItem<SortMode>(
        child: Text(SortMode.lastName.displayString()),
        value: SortMode.lastName,
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

    for(Stage s in widget.filteredStages) {
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
                          suffixIcon: GestureDetector(
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
                  Column(
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
                  SizedBox(width: 10),
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
                            var stages = await showDialog<List<Stage>>(
                              context: context,
                              builder: (context) {
                                var initialState = <Stage, bool>{};
                                for(Stage s in widget.allStages) {
                                  initialState[s] = widget.filteredStages.contains(s);
                                }
                                return StageSelectDialog(initialState: initialState);
                              }
                            );

                            if(stages != null) {
                              debugPrint("Filtered stages: $stages");
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
                    child: FlatButton(
                      child: Text("FILTERS"),
                      onPressed: () async {
                        var filters = await showDialog<FilterSet>(context: context, builder: (context) {
                          return FilterDialog(currentFilters: this.widget.filters,);
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
  StageMenuItem(Stage stage) : this.stage = stage, this.type = StageMenuItemType.stage;
  StageMenuItem.filter() : this.type = StageMenuItemType.filter;
  StageMenuItem.match() : this.type = StageMenuItemType.match;

  StageMenuItemType type;
  Stage? stage;

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