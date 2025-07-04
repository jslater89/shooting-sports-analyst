/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';

class ProjectMigrateRequest {
  final OldRatingProject project;
  final String? nameOverride;

  ProjectMigrateRequest(this.project, this.nameOverride);
}

class MigrateOldProjectDialog extends StatefulWidget {
  const MigrateOldProjectDialog({super.key});

  @override
  State<MigrateOldProjectDialog> createState() => _MigrateOldProjectDialogState();
}

class _MigrateOldProjectDialogState extends State<MigrateOldProjectDialog> {
  List<OldRatingProject> projects = [];

  @override
  void initState() {
    super.initState();
    _getProjects();
  }

  Future<void> _getProjects() async {
    await RatingProjectManager().ready;
    var mgr = RatingProjectManager();

    List<OldRatingProject> p = [];
    for(var key in mgr.savedProjects()) {
      var project = mgr.loadProject(key);
      if(project != null) {
        p.add(project);
      }
    }

    setState(() {
      projects = p;
    });
  }

  var _nameOverride = TextEditingController();
  OldRatingProject? _selectedProject;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select project to migrate"),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text("Selected project: ${_selectedProject?.name ?? "(none)"}"),
            TextField(
              controller: _nameOverride,
              decoration: InputDecoration(
                labelText: "Project name override",
                icon: Tooltip(
                  message: "Optionally, provide a new name for this project.",
                  child: Icon(Icons.help_outline)
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemBuilder: (context, i) {
                  return ListTile(
                    title: Text(projects[i].name),
                    subtitle: Text("${projects[i].matchUrls.length} matches"),
                    onTap: () {
                      setState(() {
                        _selectedProject = projects[i];
                      });
                    },
                  );
                },
                itemCount: projects.length,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context, null);
          },
          child: Text("CANCEL"),
        ),
        TextButton(
          onPressed: _selectedProject == null ? null : () {
            var nameOverride = _nameOverride.text.trim().isEmpty ? null : _nameOverride.text;
            Navigator.pop(context, ProjectMigrateRequest(_selectedProject!, nameOverride));
          },
          child: Text("IMPORT"),
        ),
      ],
    );
  }
}
