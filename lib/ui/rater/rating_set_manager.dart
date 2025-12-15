/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/rating_sets.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_set.dart';
import 'package:shooting_sports_analyst/data/help/entries/rating_set_help.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_select_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/text_input_dialog.dart';

SSALogger _log = SSALogger("RatingSetManager");

class RatingSetManagerDialog extends StatefulWidget {
  const RatingSetManagerDialog({super.key, required this.db, required this.validRatings, this.initialSelection = const []});

  final AnalystDatabase db;
  final List<ShooterRating> validRatings;
  final List<RatingSet> initialSelection;

  @override
  State<RatingSetManagerDialog> createState() => _RatingSetManagerDialogState();

  static Future<List<RatingSet>?> show(BuildContext context, {required AnalystDatabase db, required List<ShooterRating> validRatings, List<RatingSet> initialSelection = const []}) {
    return showDialog<List<RatingSet>>(context: context, builder: (context) => RatingSetManagerDialog(db: db, validRatings: validRatings, initialSelection: initialSelection));
  }
}

class _RatingSetManagerDialogState extends State<RatingSetManagerDialog> {
  late _RatingSetManagerModel _model;

  @override
  void initState() {
    super.initState();
    _model = _RatingSetManagerModel();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Rating sets"),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.upload),
                onPressed: () async {
                  var fileContents = await HtmlOr.pickAndReadFileNow();
                  if(fileContents != null) {
                    var set = RatingSet.fromJson(jsonDecode(fileContents));
                    AnalystDatabase().saveRatingSetSync(set);
                    _model.availableSetsChanged();
                  }
                },
              ),
              HelpButton(helpTopicId: ratingSetsHelpId),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: MediaQuery.of(context).size.height * 0.8,
        child: ChangeNotifierProvider.value(
          value: _model,
          builder: (context, _) => RatingSetManager(db: widget.db, initialSelection: widget.initialSelection, validRatings: widget.validRatings),
        ),
      ),
      actions: [
        TextButton(
          child: Text("CLEAR"),
          onPressed: () => Navigator.of(context).pop(<RatingSet>[]),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("CANCEL"),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_model.selectedSets),
          child: Text("APPLY"),
        ),
      ],
    );
  }
}

class RatingSetManager extends StatefulWidget {
  const RatingSetManager({super.key, required this.db, required this.validRatings, this.initialSelection = const []});

  final AnalystDatabase db;
  final List<ShooterRating> validRatings;
  final List<RatingSet> initialSelection;

  @override
  State<RatingSetManager> createState() => _RatingSetManagerState();
}

class _RatingSetManagerState extends State<RatingSetManager> {
  List<RatingSet> ratingSets = [];
  List<RatingSet> selectedRatingSets = [];

  late _RatingSetManagerModel model;

  @override
  void initState() {
    super.initState();
    model = context.read<_RatingSetManagerModel>();
    ratingSets = widget.db.getRatingSetsSync();
    var initialSetIds = widget.initialSelection.map((s) => s.id).toList();
    selectedRatingSets = ratingSets.where((s) => initialSetIds.contains(s.id)).toList();
    if(selectedRatingSets.isNotEmpty) {
      model.selectionChanged(selectedRatingSets);
    }

    model.addListener(_handleSetChange);
  }

  void _handleSetChange() {
    if(!model.handledSetChange) {
      _log.i("Handling set change");
      setState(() {
        ratingSets = widget.db.getRatingSetsSync();
        model.handledSetChange = true;
        _log.i("New set count: ${ratingSets.length}");
      });
    }
  }

  @override
  void dispose() {
    model.removeListener(_handleSetChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var model = context.watch<_RatingSetManagerModel>();
    return Column(
      children: [
        TextButton(
          child: Text("CREATE NEW"),
          onPressed: () async {
            var ratingSelection = await RatingSelectDialog.show(context, ratings: widget.validRatings);
            if(ratingSelection != null) {
              var set = RatingSet.create();
              set.memberNumbers = ratingSelection.map((r) => r.memberNumber).toList();
              setState(() {
                ratingSets.add(set);
              });
              widget.db.saveRatingSetSync(set);
            }
          },
        ),
        Expanded(
          child: ListView.builder(
            itemBuilder: (context, index) => CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              secondary: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: "Name the rating set",
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.text_increase),
                      onPressed: () async {
                        var set = ratingSets[index];
                        var name = await TextInputDialog.show(context, title: "Enter name", initialValue: set.name);
                        if(name != null) {
                          setState(() {
                            set.name = name;
                          });
                          widget.db.saveRatingSetSync(set);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.edit),
                    onPressed: () async {
                      var ratingSelection = await RatingSelectDialog.show(context, ratings: widget.validRatings);
                      if(ratingSelection != null) {
                        var set = ratingSets[index];
                        set.memberNumbers = ratingSelection.map((r) => r.memberNumber).toList();
                        set.cleanMatchingNames();
                        setState(() {
                          ratingSets[index] = set;
                        });
                        widget.db.saveRatingSetSync(set);
                      }
                    },
                  ),
                  Tooltip(
                    message: "Export rating set",
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.download),
                      onPressed: () async {
                        var filename = "${ratingSets[index].displayName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), "")}.json";
                        HtmlOr.saveFile(filename, jsonEncode(ratingSets[index].toJson()));
                      },
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete),
                    onPressed: () async {
                      var confirm = await ConfirmDialog.show(context, content: Text("Delete ${ratingSets[index].displayName}?"));
                      if(confirm ?? false) {
                        var set = ratingSets[index];
                        widget.db.deleteRatingSetSync(set);
                        if(selectedRatingSets.contains(set)) {
                          selectedRatingSets.remove(set);
                          model.selectionChanged(selectedRatingSets);
                        }
                        setState(() {
                          ratingSets.removeAt(index);
                        });
                      }
                    },
                  ),
                ],
              ),
              value: selectedRatingSets.contains(ratingSets[index]),
              onChanged: (value) {
                setState(() {
                  if(value ?? false) {
                    selectedRatingSets.add(ratingSets[index]);
                  }
                  else {
                    selectedRatingSets.remove(ratingSets[index]);
                  }
                  model.selectionChanged(selectedRatingSets);
                });
              },
              title: Text(ratingSets[index].displayName, overflow: TextOverflow.ellipsis),
            ),
            itemCount: ratingSets.length,
          ),
        ),
      ],
    );
  }
}

class _RatingSetManagerModel with ChangeNotifier {
  // Parents should call this when available sets change.
  void availableSetsChanged() {
    handledSetChange = false;
    notifyListeners();
  }

  bool handledSetChange = true;

  // The manager will call this when the selection changes.
  void selectionChanged(List<RatingSet> sets) {
    notifyListeners();
    _selectedSets = [...sets];
  }

  List<RatingSet> get selectedSets => _selectedSets;
  List<RatingSet> _selectedSets = [];
}