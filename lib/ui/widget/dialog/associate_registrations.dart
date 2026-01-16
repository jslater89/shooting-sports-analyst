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
import 'package:shooting_sports_analyst/data/database/extensions/future_match.dart';
import 'package:shooting_sports_analyst/data/database/extensions/registrations.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration_mapping.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("AssocRegistrationsDialog");

class AssociateRegistrationsDialog extends StatefulWidget {
  const AssociateRegistrationsDialog({Key? key, required this.sport, required this.futureMatch, required this.unmatchedRegistrations, required this.possibleMappings}) : super(key: key);

  final Sport sport;
  final FutureMatch futureMatch;
  final List<MatchRegistration> unmatchedRegistrations;
  final List<ShooterRating> possibleMappings;

  @override
  State<AssociateRegistrationsDialog> createState() => _AssociateRegistrationsDialogState();
}

class _AssociateRegistrationsDialogState extends State<AssociateRegistrationsDialog> {
  late Map<MatchRegistration, ShooterRating> selectedMappings;
  late List<ShooterRating> remainingOptions;
  bool persistMappings = true;

  @override
  void initState() {
    super.initState();
    widget.unmatchedRegistrations.sort((a, b) {
      var aClassification = widget.sport.classifications.lookupByName(a.shooterClassificationName);
      var bClassification = widget.sport.classifications.lookupByName(b.shooterClassificationName);
      return aClassification?.index.compareTo(bClassification?.index ?? 0) ?? 0;
    });

    selectedMappings = {};
    remainingOptions = []..addAll(widget.possibleMappings);
    loadSavedMappings();
  }

  List<MatchRegistration> deletedMappings = [];

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
                  children: widget.unmatchedRegistrations.map((unmatched) {
                    var enabled = true;
                    var currentMapping = selectedMappings[unmatched];
                    var controller = TextEditingController();
                    if(currentMapping != null) {
                      controller.text = _formatMapping(unmatched, currentMapping);
                      enabled = false;
                    }

                    return StatefulBuilder(
                      builder: (context, setState) {
                        var classification = widget.sport.classifications.lookupByName(unmatched.shooterClassificationName);
                        var division = widget.sport.divisions.lookupByName(unmatched.shooterDivisionName);
                        return Row(
                          children: [
                            Expanded(child: Text("${unmatched.shooterName} (${division?.displayName ?? "(unknown division)"} ${classification?.displayName ?? "(no classification)"})")),
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
    for(var unmatched in widget.unmatchedRegistrations) {
      var mapping = await db.getMatchRegistrationMappingByName(matchId: widget.futureMatch.matchId, shooterName: unmatched.shooterName ?? "", shooterDivisionName: unmatched.shooterDivisionName ?? "");
      if(mapping != null) {
        found += 1;
        var foundMapping = widget.possibleMappings.firstWhereOrNull((r) => r.allPossibleMemberNumbers.intersects(mapping.detectedMemberNumbers));
        var registration = widget.unmatchedRegistrations.firstWhereOrNull((r) => r.shooterName == mapping.shooterName && r.shooterDivisionName == mapping.shooterDivisionName && r.shooterClassificationName == mapping.shooterClassificationName);
        if(foundMapping != null && registration != null) {
          selectedMappings[registration] = foundMapping;
          applied += 1;
        }
        else if(foundMapping != null) {
          _log.w("Found mapping for ${unmatched.shooterName} but no registration");
        }
        else if(registration != null) {
          _log.w("Found registration for ${unmatched.shooterName} but no mapping");
        }
      }
    }
    _log.i("Found $found mappings, applied $applied to ${widget.unmatchedRegistrations.length} unmatched registrations");
    setState(() {});
  }

  Future<void> saveMappings() async {
    var db = AnalystDatabase();
    var mappings = selectedMappings.entries.map((e) => MatchRegistrationMapping(
      matchId: widget.futureMatch.matchId,
      shooterName: e.key.shooterName ?? "",
      shooterClassificationName: e.key.shooterClassificationName ?? "",
      shooterDivisionName: e.key.shooterDivisionName ?? "",
      detectedMemberNumbers: e.value.allPossibleMemberNumbers.toList(),
      squad: e.key.squad,
    )).toList();

    await db.saveMatchRegistrationMappings(widget.futureMatch.matchId, mappings);
    await db.deleteMatchRegistrationMappingsByNames(matchId: widget.futureMatch.matchId, shooterNames: deletedMappings.map((e) => e.shooterName ?? "").toList());

    _log.i("Saved ${mappings.length} mappings and deleted ${deletedMappings.length} mappings");

    var updated = await widget.futureMatch.updateRegistrationsFromMappings();
    _log.i("Updated $updated registrations from ${mappings.length} mappings");
  }

  String _formatMapping(MatchRegistration registration, ShooterRating mapping) {
    return "${mapping.getName(suffixes: false)} ${mapping.memberNumber} (${mapping.division?.displayName ?? "NO DIVISION"} ${mapping.lastClassification?.displayName})";
  }
}
