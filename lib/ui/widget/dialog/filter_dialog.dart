/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/jsonutils.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

part 'filter_dialog.g.dart';

@JsonSerializable()
class FilterSet {
  @JsonKey(toJson: sportToJson, fromJson: sportFromJson)
  Sport sport;
  FilterMode mode = FilterMode.and;
  bool reentries = true;
  bool scoreDQs = true;
  bool femaleOnly = false;

  @JsonKey(toJson: divisionMapToJson, includeToJson: true, includeFromJson: false)
  late Map<Division, bool> divisions;
  @JsonKey(toJson: classificationMapToJson, includeToJson: true, includeFromJson: false)
  late Map<Classification, bool> classifications;
  @JsonKey(toJson: powerFactorMapToJson, includeToJson: true, includeFromJson: false)
  late Map<PowerFactor, bool> powerFactors;
  @JsonKey(toJson: ageCategoryMapToJson, includeToJson: true, includeFromJson: false)
  late Map<AgeCategory, bool> ageCategories;
  List<int> squads = [];
  List<int> knownSquads;

  FilterSet(this.sport, {bool empty = false, this.knownSquads = const []}) {
    divisions = {};
    classifications = {};
    powerFactors = {};
    ageCategories = {};

    for (Division d in sport.divisions.values) {
      divisions[d] = !empty;
    }

    for (Classification c in sport.classifications.values) {
      classifications[c] = !empty;
    }

    for (PowerFactor f in sport.powerFactors.values) {
      powerFactors[f] = !empty;
    }

    for (AgeCategory c in sport.ageCategories.values) {
      ageCategories[c] = false;
    }

    if(!empty) {
      squads = knownSquads;
    }
  }

  Iterable<Division> get activeDivisions => divisions.keys.where((div) => divisions[div] ?? false);
  Iterable<Classification> get activeClassifications => classifications.keys.where((c) => classifications[c] ?? false);
  Iterable<PowerFactor> get activePowerFactors => powerFactors.keys.where((f) => powerFactors[f] ?? false);
  Iterable<AgeCategory> get activeAgeCategories => ageCategories.keys.where((c) => ageCategories[c] ?? false);

  Map<Division, bool> divisionListToMap(List<Division> divisions) {
    Map<Division, bool> map = {};
    for(var d in sport.divisions.values) {
      map[d] = divisions.contains(d);
    }

    return map;
  }

  FilterSet copy() {
    return FilterSet.fromJson(toJson());
  }

  factory FilterSet.fromJson(Map<String, dynamic> json) {
    var set = _$FilterSetFromJson(json);
    var divisionMap = json['divisions'] as Map<String, dynamic>;
    set.divisions = divisionMapFromJson(set.sport, divisionMap);

    var classificationMap = json['classifications'] as Map<String, dynamic>;
    set.classifications = classificationMapFromJson(set.sport, classificationMap);

    var powerFactorMap = json['powerFactors'] as Map<String, dynamic>;
    set.powerFactors = powerFactorMapFromJson(set.sport, powerFactorMap);

    var ageCategoryMap = json['ageCategories'] as Map<String, dynamic>;
    set.ageCategories = ageCategoryMapFromJson(set.sport, ageCategoryMap);
    return set;
  }

  Map<String, dynamic> toJson() {
    return _$FilterSetToJson(this);
  }
}

class FilterDialog extends StatefulWidget {
  final FilterSet currentFilters;
  final bool showDivisions;

  const FilterDialog({Key? key, required this.currentFilters, this.showDivisions = true}) : super(key: key);
  @override
  State<FilterDialog> createState() {
    return _FilterDialogState();
  }

  static Future<FilterSet?> show(BuildContext context, FilterSet currentFilters) {
    return showDialog<FilterSet>(context: context, builder: (context) => FilterDialog(currentFilters: currentFilters));
  }
}

class _FilterDialogState extends State<FilterDialog> {

