/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/match_prediction_mode.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_model.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';

SSALogger _log = SSALogger("ScorecardSettingsDialog");

/// ScorecardSettingsDialog is a modal host for [ScorecardSettingsWidget].
class ScorecardSettingsDialog extends StatelessWidget {
  const ScorecardSettingsDialog({super.key, required this.scorecard, required this.match, this.ratingsContext});

  final ScorecardModel scorecard;
  final ShootingMatch match;
  final DbRatingProject? ratingsContext;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Settings"),
      content: ScorecardSettingsWidget(scorecard: scorecard, match: match, ratingsContext: ratingsContext),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("CANCEL")),
        TextButton(onPressed: () => Navigator.of(context).pop(scorecard), child: const Text("SAVE")),
      ],
    );
  }

  static Future<ScorecardModel?> show(BuildContext context, {
    required ScorecardModel scorecard,
    required ShootingMatch match,
    DbRatingProject? ratingsContext,
  }) {
    _log.i("Showing scorecard settings dialog for ${scorecard.name} id:${scorecard.id}");
    return showDialog<ScorecardModel>(
      context: context,
      builder: (context) => ScorecardSettingsDialog(scorecard: scorecard, match: match, ratingsContext: ratingsContext),
      barrierDismissible: false,
    );
  }
}

/// ScorecardSettings edits the provided scorecard.
/// Edits happen in place, so use [ScorecardModel.copy] to get a copy if confirm/discard is needed.
class ScorecardSettingsWidget extends StatefulWidget {
  const ScorecardSettingsWidget({super.key, required this.scorecard, required this.match, this.ratingsContext});

  final ScorecardModel scorecard;
  final ShootingMatch match;
  final DbRatingProject? ratingsContext;

  @override
  State<ScorecardSettingsWidget> createState() => _ScorecardSettingsWidgetState();
}

class _ScorecardSettingsWidgetState extends State<ScorecardSettingsWidget> {
  late ScorecardModel scorecard;

  TextEditingController nameController = TextEditingController();
  TextEditingController topNController = TextEditingController();
  int scoreFilteredCount = 0;
  int displayFilteredCount = 0;

  @override
  void initState() {
    super.initState();
    scorecard = widget.scorecard;
    nameController.text = scorecard.name;

    _applyScoreFilters();
    _applyDisplayFilters();

    topNController.text = scorecard.displayFilters.topN?.toString() ?? "";
  }

  void _applyScoreFilters() {
    var scoreFiltered = scorecard.fullScoreFilters.apply(widget.match);

    if(scorecard.fullScoreFilters.entryIds != null) {
      scoreFilteredCount = min(scoreFilteredCount, scorecard.fullScoreFilters.entryIds!.length);
    }
    if(scorecard.fullScoreFilters.entryUuids != null) {
      scoreFilteredCount = min(scoreFilteredCount, scorecard.fullScoreFilters.entryUuids!.length);
    }
    scoreFilteredCount = scoreFiltered.length;
  }

