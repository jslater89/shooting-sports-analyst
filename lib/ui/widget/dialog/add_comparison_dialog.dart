/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:uspsa_result_viewer/data/model.dart';

class AddComparisonDialog extends StatefulWidget {
  AddComparisonDialog(this.scores, {Key? key}) : super(key: key);

  final List<RelativeMatchScore> scores;

  @override
  State<AddComparisonDialog> createState() => _AddComparisonDialogState();
}

class _AddComparisonDialogState extends State<AddComparisonDialog> {
  TextEditingController selectionController = TextEditingController();
  RelativeMatchScore? selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select Shooter"),
      content: TypeAheadField<RelativeMatchScore>(
        textFieldConfiguration: TextFieldConfiguration(
          controller: selectionController,
        ),
        itemBuilder: (context, score) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("${score.shooter.getName(suffixes: false)}"),
          );
        },
        suggestionsCallback: (query) {
          query = query.toLowerCase();
          return widget.scores.where((element) =>
            element.shooter.getName(suffixes: false).toLowerCase().startsWith(query) ||
            element.shooter.lastName.toLowerCase().startsWith(query)
          );
        },
        onSuggestionSelected: (suggestion) {
          selectionController.text = suggestion.shooter.getName(suffixes: false);
          selected = suggestion;
        },
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text("ADD"),
          onPressed: () {
            Navigator.of(context).pop(selected);
          },
        )
      ],
    );
  }
}
