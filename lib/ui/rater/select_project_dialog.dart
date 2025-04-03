/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';

class SelectProjectDialog extends StatefulWidget {
  const SelectProjectDialog({Key? key}) : super(key: key);

  @override
  State<SelectProjectDialog> createState() => _SelectProjectDialogState();

  static Future<DbRatingProject?> show(BuildContext context) {
    return showDialog<DbRatingProject>(context: context, builder: (context) => SelectProjectDialog());
  }
}

class _SelectProjectDialogState extends State<SelectProjectDialog> {
  List<DbRatingProject> projects = [];
  @override
  void initState() {
    super.initState();
    _getProjects();
  }

  var _sort = _ProjectSort.loaded;

  Future<void> _getProjects() async {
    var p = await AnalystDatabase().getAllRatingProjects();
    p.sort((a, b) {
      return switch(_sort) {
        _ProjectSort.name => a.name.compareTo(b.name),
        _ProjectSort.id => a.id.compareTo(b.id),
        _ProjectSort.created => a.created.compareTo(b.created),
        _ProjectSort.updated => a.updated.compareTo(b.updated),
        _ProjectSort.loaded => a.loaded.compareTo(b.loaded),
      };
    });
    setState(() {
      projects = p;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select Project"),
      content: SizedBox(
        width: 600,
        child: ListView.builder(
          shrinkWrap: true,
          itemBuilder: (context, i) {
            var project = projects[i];
            return ListTile(
              title: Text(project.name),
              subtitle: Text("Database ID: ${project.id}"),
              trailing: IconButton(
                icon: Icon(Icons.delete),
                onPressed: () async {
                  var delete = await showDialog<bool>(context: context, builder: (context) {
                    return ConfirmDialog(content: Text("Delete ${project.name}?"));
                  });

                  if(delete ?? false) {
                    AnalystDatabase().deleteRatingProject(project);
                    setState(() {
                      projects.remove(project);
                    });
                  }
                },
              ),
              onTap: () {
                Navigator.of(context).pop(project);
              },
            );
          },
          itemCount: projects.length,
        ),
      ),
    );
  }
}

enum _ProjectSort {
  name,
  id,
  created,
  updated,
  loaded;
}