  void _applyDisplayFilters() {
    var displayFiltered = scorecard.displayFilters.apply(widget.match);
    displayFilteredCount = displayFiltered.length;
    displayFilteredCount = min(displayFilteredCount, scoreFilteredCount);
    if(scorecard.displayFilters.topN != null) {
      displayFilteredCount = min(displayFilteredCount, scorecard.displayFilters.topN!);
    }
    if(scorecard.displayFilters.entryIds != null) {
      displayFilteredCount = min(displayFilteredCount, scorecard.displayFilters.entryIds!.length);
    }
    if(scorecard.displayFilters.entryUuids != null) {
      displayFilteredCount = min(displayFilteredCount, scorecard.displayFilters.entryUuids!.length);
    }
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
            if(scorecard.scoreFilters.knownSquads.isEmpty) {
              scorecard.scoreFilters.knownSquads = widget.match.squadNumbers.toList();
              scorecard.scoreFilters.knownSquads.sort();
            }
            var filters = await FilterDialog.show(context, scorecard.scoreFilters);
            if(filters != null) {
              scorecard.fullScoreFilters.filterSet = filters;
              _applyScoreFilters();

              if(scorecard.displayFilters.isEmpty) {
                scorecard.displayFilters.filterSet = scorecard.fullScoreFilters.filterSet?.copy();
              }
              _applyDisplayFilters();

              setState(() {
              });
            }
          },
        ),
        TextButton(
          child: Text("SELECT COMPETITORS"),
          onPressed: () async {
            var previouslySelectedInts = scorecard.fullScoreFilters.entryIds;
            var previouslySelectedStrings = scorecard.fullScoreFilters.entryUuids;

            List<MatchEntry>? competitors;
            if(previouslySelectedStrings != null) {
              competitors = await MatchEntrySelectDialog.show<String>(
                context,
                match: widget.match,
                filters: scorecard.fullScoreFilters.filterSet ?? FilterSet(widget.match.sport),
                previousSelection: previouslySelectedStrings,
              );
            }
            else {
              competitors = await MatchEntrySelectDialog.show<int>(
                context,
                match: widget.match,
                filters: scorecard.fullScoreFilters.filterSet ?? FilterSet(widget.match.sport),
                previousSelection: previouslySelectedInts ?? <int>[],
              );
            }
            if(competitors != null) {
              if(competitors.every((e) => e.sourceId != null)) {
                scorecard.fullScoreFilters.entryUuids = competitors.map((e) => e.sourceId!).toList();
                scorecard.fullScoreFilters.entryIds = null;
                _log.vv("Using source IDs");
              }
              else {
                scorecard.fullScoreFilters.entryIds = competitors.map((e) => e.entryId).toList();
                scorecard.fullScoreFilters.entryUuids = null;
                _log.vv("Using entry IDs");
              }
              if(competitors.isEmpty) {
                scorecard.fullScoreFilters.entryUuids = null;
                scorecard.fullScoreFilters.entryIds = null;
                _log.vv("No competitors selected, resetting competitor filter");
              }

              _applyScoreFilters();
              setState(() {});
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
            if(scorecard.displayFilters.filterSet?.knownSquads.isEmpty ?? false) {
              scorecard.displayFilters.filterSet!.knownSquads = widget.match.squadNumbers.toList();
              scorecard.displayFilters.filterSet!.knownSquads.sort();
            }
            var filters = await FilterDialog.show(context, scorecard.displayFilters.filterSet
              ?? FilterSet(widget.match.sport, empty: true));

            // returns null on cancel
            if(filters == null) {
              return;
            }

            if(filters.isEmpty) {
              scorecard.displayFilters.filterSet = null;
            }

            scorecard.displayFilters.filterSet = filters;
            setState(() {
              _applyDisplayFilters();
            });
          },
        ),
        TextButton(
          child: Text("SELECT COMPETITORS"),
          onPressed: () async {
            var previouslySelectedInts = scorecard.displayFilters.entryIds;
            var previouslySelectedStrings = scorecard.displayFilters.entryUuids;

            List<MatchEntry>? competitors;
            if(previouslySelectedStrings != null) {
              competitors = await MatchEntrySelectDialog.show<String>(
                context,
                match: widget.match,
                filters: scorecard.displayFilters.filterSet ?? FilterSet(widget.match.sport),
                previousSelection: previouslySelectedStrings,
              );
            }
            else {
              competitors = await MatchEntrySelectDialog.show<int>(
                context,
                match: widget.match,
                filters: scorecard.displayFilters.filterSet ?? FilterSet(widget.match.sport),
                previousSelection: previouslySelectedInts ?? <int>[],
              );
            }
            if(competitors != null) {
              if(competitors.every((e) => e.sourceId != null)) {
                scorecard.displayFilters.entryUuids = competitors.map((e) => e.sourceId!).toList();
                scorecard.displayFilters.entryIds = null;
                _log.vv("Using source IDs");
              }
              else {
                scorecard.displayFilters.entryIds = competitors.map((e) => e.entryId).toList();
                scorecard.displayFilters.entryUuids = null;
                _log.vv("Using entry IDs");
              }
              if(competitors.isEmpty) {
                scorecard.displayFilters.entryUuids = null;
                scorecard.displayFilters.entryIds = null;
                _log.vv("No competitors selected, resetting competitor filter");
              }

              _applyDisplayFilters();
              setState(() {});
            }
          },
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: "Limit to top N competitors",
                  hintText: "Enter a number",
                  errorText: scorecard.displayFilters.topN != null && int.tryParse(scorecard.displayFilters.topN.toString()) == null
                      ? "Please enter a valid positive integer"
                      : null,
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() {
                    if (value.isEmpty) {
                      setState(() {
                        scorecard.displayFilters.topN = null;
                        _applyDisplayFilters();
                      });
                    }
                    else {
                      int? parsed = int.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        setState(() {
                          scorecard.displayFilters.topN = parsed;
                          _applyDisplayFilters();
                        });
                      }
                    }
                  });
                },
                controller: topNController,
              ),
            ),
            TextButton(
              child: Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  scorecard.displayFilters.topN = null;
                  _applyDisplayFilters();
                });
              },
            ),
          ],
        ),
        DropdownButtonFormField<MatchPredictionMode>(
          value: scorecard.predictionMode,
          decoration: const InputDecoration(labelText: "Prediction mode"),
          items: MatchPredictionMode.dropdownValues(widget.ratingsContext != null).map((mode) => DropdownMenuItem(
            value: mode,
            child: Text(mode.uiLabel),
          )).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                  scorecard.predictionMode = value;
              });
            }
          },
        ),
        CheckboxListTile(
          title: const Text("Show horizontal scrollbar"),
          value: scorecard.hasHorizontalScrollbar,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (value) {
            if(value != null) {
              setState(() {
                scorecard.hasHorizontalScrollbar = value;
              });
            }
          },
        ),
      ],
    );
  }
}

