/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/registrations.dart';
import 'package:shooting_sports_analyst/data/database/schema/registration.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/registration_parser.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("AssocRegistrationsDialog");

class AssociateRegistrationsDialog extends StatefulWidget {
  const AssociateRegistrationsDialog({Key? key, required this.registrations, required this.possibleMappings}) : super(key: key);

  final RegistrationResult registrations;
  final List<ShooterRating> possibleMappings;

  @override
  State<AssociateRegistrationsDialog> createState() => _AssociateRegistrationsDialogState();
}

class _AssociateRegistrationsDialogState extends State<AssociateRegistrationsDialog> {
  late Map<Registration, ShooterRating> selectedMappings;
  late List<ShooterRating> remainingOptions;
  bool persistMappings = true;

  @override
  void initState() {
    super.initState();
    widget.registrations.unmatchedShooters.sort((a, b) => a.classification.index.compareTo(b.classification.index));

    selectedMappings = {};
    remainingOptions = []..addAll(widget.possibleMappings);
    loadSavedMappings();
  }

  List<Registration> deletedMappings = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Map registrations"),
      content: SizedBox(
        width: 800,
        child: Container(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("The following shooters could not be automatically matched. Use the autocomplete text boxes to link them to existing "
                  "ratings, or leave the text boxes blank to leave them out of the prediction."),
              CheckboxListTile(
                title: Text("Save mappings?"),
                value: persistMappings,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) {
                  setState(() => persistMappings = value ?? false);
                },
              ),
              Expanded(
                child: ListView(
                  children: widget.registrations.unmatchedShooters.map((unmatched) {
                    var enabled = true;
                    var currentMapping = selectedMappings[unmatched];
                    var controller = TextEditingController();
                    if(currentMapping != null) {
                      controller.text = _formatMapping(unmatched, currentMapping);
                      enabled = false;
                    }

                    return StatefulBuilder(
                      builder: (context, setState) {
                        return Row(
                          children: [
                            Expanded(child: Text("${unmatched.name} (${unmatched.division.displayName} ${unmatched.classification.displayName})")),
                            Expanded(
                              child: SizedBox(
                                width: 250,
                                child: TypeAheadField<ShooterRating>(
                                  suggestionsCallback: (search) {
                                    var matches = remainingOptions.where((r) {
                                      var firstPattern = r.getName(suffixes: false).toLowerCase().startsWith(search.toLowerCase());
                                      var secondPattern = r.lastName.toLowerCase().startsWith(search.toLowerCase());
                                      return firstPattern || secondPattern;
                                    }).toList();

                                    var length = min(50, matches.length);
                                    return matches.sublist(0, length);
                                  },
                                  itemBuilder: (context, rating) {
                                    return Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(_formatMapping(unmatched, rating)),
                                    );
                                  },
                                  onSuggestionSelected: (rating) {
                                    _log.d("Selected $rating");
                                    setState(() {
                                      enabled = false;
                                      selectedMappings[unmatched] = rating;
                                      remainingOptions.remove(rating);
                                      deletedMappings.remove(unmatched);
                                    });
                                    controller.text = _formatMapping(unmatched, rating);
                                  },
                                  textFieldConfiguration: TextFieldConfiguration(
                                    controller: controller,
                                    enabled: enabled,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.cancel),
                              onPressed: () {
                                setState(() {
                                  enabled = true;
                                  var rating = selectedMappings[unmatched];
                                  if(rating != null) {
                                    deletedMappings.add(unmatched);
                                    selectedMappings.remove(unmatched);
                                    remainingOptions.add(rating);
                                  }
                                });
                                controller.text = "";
                              },
                            )
                          ],
                        );
                      }
                    );
                  }).toList()
                )
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text("ADVANCE"),
          onPressed: () async {
            if(persistMappings) {
              await saveMappings();
            }
            Navigator.of(context).pop(selectedMappings.values.toList());
          },
        )
      ],
    );
  }

  Future<void> loadSavedMappings() async {
    var db = AnalystDatabase();
    int found = 0;
    int applied = 0;
    for(var unmatched in widget.registrations.unmatchedShooters) {
      var mapping = await db.getMatchRegistrationMappingByName(matchId: widget.registrations.matchId, shooterName: unmatched.name, shooterDivisionName: unmatched.division.name);
      if(mapping != null) {
        found += 1;
        var foundMapping = widget.possibleMappings.firstWhereOrNull((r) => r.allPossibleMemberNumbers.intersects(mapping.detectedMemberNumbers));
        var registration = widget.registrations.unmatchedShooters.firstWhereOrNull((r) => r.name == mapping.shooterName);
        if(foundMapping != null && registration != null) {
          selectedMappings[registration] = foundMapping;
          applied += 1;
        }
        else if(foundMapping != null) {
          _log.w("Found mapping for ${unmatched.name} but no registration");
        }
        else if(registration != null) {
          _log.w("Found registration for ${unmatched.name} but no mapping");
        }
      }
    }
    _log.i("Found $found mappings, applied $applied to ${widget.registrations.unmatchedShooters.length} unmatched shooters");
    setState(() {});
  }

  Future<void> saveMappings() async {
    var db = AnalystDatabase();
    var mappings = selectedMappings.entries.map((e) => MatchRegistrationMapping(
      matchId: widget.registrations.matchId,
      shooterName: e.key.name,
      shooterClassificationName: e.key.classification.name,
      shooterDivisionName: e.key.division.name,
      detectedMemberNumbers: e.value.allPossibleMemberNumbers.toList(),
    )).toList();

    await db.saveMatchRegistrationMappings(widget.registrations.matchId, mappings);
    await db.deleteMatchRegistrationMappingsByNames(matchId: widget.registrations.matchId, shooterNames: deletedMappings.map((e) => e.name).toList());

    _log.i("Saved ${mappings.length} mappings and deleted ${deletedMappings.length} mappings");
  }

  String _formatMapping(Registration registration, ShooterRating mapping) {
    return "${mapping.getName(suffixes: false)} ${mapping.memberNumber} (${mapping.division?.displayName ?? "NO DIVISION"} ${mapping.lastClassification?.displayName})";
  }
}
