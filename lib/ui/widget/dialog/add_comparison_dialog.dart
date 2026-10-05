/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("AddComparisonDialog");

class AddComparisonDialog extends StatefulWidget {
  AddComparisonDialog(this.scores, {Key? key}) : super(key: key);

  final List<RelativeMatchScore> scores;

  @override
  State<AddComparisonDialog> createState() => _AddComparisonDialogState();
}

class _AddComparisonDialogState extends State<AddComparisonDialog> {
  RelativeMatchScore? selected;
  late TextEditingController selectionController;

  @override
  void initState() {
    super.initState();
    _log.i("Initializing AddComparisonDialog with ${widget.scores.length} scores");
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select shooter"),
      content: TypeAheadField<RelativeMatchScore>(
        builder: (context, controller, focusNode) {
          selectionController = controller;
          return TextField(
            controller: controller,
            focusNode: focusNode,
          );
        },
        itemBuilder: (context, score) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("${score.shooter.name}"),
          );
        },
        suggestionsCallback: (query) async {
          query = query.toLowerCase();
          return widget.scores.where((element) =>
            element.shooter.name.toLowerCase().startsWith(query) ||
            element.shooter.lastName.toLowerCase().startsWith(query)
          ).toList();
        },
        onSelected: (suggestion) {
          selectionController.text = suggestion.shooter.name;
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
