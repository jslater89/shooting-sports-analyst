import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';

class FilterSet {
  FilterMode mode = FilterMode.and;
  bool reentries = true;
  bool scoreDQs = true;

  late Map<USPSADivision, bool> divisions;
  late Map<USPSAClassification, bool> classifications;
  late Map<PowerFactor, bool> powerFactors;

  FilterSet({bool empty = false}) {
    divisions = {};
    classifications = {};
    powerFactors = {};

    for (USPSADivision d in USPSADivision.values) {
      divisions[d] = !empty;
    }

    for (USPSAClassification c in USPSAClassification.values) {
      classifications[c] = !empty;
    }

    for (PowerFactor f in PowerFactor.values) {
      powerFactors[f] = !empty;
    }
  }

  Iterable<USPSADivision> get activeDivisions => divisions.keys.where((div) => divisions[div] ?? false);

  static Map<USPSADivision, bool> divisionListToMap(List<USPSADivision> divisions) {
    Map<USPSADivision, bool> map = {};
    for(var d in USPSADivision.values) {
      map[d] = divisions.contains(d);
    }

    return map;
  }
}

class FilterDialog extends StatefulWidget {
  final FilterSet? currentFilters;

  const FilterDialog({Key? key, this.currentFilters}) : super(key: key);
  @override
  State<FilterDialog> createState() {
    return _FilterDialogState();
  }

}

class _FilterDialogState extends State<FilterDialog> {

  FilterSet? _filters;
  @override
  void initState() {
    super.initState();
    _filters = widget.currentFilters;
  }
  @override
  Widget build(BuildContext context) {
    if(MediaQuery.of(context).size.width < 775) {
      return _buildNarrow(context);
    }
    else {
      return _buildWide(context);
    }
  }

  void _updateFilter<T>(Map<T, bool?>? filterSet, T key, bool? value) {
    setState(() {
      filterSet![key] = value;
    });
  }

