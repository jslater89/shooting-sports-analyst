/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/prematch/dialog/new_match_prep.dart';
import 'package:shooting_sports_analyst/ui/prematch/match_prep_list.dart';

class MatchPrepListPage extends StatefulWidget {
  const MatchPrepListPage({super.key, this.singleProject});

  /// If provided, only show match prep rows for this project.
  final DbRatingProject? singleProject;

  @override
  State<MatchPrepListPage> createState() => _MatchPrepListPageState();
}

class _MatchPrepListPageState extends State<MatchPrepListPage> {
  late final MatchPrepListModel model;

  void initState() {
    super.initState();
    model = MatchPrepListModel(singleProject: widget.singleProject);
    model.load();
  }

  @override
  Widget build(BuildContext context) {
    return EmptyScaffold(
      title: "Match Prep",
      actions: [
        IconButton(
          icon: Icon(Icons.add),
          onPressed: () async {
            var prep = await NewMatchPrepDialog.show(context, saveOnPop: true, singleProject: widget.singleProject);
            if(prep != null) {
              model.load();
            }
          }
        ),
      ],
      child: ChangeNotifierProvider.value(
        value: model,
        child: MatchPrepList(),
      ),
    );
  }
}
