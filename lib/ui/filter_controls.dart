import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/sort_mode.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';

class FilterControls extends StatefulWidget {
  final SortMode sortMode;
  final List<Stage> stages;
  final Stage currentStage;
  final FilterSet filters;
  
  final Function(SortMode) onSortModeChanged;
  final Function(Stage) onStageChanged;
  final Function(FilterSet) onFiltersChanged;
  final Function(String) onSearchChanged;
  //final Function onAdvancedQueryChanged;

  const FilterControls(
    {
      Key key,
      @required this.sortMode,
      @required this.currentStage,
      @required this.stages,
      @required this.filters,
      @required this.onSortModeChanged,
      @required this.onStageChanged,
      @required this.onFiltersChanged,
      @required this.onSearchChanged
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

  List<DropdownMenuItem<Stage>> _buildStageMenuItems() {
    var stageMenuItems = [
      DropdownMenuItem<Stage>(
        child: Text("Match"),
        value: null,
      )
    ];

    for(Stage s in widget.stages) {
      stageMenuItems.add(
          DropdownMenuItem<Stage>(
              child: Text(s.name),
              value: s
          )
      );
    }

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
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 200,
                      minWidth: 50,
                    ),
                    child: TextField(
                      controller: _searchController,
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: "Quick search",
//                        suffixIcon: GestureDetector(
//                          child: Icon(Icons.help),
//                        )
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
                        onChanged: (SortMode s) {
                          widget.onSortModeChanged(s);
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
                      DropdownButton<Stage>(
                        underline: Container(
                          height: 1,
                          color: Colors.black,
                        ),
                        items: _buildStageMenuItems(),
                        onChanged: (Stage s) {
                          widget.onStageChanged(s);
                        },
                        value: widget.currentStage,
                      ),
                    ],
                  ),
                  SizedBox(width: 10),
                  FlatButton(
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
                ],
              ),
            )
        ),
      ),
    );
  }
}