/// MatchEntrySelectDialog selects match entries from a match's shooters.
///
/// If T is String, the dialog will use [MatchEntry.sourceId] as the unique identifier. Otherwise,
/// it will use [MatchEntry.entryId].
///
/// If T is String but some entries have null source IDs, this dialog will throw an exception.
class MatchEntrySelectDialog<T> extends StatefulWidget {
  const MatchEntrySelectDialog({super.key, required this.match, required this.filters, required this.previousSelection});

  final ShootingMatch match;
  final FilterSet filters;
  final List<T> previousSelection;

  @override
  State<MatchEntrySelectDialog<T>> createState() => _MatchEntrySelectDialogState<T>();

  static Future<List<MatchEntry>?> show<T>(BuildContext context, {required ShootingMatch match, required FilterSet filters, required List<T> previousSelection}) {
    return showDialog<List<MatchEntry>>(
      context: context,
      builder: (context) => MatchEntrySelectDialog<T>(match: match, filters: filters, previousSelection: previousSelection),
    );
  }
}

class _MatchEntrySelectDialogState<T> extends State<MatchEntrySelectDialog<T>> {
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

    _log.vv("T is ${T.toString()}");
    if(T == String) {
      selectedEntries = baseEntries.where((e) => widget.previousSelection.contains(e.sourceId!)).toList();
    }
    else {
      selectedEntries = baseEntries.where((e) => widget.previousSelection.contains(e.entryId)).toList();
    }

    if(T == String) {
      _log.vv("Matched ${selectedEntries.length} of ${baseEntries.length} shooters using source IDs");
    }
    else {
      _log.vv("Matched ${selectedEntries.length} of ${baseEntries.length} shooters using entry IDs");
    }
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