  late FilterSet _filters;
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
                    children: [
                      if(_filters.sport.hasPowerFactors) ..._powerFactorTiles(context),
                      if(_filters.sport.hasPowerFactors) Divider(),
                      ..._otherTiles(context),
                    ],
                  ),
                ),
                if(widget.showDivisions) SizedBox(width: 20),
                if(widget.showDivisions) Expanded(
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
            children: [
              ..._powerFactorTiles(context),
              if(widget.showDivisions) SizedBox(height: 10),
              if(widget.showDivisions) ..._divisionTiles(context),
              SizedBox(height: 10),
              ..._classTiles(context),
              SizedBox(height: 10),
              ..._otherTiles(context),
              Divider(),
              ..._settingsTiles(context),
            ]
          ),
        ),
      ),
      actions: _actions(context),
    );
  }

  List<Widget> _powerFactorTiles(BuildContext context) {
    return [
      Text("Power Factors", style: Theme.of(context).textTheme.subtitle1!.apply(decoration: TextDecoration.underline)),
      for(var pf in _filters.sport.powerFactors.values)
        CheckboxListTile(
          title: Text(pf.displayName),
          controlAffinity: ListTileControlAffinity.leading,
          value: _filters.powerFactors[pf],
          onChanged: (bool? value) {
            _updateFilter(_filters.powerFactors, pf, value);
          },
        ),
    ];
  }

  List<Widget> _otherTiles(BuildContext context) {
    return [
      Text("Categories", style: Theme.of(context).textTheme.subtitle1!.apply(decoration: TextDecoration.underline)),
      Tooltip(
        message: "Include only female competitors.",
        child: CheckboxListTile(
          title: Text("Lady"),
          controlAffinity: ListTileControlAffinity.leading,
          value: _filters.femaleOnly,
          onChanged: (bool? value) {
            if(value != null) {
              setState(() {
                _filters.femaleOnly = value;
              });
            }
          },
        ),
      ),
      for(var cat in _filters.sport.ageCategories.values)
        CheckboxListTile(
          title: Text(cat.name),
          controlAffinity: ListTileControlAffinity.leading,
          value: _filters.ageCategories[cat],
          onChanged: (bool? value) {
            if(value != null) {
              setState(() {
                _filters.ageCategories[cat] = value;
              });
            }
          },
        ),
    ];
  }

  List<Widget> _divisionTiles(BuildContext context) {
    return [
      Text("Divisions", style: Theme.of(context).textTheme.subtitle1!.apply(decoration: TextDecoration.underline)),
      for(var division in _filters.sport.divisions.values)
        CheckboxListTile(
          title: Text(division.displayName),
          controlAffinity: ListTileControlAffinity.leading,
          value: _filters.divisions[division],
          onChanged: (bool? value) {
            _updateFilter(_filters.divisions, division, value);
          },
        ),
    ];
  }

  List<Widget> _classTiles(BuildContext context) {
    return [
      Text("Classes", style: Theme.of(context).textTheme.subtitle1!.apply(decoration: TextDecoration.underline)),
      for(var classification in _filters.sport.classifications.values)
        CheckboxListTile(
          title: Text(classification.shortDisplayName),
          controlAffinity: ListTileControlAffinity.leading,
          value: _filters.classifications[classification],
          onChanged: (bool? value) {
            _updateFilter(_filters.classifications, classification, value);
          },
        ),
    ];
  }

  List<Widget> _settingsTiles(BuildContext context) {
    return [
      Tooltip(
        message: "If unchecked, results for shooters' second guns/reentries will be hidden.",
        child: CheckboxListTile(
          title: Text("Include 2nd Gun?"),
          controlAffinity: ListTileControlAffinity.leading,
          value: _filters.reentries,
          onChanged: (bool? value) {
            setState(() {
              _filters.reentries = value ?? false;
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
            value: _filters.mode == FilterMode.and,
            onChanged: (bool? value) {
              setState(() {
                value! ? _filters.mode = FilterMode.and : _filters.mode = FilterMode.or;
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
            value: _filters.scoreDQs,
            onChanged: (bool? value) {
              setState(() {
                _filters.scoreDQs = value ?? false;
              });
            }
        ),
      ),
    ];
  }

  List<Widget> _actions(BuildContext context) {
    var spacing = MediaQuery.of(context).size.width > 775 ? 55.0 : 0.0;
    return [
      if(_filters.knownSquads.isNotEmpty) TextButton(
        child: Text("SQUADS (${_filters.squads.length})"),
        onPressed: () async {
          var squads = await SquadSelectDialog.show(context, knownSquads: _filters.knownSquads, selectedSquads: _filters.squads);

          if(squads != null) {
            setState(() {
              _filters.squads = squads;
            });
          }
        },
      ),
      if(_filters.knownSquads.isNotEmpty) SizedBox(width: spacing),
      TextButton(
        child: Text("HANDGUNS"),
        onPressed: _filters.sport != uspsaSport ? null : () {
          var filters = FilterSet(_filters.sport);
          filters.reentries =_filters.reentries;
          filters.scoreDQs = _filters.scoreDQs;
          filters.knownSquads = _filters.knownSquads;
          filters.squads = _filters.squads;
          filters.divisions[uspsaSport.divisions.lookupByName("PCC")!] = false;

          setState(() {
            _filters = filters;
          });
        },
      ),
      TextButton(
        child: Text("HICAP"),
        onPressed: _filters.sport != uspsaSport ? null : () {
          var filters = FilterSet(_filters.sport);
          filters.reentries =_filters.reentries;
          filters.scoreDQs = _filters.scoreDQs;
          filters.knownSquads = _filters.knownSquads;
          filters.squads = _filters.squads;
          filters.divisions[uspsaSport.divisions.lookupByName("PCC")!] = false;
          filters.divisions[uspsaSport.divisions.lookupByName("L10")!] = false;
          filters.divisions[uspsaSport.divisions.lookupByName("PROD")!] = false;
          filters.divisions[uspsaSport.divisions.lookupByName("SS")!] = false;
          filters.divisions[uspsaSport.divisions.lookupByName("REVO")!] = false;

          setState(() {
            _filters = filters;
          });
        },
      ),
      TextButton(
          child: Text("LOCAP"),
          onPressed: _filters.sport != uspsaSport ? null : () {
            var filters = FilterSet(_filters.sport);
            filters.reentries =_filters.reentries;
            filters.scoreDQs = _filters.scoreDQs;
            filters.knownSquads = _filters.knownSquads;
            filters.squads = _filters.squads;
            filters.divisions[uspsaSport.divisions.lookupByName("PCC")!] = false;
            filters.divisions[uspsaSport.divisions.lookupByName("OPEN")!] = false;
            filters.divisions[uspsaSport.divisions.lookupByName("LIM")!] = false;
            filters.divisions[uspsaSport.divisions.lookupByName("LO")!] = false;
            filters.divisions[uspsaSport.divisions.lookupByName("CO")!] = false;

            setState(() {
              _filters = filters;
            });
          }
      ),
      SizedBox(width: spacing),
      TextButton(
        child: Text("ALL"),
        onPressed: () {
          bool? secondGun = _filters.reentries;
          FilterMode mode = FilterMode.and;
          bool? scoreDQs = _filters.scoreDQs;
          List<int> knownSquads = _filters.knownSquads;
          List<int> squads = _filters.squads;
          setState(() {
            _filters = FilterSet(_filters.sport);
            _filters.reentries = secondGun;
            _filters.mode = mode;
            _filters.scoreDQs = scoreDQs;
            _filters.knownSquads = knownSquads;
            _filters.squads = squads;
          });
        },
      ),
      TextButton(
        child: Text("NONE"),
        onPressed: () {
          bool? secondGun = _filters.reentries;
          FilterMode mode = FilterMode.or;
          bool? scoreDQs = _filters.scoreDQs;
          List<int> knownSquads = _filters.knownSquads;
          List<int> squads = _filters.squads;
          setState(() {
            _filters = FilterSet(_filters.sport, empty: true);
            _filters.reentries = secondGun;
            _filters.mode = mode;
            _filters.scoreDQs = scoreDQs;
            _filters.knownSquads = knownSquads;
            _filters.squads = squads;
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

class SquadSelectDialog extends StatefulWidget {
  const SquadSelectDialog({super.key, required this.knownSquads, this.selectedSquads = const []});

  final List<int> knownSquads;
  final List<int> selectedSquads;

  @override
  State<SquadSelectDialog> createState() => _SquadSelectDialogState();

  static Future<List<int>?> show(BuildContext context, {required List<int> knownSquads, List<int> selectedSquads = const []}) {
    return showDialog(context: context, builder: (context) => SquadSelectDialog(knownSquads: knownSquads, selectedSquads: selectedSquads));
  }
}

class _SquadSelectDialogState extends State<SquadSelectDialog> {
  Map<int, bool> selected = {};

  @override
  void initState() {
    super.initState();

    for(var s in widget.knownSquads) {
      selected[s] = widget.selectedSquads.contains(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [
      Text("Select squads to include in scoring."),
      SizedBox(height: 10),
    ]..addAll(
        selected.keys.map(
            (int s) => CheckboxListTile(value: selected[s], onChanged: (v) => _toggle(s, v), title: Text("$s"))
        )
    );


    return AlertDialog(
      title: Text("Select Squads"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
      actions: [
        TextButton(
          child: Text("ALL"),
          onPressed: () {
            setState(() {
              selected.keys.forEach((squad) => selected[squad] = true);
            });

          },
        ),
        TextButton(
          child: Text("NONE"),
          onPressed: () {
            setState(() {
              selected.keys.forEach((squad) => selected[squad] = false);
            });
          },
        ),
        SizedBox(width: 50),
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop(null);
          },
        ),
        TextButton(
          child: Text("APPLY"),
          onPressed: () {
            Navigator.of(context).pop(selected.keys.toList()..retainWhere((squad) => selected[squad]!));
          },
        )
      ],
    );
  }

  void _toggle(int s, bool? value) {
    setState(() {
      selected[s] = value ?? false;
    });
  }
}
