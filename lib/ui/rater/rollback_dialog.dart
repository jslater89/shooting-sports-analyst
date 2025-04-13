/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_pointer_chooser_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

class RollbackDialog extends StatefulWidget {
  const RollbackDialog({super.key, required this.project});

  final DbRatingProject project;

  @override
  State<RollbackDialog> createState() => _RollbackDialogState();

  static Future<DateTime?> show(BuildContext context, DbRatingProject project) async {
    return showDialog<DateTime>(
      context: context,
      builder: (context) => RollbackDialog(project: project),
    );
  }
}

class _RollbackDialogState extends State<RollbackDialog> {
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select rollback date"),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Select match or date to roll back to. All matches after the selected date will be removed."),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                var date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now());
                if(date != null) {
                  setState(() {
                    _selectedDate = date;
                  });
                }
              },
              child: Text(_selectedDate != null ? programmerYmdFormat.format(_selectedDate!) : "Select date"),
            ),
            SizedBox(height: 10),
            Text("- or -", style: Theme.of(context).textTheme.labelMedium),
            SizedBox(height: 10),
            ElevatedButton(
              child: Text("Select match"),
              onPressed: () async {
                var match = await MatchPointerChooserDialog.showSingle(context: context, matches: widget.project.matchPointers);
                if(match != null) {
                  setState(() {
                    _selectedDate = match.date;
                  });
                }
              }
            )
          ],
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
          child: Text("ROLL BACK"),
          onPressed: () {
            Navigator.of(context).pop(_selectedDate);
          },
        )
      ],
    );
  }
}
