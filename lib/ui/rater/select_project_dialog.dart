/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';
class SelectProjectDialog extends StatefulWidget {
  const SelectProjectDialog({Key? key, this.showSort = true}) : super(key: key);

  final bool showSort;

  @override
  State<SelectProjectDialog> createState() => _SelectProjectDialogState();

  static Future<DbRatingProject?> show(BuildContext context, {bool showSort = true}) {
    return showDialog<DbRatingProject>(context: context, builder: (context) => SelectProjectDialog(showSort: showSort));
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
  var _sortController = TextEditingController(text: _ProjectSort.loaded.uiLabel);

  Future<void> _getProjects() async {
    var p = await AnalystDatabase().getAllRatingProjects();
    p.sort(_sort.compare);
    setState(() {
      projects = p;
    });
  }

  void _updateSort(_ProjectSort sort) {
    setState(() {
      _sort = sort;
      _sortController.text = sort.uiLabel;
    });
    projects.sort(_sort.compare);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select Project"),
      content: SizedBox(
        width: 600,
        child: Column(
          children: [
            if(widget.showSort)
              DropdownMenu<_ProjectSort>(
                controller: _sortController,
                onSelected: (value) {
                  if(value != null) {
                    _updateSort(value);
                  }
                },
                dropdownMenuEntries: _ProjectSort.values.map((e) => DropdownMenuEntry(value: e, label: e.uiLabel)).toList(),
              ),
            if(widget.showSort) Divider(),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemBuilder: (context, i) {
                  var sortText = _sortText(projects[i]);
                  var project = projects[i];
                  return ListTile(
                    title: Text(project.name),
                    subtitle: sortText != null ? Text(sortText) : null,
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
          ],
        ),
      ),
    );
  }

  String? _sortText(DbRatingProject project) {
    switch(_sort) {
      case _ProjectSort.name:
        return "Last viewed: ${programmerYmdHmFormat.format(project.loaded)}";
      case _ProjectSort.id:
        return "Database ID: ${project.id}";
      case _ProjectSort.created:
        return "Created: ${programmerYmdHmFormat.format(project.created)}";
      case _ProjectSort.updated:
        return "Last updated: ${programmerYmdHmFormat.format(project.updated)}";
      case _ProjectSort.loaded:
        return "Last viewed: ${programmerYmdHmFormat.format(project.loaded)}";
    }
  }
}

enum _ProjectSort {
  name,
  id,
  created,
  updated,
  loaded;

  String get uiLabel => switch(this) {
    name => "Name",
    id => "Database ID",
    created => "Created",
    updated => "Last updated",
    loaded => "Last viewed",
  };

  int compare(DbRatingProject a, DbRatingProject b) {
    return switch(this) {
      name => a.name.compareTo(b.name),
      id => a.id.compareTo(b.id),
      created => b.created.compareTo(a.created),
      updated => b.updated.compareTo(a.updated),
      loaded => b.loaded.compareTo(a.loaded),
    };
  }
}
