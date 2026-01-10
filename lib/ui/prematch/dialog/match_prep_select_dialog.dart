/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/ui/prematch/match_prep_list.dart';

/// A dialog to select a match prep. Pops a MatchPrep object on selection.
class MatchPrepSelectDialog extends StatefulWidget {
  const MatchPrepSelectDialog({super.key});

  @override
  State<MatchPrepSelectDialog> createState() => _MatchPrepSelectDialogState();

  static Future<MatchPrep?> show(BuildContext context) async {
    return showDialog<MatchPrep>(context: context, builder: (context) => MatchPrepSelectDialog());
  }
}

class _MatchPrepSelectDialogState extends State<MatchPrepSelectDialog> {
  final model = MatchPrepListModel();

  @override
  void initState() {
    super.initState();
    model.load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select a match prep"),
      content: ChangeNotifierProvider.value(
        value: model,
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: MatchPrepList(
            onMatchPrepSelected: (matchPrep) {
              Navigator.of(context).pop(matchPrep);
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("CANCEL"),
        ),
      ],
    );
  }
}