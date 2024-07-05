/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';

class RaterGroupsDialog extends StatefulWidget {
  const RaterGroupsDialog({Key? key, required this.selectedGroups, this.customGroups = const [], this.groupProvider}) : super(key: key);

  final RatingGroupsProvider? groupProvider;
  final List<DbRatingGroup> selectedGroups;
  final List<DbRatingGroup> customGroups;

  List<DbRatingGroup> get allGroups {
    List<DbRatingGroup> all = [];
    if(groupProvider != null) {
      all.addAll(groupProvider!.builtinRatingGroups);
    }
    all.addAll(customGroups);
    return all;
  }

  @override
  State<RaterGroupsDialog> createState() => _RaterGroupsDialogState();
}

class _RaterGroupsDialogState extends State<RaterGroupsDialog> {

  Map<DbRatingGroup, bool> checked = {};

  RatingGroupsProvider? get provider => widget.groupProvider;

  @override
  void initState() {
    super.initState();

    for(var g in widget.selectedGroups) {
      checked[g] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Select rater groups"),
      content: SingleChildScrollView(
        child: Column(
          children: [
            Text("Ratings will be calculated for each division or combination of divisions\n"
                "checked below."),
            ...buildRaterGroupRows(),
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                TextButton(
                  child: Text("NONE"),
                  onPressed: () {
                    setState(() {
                      checked.clear();
                    });
                  },
                ),
                if(provider?.defaultRatingGroups.isNotEmpty ?? false) TextButton(
                  child: Text("DEFAULT"),
                  onPressed: () {
                    checked.clear();
                    for(var g in provider!.defaultRatingGroups) {
                      checked[g] = true;
                    }

                    setState(() {

                    });
                  },
                ),
                if(provider?.divisionRatingGroups.isNotEmpty ?? false) TextButton(
                  child: Text("DIVISIONS"),
                  onPressed: () {
                    checked.clear();
                    for(var g in provider!.divisionRatingGroups) {
                      checked[g] = true;
                    }

                    setState(() {

                    });
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  child: Text("CANCEL"),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text("OK"),
                  onPressed: () {
                    Navigator.of(context).pop(widget.allGroups.where((g) => checked[g] ?? false).toList());
                  },
                )
              ],
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> buildRaterGroupRows() {
    List<Widget> widgets = [];
    for(var g in widget.allGroups) {
      widgets.add(
        CheckboxListTile(
          value: checked[g] ?? false,
          onChanged: (value) {
            setState(() {
              checked[g] = value ?? false;
            });
          },
          title: Text(g.uiLabel),
        )
      );
    }

    return widgets;
  }
}
