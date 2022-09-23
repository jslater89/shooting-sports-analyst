import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/ui/rater/prediction/registration_parser.dart';

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

  @override
  void initState() {
    super.initState();
    widget.registrations.unmatchedShooters.sort((a, b) => a.classification.index.compareTo(b.classification.index));

    selectedMappings = {};
    remainingOptions = []..addAll(widget.possibleMappings);
  }

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
              Expanded(
                child: ListView(
                  children: widget.registrations.unmatchedShooters.map((unmatched) {
                    var controller = TextEditingController();
                    var enabled = true;

                    return StatefulBuilder(
                      builder: (context, setState) {
                        return Row(
                          children: [
                            Expanded(child: Text("${unmatched.name} (${unmatched.division.displayString()} ${unmatched.classification.displayString()})")),
                            Expanded(
                              child: SizedBox(
                                width: 250,
                                child: TypeAheadField<ShooterRating>(
                                  suggestionsCallback: (search) {
                                    var matches = remainingOptions.where((r) {
                                      var firstPattern = r.shooter.getName(suffixes: false).toLowerCase().startsWith(search.toLowerCase());
                                      var secondPattern = r.shooter.lastName.toLowerCase().startsWith(search.toLowerCase());
                                      return firstPattern || secondPattern;
                                    }).toList();

                                    var length = min(50, matches.length);
                                    return matches.sublist(0, length);
                                  },
                                  itemBuilder: (context, rating) {
                                    return Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text("${rating.shooter.getName(suffixes: false)} (${rating.shooter.division.displayString()} ${rating.shooter.classification.displayString()})"),
                                    );
                                  },
                                  onSuggestionSelected: (rating) {
                                    setState(() {
                                      enabled = false;
                                      selectedMappings[unmatched] = rating;
                                      remainingOptions.remove(rating);
                                    });
                                    controller.text = "${rating.shooter.getName(suffixes: false)} (${rating.shooter.division.displayString()} ${rating.shooter.classification.displayString()})";
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
          onPressed: () {
            Navigator.of(context).pop(selectedMappings.values.toList());
          },
        )
      ],
    );
  }
}
