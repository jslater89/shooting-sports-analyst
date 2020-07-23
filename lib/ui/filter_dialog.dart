import 'package:flutter/material.dart';
import 'package:uspsa_results_viewer/data/model.dart';

class FilterSet {
  FilterMode mode = FilterMode.and;
  bool reentries = true;

  Map<Division, bool> divisions;
  Map<Classification, bool> classifications;
  Map<PowerFactor, bool> powerFactors;

  FilterSet({bool empty = false}) {
    divisions = {};
    classifications = {};
    powerFactors = {};

    for (Division d in Division.values) {
      divisions[d] = !empty;
    }

    for (Classification c in Classification.values) {
      classifications[c] = !empty;
    }

    for (PowerFactor f in PowerFactor.values) {
      powerFactors[f] = !empty;
    }

  }
}

class FilterDialog extends StatefulWidget {
  final FilterSet currentFilters;

  const FilterDialog({Key key, this.currentFilters}) : super(key: key);
  @override
  State<FilterDialog> createState() {
    return _FilterDialogState();
  }

}

class _FilterDialogState extends State<FilterDialog> {

  FilterSet _filters;
  @override
  void initState() {
    super.initState();
    _filters = widget.currentFilters;
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Filters"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Power Factors", style: Theme.of(context).textTheme.subtitle1.apply(decoration: TextDecoration.underline)),
                    CheckboxListTile(
                      title: Text("Major"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.powerFactors[PowerFactor.major],
                      onChanged: (bool value) {
                        _updateFilter(_filters.powerFactors, PowerFactor.major, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("Minor"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.powerFactors[PowerFactor.minor],
                      onChanged: (bool value) {
                        _updateFilter(_filters.powerFactors, PowerFactor.minor, value);
                      },
                    )
                  ],
                ),
              ),
              SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Divisions", style: Theme.of(context).textTheme.subtitle1.apply(decoration: TextDecoration.underline)),
                    CheckboxListTile(
                      title: Text("PCC"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.divisions[Division.pcc],
                      onChanged: (bool value) {
                        _updateFilter(_filters.divisions, Division.pcc, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("Open"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.divisions[Division.open],
                      onChanged: (bool value) {
                        _updateFilter(_filters.divisions, Division.open, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("Limited"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.divisions[Division.limited],
                      onChanged: (bool value) {
                        _updateFilter(_filters.divisions, Division.limited, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("Limited 10"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.divisions[Division.limited10],
                      onChanged: (bool value) {
                        _updateFilter(_filters.divisions, Division.limited10, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("Carry Optics"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.divisions[Division.carryOptics],
                      onChanged: (bool value) {
                        _updateFilter(_filters.divisions, Division.carryOptics, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("Production"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.divisions[Division.production],
                      onChanged: (bool value) {
                        _updateFilter(_filters.divisions, Division.production, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("Single Stack"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.divisions[Division.singleStack],
                      onChanged: (bool value) {
                        _updateFilter(_filters.divisions, Division.singleStack, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("Revolver"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.divisions[Division.revolver],
                      onChanged: (bool value) {
                        _updateFilter(_filters.divisions, Division.revolver, value);
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Classes", style: Theme.of(context).textTheme.subtitle1.apply(decoration: TextDecoration.underline)),
                    CheckboxListTile(
                      title: Text("GM"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.classifications[Classification.GM],
                      onChanged: (bool value) {
                        _updateFilter(_filters.classifications, Classification.GM, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("M"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.classifications[Classification.M],
                      onChanged: (bool value) {
                        _updateFilter(_filters.classifications, Classification.M, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("A"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.classifications[Classification.A],
                      onChanged: (bool value) {
                        _updateFilter(_filters.classifications, Classification.A, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("B"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.classifications[Classification.B],
                      onChanged: (bool value) {
                        _updateFilter(_filters.classifications, Classification.B, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("C"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.classifications[Classification.C],
                      onChanged: (bool value) {
                        _updateFilter(_filters.classifications, Classification.C, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("D"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.classifications[Classification.D],
                      onChanged: (bool value) {
                        _updateFilter(_filters.classifications, Classification.D, value);
                      },
                    ),
                    CheckboxListTile(
                      title: Text("U"),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _filters.classifications[Classification.U],
                      onChanged: (bool value) {
                        _updateFilter(_filters.classifications, Classification.U, value);
                      },
                    )
                  ],
                ),
              ),
            ],
          ),
          Divider(),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: "If unchecked, results for shooters' second guns will be hidden.",
                  child: CheckboxListTile(
                    title: Text("Include 2nd Gun?"),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _filters.reentries,
                    onChanged: (bool value) {
                      setState(() {
                        _filters.reentries = value;
                      });
                    },
                  ),
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: "If checked, only shooters who match ALL checked values will be shown. "
                    "Otherwise, shooters who match ANY checked value will be shown.",
                  child: CheckboxListTile(
                    title: Text("Exclusive Filters?"),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _filters.mode == FilterMode.and,
                    onChanged: (bool value) {
                      setState(() {
                        value ? _filters.mode = FilterMode.and : _filters.mode = FilterMode.or;
                      });
                    }
                  ),
                ),
              )
            ],
          )
        ],
      ),
      actions: [
        FlatButton(
          child: Text("RESET"),
          onPressed: () {
            setState(() {
              _filters = FilterSet();
            });
          },
        ),
        FlatButton(
          child: Text("CLEAR"),
          onPressed: () {
            setState(() {
              _filters = FilterSet(empty: true);
            });
          },
        ),
        SizedBox(width: 60),
        FlatButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop(null);
          },
        ),
        FlatButton(
          child: Text("APPLY"),
          onPressed: () {
            Navigator.of(context).pop(_filters);
          },
        )
      ],
    );
  }

  void _updateFilter<T>(Map<T, bool> filterSet, T key, bool value) {
    setState(() {
      filterSet[key] = value;
    });
  }
}