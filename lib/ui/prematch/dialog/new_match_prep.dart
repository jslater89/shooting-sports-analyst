/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/ui/rater/select_project_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/future_match_database_chooser_dialog.dart';

/// A dialog to create a new match prep. Checks to see if a match prep already exists for the given project and match.
class NewMatchPrepDialog extends StatefulWidget {
  const NewMatchPrepDialog({super.key, this.saveOnPop = false, this.singleProject});

  final bool saveOnPop;
  final DbRatingProject? singleProject;

  @override
  State<NewMatchPrepDialog> createState() => _NewMatchPrepDialogState();

  static Future<MatchPrep?> show(BuildContext context, {bool saveOnPop = false, DbRatingProject? singleProject}) async {
    return showDialog<MatchPrep>(context: context, builder: (context) => NewMatchPrepDialog(saveOnPop: saveOnPop, singleProject: singleProject));
  }
}

class _NewMatchPrepDialogState extends State<NewMatchPrepDialog> {
  DbRatingProject? project;
  FutureMatch? match;

  bool alreadyExists = false;

  final _projectController = TextEditingController();
  final _matchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialProject();
  }

  Future<void> _loadInitialProject() async {
    DbRatingProject? project;
    if(widget.singleProject != null) {
      project = widget.singleProject;
    }
    else {
      project = await AnalystDatabase().getRatingProjectById(ChangeNotifierConfigLoader().config.ratingsContextProjectId ?? -1);
    }
    if(project == null) {
      return;
    }

    setState(() {
      this.project = project;
      _projectController.text = project?.name ?? "";
    });
  }

  Future<void> _selectProject() async {
    var project = await SelectProjectDialog.show(context);
    if(project == null) {
      return;
    }
    setState(() {
      this.project = project;
      _projectController.text = project.name;
    });
    _checkAlreadyExists();
  }

  Future<void> _selectMatch() async {
    var match = await FutureMatchDatabaseChooserDialog.showSingle(context: context, sport: project?.sport);
    if(match == null) {
      return;
    }
    setState(() {
      this.match = match;
      _matchController.text = match.eventName;
    });
    _checkAlreadyExists();
  }

  Future<void> _checkAlreadyExists() async {
    if(match != null && project != null) {
      var prep = await AnalystDatabase().getMatchPrepForProjectAndMatch(project!, match!);
      if(prep != null) {
        setState(() {
          alreadyExists = true;
        });
        return;
      }
    }

    setState(() {
      alreadyExists = false;
    });
  }

  Future<void> _createMatchPrep() async {
    if(match != null && project != null) {
      var prep = MatchPrep.from(futureMatch: match!, project: project!);

      if(widget.saveOnPop) {
        prep = await AnalystDatabase().saveMatchPrep(prep);
      }

      Navigator.of(context).pop(prep);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text("New match prep"),
      content: SizedBox(width: 500 * uiScaleFactor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _projectController,
              decoration: InputDecoration(
                labelText: "Project",
                suffixIcon: widget.singleProject == null ? IconButton(icon: Icon(Icons.edit), onPressed: () => _selectProject()) : null,
              ),
              readOnly: true,
            ),
            TextFormField(
              controller: _matchController,
              decoration: InputDecoration(
                labelText: "Match",
                suffixIcon: IconButton(icon: Icon(Icons.edit), onPressed: () => _selectMatch()),
              ),
              enabled: project != null,
              readOnly: true,
            ),
            if(alreadyExists)
              Text("A match prep already exists for this project and match.", style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(
          child: Text("CREATE"),
          onPressed: alreadyExists ? null : () => _createMatchPrep()
        ),
      ],
    );
  }
}