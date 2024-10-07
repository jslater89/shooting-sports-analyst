/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';

/// ScorecardSettingsDialog is a modal host for [ScorecardSettingsWidget].
class ScorecardSettingsDialog extends StatelessWidget {
  const ScorecardSettingsDialog({super.key, required this.scorecard, required this.match});

  final ScorecardModel scorecard;
  final ShootingMatch match;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Settings"),
      content: ScorecardSettingsWidget(scorecard: scorecard, match: match),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("CANCEL")),
        TextButton(onPressed: () => Navigator.of(context).pop(scorecard), child: const Text("SAVE")),
      ],
    );
  }

  static Future<ScorecardModel?> show(BuildContext context, {required ScorecardModel scorecard, required ShootingMatch match}) {
    return showDialog<ScorecardModel>(
      context: context,
      builder: (context) => ScorecardSettingsDialog(scorecard: scorecard, match: match),
      barrierDismissible: false,
    );
  }
}

/// ScorecardSettings edits the provided scorecard.
/// Edits happen in place, so use [ScorecardModel.copy] to get a copy if confirm/discard is needed.
class ScorecardSettingsWidget extends StatefulWidget {
  const ScorecardSettingsWidget({super.key, required this.scorecard, required this.match});

  final ScorecardModel scorecard;
  final ShootingMatch match;
  @override
  State<ScorecardSettingsWidget> createState() => _ScorecardSettingsWidgetState();
}

class _ScorecardSettingsWidgetState extends State<ScorecardSettingsWidget> {
  late ScorecardModel scorecard;

  TextEditingController nameController = TextEditingController();
  int scoreFilteredCount = 0;
  int displayFilteredCount = 0;

  @override
  void initState() {
    super.initState();
    scorecard = widget.scorecard;
    nameController.text = scorecard.name;
    var scoreFiltered = widget.match.applyFilterSet(scorecard.scoreFilters);
    scoreFilteredCount = scoreFiltered.length;
    
    var displayFiltered = scorecard.displayFilters.apply(widget.match);
    displayFilteredCount = displayFiltered.length;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "Name"),
          onChanged: (value) => scorecard.name = value,
        ),
        SizedBox(height: 16),
        Tooltip(
          message: "Scoring filters determine the set of shooters used to calculate scores for this scorecard.",
          child: Text("Scoring filters match $scoreFilteredCount of ${widget.match.shooters.length} competitors.")
        ),
        TextButton(
          child: Text("EDIT SCORING FILTERS"),
          onPressed: () async {
            var filters = await FilterDialog.show(context, scorecard.scoreFilters);
            if(filters != null) {
              scorecard.scoreFilters = filters;
              var scoreFiltered = widget.match.applyFilterSet(scorecard.scoreFilters);
              setState(() {
                scoreFilteredCount = scoreFiltered.length;
              });
            }
          },
        ),
        SizedBox(height: 16),
        Tooltip(
          message: "Display filters determine the set of shooters shown on this scorecard.",
          child: Text("Display filters match $displayFilteredCount of ${widget.match.shooters.length} competitors."),
        ),
        TextButton(
          child: Text("EDIT DISPLAY FILTERS"),
          onPressed: () async {
            var filters = await FilterDialog.show(context, scorecard.displayFilters.filterSet 
                ?? FilterSet(widget.match.sport, empty: true)
                  ..mode = FilterMode.or
                  ..knownSquads = widget.match.sortedSquadNumbers
            );
            scorecard.displayFilters.filterSet = filters;

            var displayFiltered = scorecard.displayFilters.apply(widget.match);
            setState(() {
              displayFilteredCount = displayFiltered.length;
            });
          },
        ),
        TextButton(
          child: Text("SELECT COMPETITORS"),
          onPressed: () async {
            var competitors = await MatchEntrySelectDialog.show(
              context, 
              match: widget.match, 
              filters: scorecard.displayFilters.filterSet ?? FilterSet(widget.match.sport),
              previousSelection: scorecard.displayFilters.entryIds ?? <int>[],
            );
            if(competitors != null) {
              scorecard.displayFilters.entryIds = competitors.map((e) => e.entryId).toList();
              if(competitors.isEmpty) {
                scorecard.displayFilters.entryIds = null;
              }

              var displayFiltered = scorecard.displayFilters.apply(widget.match);
              setState(() {
                displayFilteredCount = displayFiltered.length;
              });
            }
          },
        )
      ],
    );
  }
}

class MatchEntrySelectDialog extends StatefulWidget {
  const MatchEntrySelectDialog({super.key, required this.match, required this.filters, required this.previousSelection});

  final ShootingMatch match;
  final FilterSet filters;
  final List<int> previousSelection;

  @override
  State<MatchEntrySelectDialog> createState() => _MatchEntrySelectDialogState();

  static Future<List<MatchEntry>?> show(BuildContext context, {required ShootingMatch match, required FilterSet filters, required List<int> previousSelection}) {
    return showDialog<List<MatchEntry>>(
      context: context,
      builder: (context) => MatchEntrySelectDialog(match: match, filters: filters, previousSelection: previousSelection),
    );
  }
}

class _MatchEntrySelectDialogState extends State<MatchEntrySelectDialog> {
  List<MatchEntry> selectedEntries = [];
  List<MatchEntry> baseEntries = [];
  List<MatchEntry> shooters = [];

  String search = "";

  @override
  void initState() {
    super.initState();
    baseEntries = widget.match.applyFilterSet(widget.filters);
    baseEntries.sort((a, b) => a.lastName.compareTo(b.lastName));
    shooters = baseEntries;
    selectedEntries = baseEntries.where((e) => widget.previousSelection.contains(e.entryId)).toList();
  }

  void _updateSearch(String value) {
    setState(() {
      shooters = baseEntries.where((e) => e.getName(suffixes: false).toLowerCase().contains(value.toLowerCase())).toList();
      search = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Select competitors"),
      content: SizedBox(
        width: 400,
        height: 600,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(labelText: "Search"),
              onChanged: (value) => _updateSearch(value),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shooters.length,
                itemBuilder: (context, index) {
                  var shooter = shooters[index];
                  return CheckboxListTile(
                    value: selectedEntries.contains(shooter),
                    title: Text(shooter.name),
                    onChanged: (value) {
                      setState(() {
                        if(value == true) {
                          selectedEntries.add(shooter);
                        } 
                        else {
                          selectedEntries.remove(shooter);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(<MatchEntry>[]),
              child: const Text("CLEAR"),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("CANCEL"),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(selectedEntries),
                  child: const Text("SAVE"),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}