  Widget _buildWide(BuildContext context) {
    return AlertDialog(
      title: Text("Filters"),
      content: SingleChildScrollView(
        child: Column(
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
                    children: _powerFactorTiles(context),
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _divisionTiles(context),
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _classTiles(context),
                  ),
                ),
              ],
            ),
            Divider(),
            Row(
              children: _settingsTiles(context).map((e) => Expanded(child: e)).toList()
            ),
          ],
        ),
      ),
      actions: _actions(context),
    );
  }

  Widget _buildNarrow(BuildContext context) {
    var height = MediaQuery.of(context).size.height * 0.9;
    return AlertDialog(
      title: Text("Filters"),
      content: SizedBox(
        height: height,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: []
              ..addAll(_powerFactorTiles(context))
              ..add(SizedBox(height: 10))
              ..addAll(_divisionTiles(context))
              ..add(SizedBox(height: 10))
              ..addAll(_classTiles(context))
              ..add(Divider())
              ..addAll(_settingsTiles(context))
          ),
        ),
      ),
      actions: _actions(context),
    );
  }

  List<Widget> _powerFactorTiles(BuildContext context) {
    return [
      Text("Power Factors", style: Theme.of(context).textTheme.subtitle1!.apply(decoration: TextDecoration.underline)),
      CheckboxListTile(
        title: Text("Major"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.powerFactors[PowerFactor.major],
        onChanged: (bool? value) {
          _updateFilter(_filters!.powerFactors, PowerFactor.major, value);
        },
      ),
      CheckboxListTile(
        title: Text("Minor"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.powerFactors[PowerFactor.minor],
        onChanged: (bool? value) {
          _updateFilter(_filters!.powerFactors, PowerFactor.minor, value);
        },
      )
    ];
  }

  List<Widget> _divisionTiles(BuildContext context) {
    return [
      Text("Divisions", style: Theme.of(context).textTheme.subtitle1!.apply(decoration: TextDecoration.underline)),
      CheckboxListTile(
        title: Text("PCC"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.divisions[USPSADivision.pcc],
        onChanged: (bool? value) {
          _updateFilter(_filters!.divisions, USPSADivision.pcc, value);
        },
      ),
      CheckboxListTile(
        title: Text("Open"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.divisions[USPSADivision.open],
        onChanged: (bool? value) {
          _updateFilter(_filters!.divisions, USPSADivision.open, value);
        },
      ),
      CheckboxListTile(
        title: Text("Limited"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.divisions[USPSADivision.limited],
        onChanged: (bool? value) {
          _updateFilter(_filters!.divisions, USPSADivision.limited, value);
        },
      ),
      CheckboxListTile(
        title: Text("Limited 10"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.divisions[USPSADivision.limited10],
        onChanged: (bool? value) {
          _updateFilter(_filters!.divisions, USPSADivision.limited10, value);
        },
      ),
      CheckboxListTile(
        title: Text("Carry Optics"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.divisions[USPSADivision.carryOptics],
        onChanged: (bool? value) {
          _updateFilter(_filters!.divisions, USPSADivision.carryOptics, value);
        },
      ),
      CheckboxListTile(
        title: Text("Production"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.divisions[USPSADivision.production],
        onChanged: (bool? value) {
          _updateFilter(_filters!.divisions, USPSADivision.production, value);
        },
      ),
      CheckboxListTile(
        title: Text("Single Stack"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.divisions[USPSADivision.singleStack],
        onChanged: (bool? value) {
          _updateFilter(_filters!.divisions, USPSADivision.singleStack, value);
        },
      ),
      CheckboxListTile(
        title: Text("Revolver"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.divisions[USPSADivision.revolver],
        onChanged: (bool? value) {
          _updateFilter(_filters!.divisions, USPSADivision.revolver, value);
        },
      ),
    ];
  }

  List<Widget> _classTiles(BuildContext context) {
    return [
      Text("Classes", style: Theme.of(context).textTheme.subtitle1!.apply(decoration: TextDecoration.underline)),
      CheckboxListTile(
        title: Text("GM"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.classifications[USPSAClassification.GM],
        onChanged: (bool? value) {
          _updateFilter(_filters!.classifications, USPSAClassification.GM, value);
        },
      ),
      CheckboxListTile(
        title: Text("M"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.classifications[USPSAClassification.M],
        onChanged: (bool? value) {
          _updateFilter(_filters!.classifications, USPSAClassification.M, value);
        },
      ),
      CheckboxListTile(
        title: Text("A"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.classifications[USPSAClassification.A],
        onChanged: (bool? value) {
          _updateFilter(_filters!.classifications, USPSAClassification.A, value);
        },
      ),
      CheckboxListTile(
        title: Text("B"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.classifications[USPSAClassification.B],
        onChanged: (bool? value) {
          _updateFilter(_filters!.classifications, USPSAClassification.B, value);
        },
      ),
      CheckboxListTile(
        title: Text("C"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.classifications[USPSAClassification.C],
        onChanged: (bool? value) {
          _updateFilter(_filters!.classifications, USPSAClassification.C, value);
        },
      ),
      CheckboxListTile(
        title: Text("D"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.classifications[USPSAClassification.D],
        onChanged: (bool? value) {
          _updateFilter(_filters!.classifications, USPSAClassification.D, value);
        },
      ),
      CheckboxListTile(
        title: Text("U"),
        controlAffinity: ListTileControlAffinity.leading,
        value: _filters!.classifications[USPSAClassification.U],
        onChanged: (bool? value) {
          _updateFilter(_filters!.classifications, USPSAClassification.U, value);
        },
      )
    ];
  }

  List<Widget> _settingsTiles(BuildContext context) {
    return [
      Tooltip(
        message: "If unchecked, results for shooters' second guns/reentries will be hidden.",
        child: CheckboxListTile(
          title: Text("Include 2nd Gun?"),
          controlAffinity: ListTileControlAffinity.leading,
          value: _filters!.reentries,
          onChanged: (bool? value) {
            setState(() {
              _filters!.reentries = value ?? false;
            });
          },
        ),
      ),
      Tooltip(
        message: "If checked, only shooters who match a checked item in every column will be shown. "
            "Otherwise, shooters who match any checked value will be shown.",
        child: CheckboxListTile(
            title: Text("Exclusive Filters?"),
            controlAffinity: ListTileControlAffinity.leading,
            value: _filters!.mode == FilterMode.and,
            onChanged: (bool? value) {
              setState(() {
                value! ? _filters!.mode = FilterMode.and : _filters!.mode = FilterMode.or;
              });
            }
        ),
      ),
      Tooltip(
        message: "If checked, disqualified shooters will be scored on stages they completed pre-DQ. "
            "Otherwise, disqualified shooters will be scored 0 on all stages.",
        child: CheckboxListTile(
            title: Text("Score DQs?"),
            controlAffinity: ListTileControlAffinity.leading,
            value: _filters!.scoreDQs,
            onChanged: (bool? value) {
              setState(() {
                _filters!.scoreDQs = value ?? false;
              });
            }
        ),
      ),
    ];
  }

  List<Widget> _actions(BuildContext context) {
    var spacing = MediaQuery.of(context).size.width > 775 ? 60.0 : 0.0;
    return [
      TextButton(
        child: Text("HANDGUNS"),
        onPressed: () {
          var filters = FilterSet();
          filters.reentries =_filters!.reentries;
          filters.scoreDQs = _filters!.scoreDQs;
          filters.divisions[USPSADivision.pcc] = false;

          setState(() {
            _filters = filters;
          });
        },
      ),
      TextButton(
        child: Text("HICAP"),
        onPressed: () {
          var filters = FilterSet();
          filters.reentries =_filters!.reentries;
          filters.scoreDQs = _filters!.scoreDQs;
          filters.divisions[USPSADivision.pcc] = false;
          filters.divisions[USPSADivision.limited10] = false;
          filters.divisions[USPSADivision.production] = false;
          filters.divisions[USPSADivision.singleStack] = false;
          filters.divisions[USPSADivision.revolver] = false;

          setState(() {
            _filters = filters;
          });
        },
      ),
      TextButton(
          child: Text("LOCAP"),
          onPressed: () {
            var filters = FilterSet();
            filters.reentries =_filters!.reentries;
            filters.scoreDQs = _filters!.scoreDQs;
            filters.divisions[USPSADivision.pcc] = false;
            filters.divisions[USPSADivision.open] = false;
            filters.divisions[USPSADivision.limited] = false;
            filters.divisions[USPSADivision.carryOptics] = false;

            setState(() {
              _filters = filters;
            });
          }
      ),
      SizedBox(width: spacing),
      TextButton(
        child: Text("ALL"),
        onPressed: () {
          bool? secondGun = _filters!.reentries;
          FilterMode mode = FilterMode.and;
          bool? scoreDQs = _filters!.scoreDQs;
          setState(() {
            _filters = FilterSet();
            _filters!.reentries = secondGun;
            _filters!.mode = mode;
            _filters!.scoreDQs = scoreDQs;
          });
        },
      ),
      TextButton(
        child: Text("NONE"),
        onPressed: () {
          bool? secondGun = _filters!.reentries;
          FilterMode mode = FilterMode.or;
          bool? scoreDQs = _filters!.scoreDQs;
          setState(() {
            _filters = FilterSet(empty: true);
            _filters!.reentries = secondGun;
            _filters!.mode = mode;
            _filters!.scoreDQs = scoreDQs;
          });
        },
      ),
      SizedBox(width: spacing),
      TextButton(
        child: Text("CANCEL"),
        onPressed: () {
          Navigator.of(context).pop(null);
        },
      ),
      TextButton(
        child: Text("APPLY"),
        onPressed: () {
          Navigator.of(context).pop(_filters);
        },
      )
    ];
  }
}