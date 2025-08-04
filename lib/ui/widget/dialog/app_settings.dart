/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:logger/logger.dart';
import 'package:shooting_sports_analyst/data/help/app_settings_help.dart';
import 'package:shooting_sports_analyst/ui/rater/select_project_dialog.dart';
import 'package:shooting_sports_analyst/ui/source/credentials_manager.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';

class AppSettingsDialog extends StatefulWidget {
  const AppSettingsDialog({super.key});

  @override
  State<AppSettingsDialog> createState() => _AppSettingsDialogState();

  static Future<SerializedConfig?> show(BuildContext context) {
    return showDialog<SerializedConfig>(
      context: context,
      builder: (context) => AppSettingsDialog(),
    );
  }
}

class _AppSettingsDialogState extends State<AppSettingsDialog> {
  late SerializedConfig config;
  DbRatingProject? project;

  TextEditingController _logLevelController = TextEditingController();
  TextEditingController _projectController = TextEditingController();
  @override
  void initState() {
    super.initState();

    config = ConfigLoader().config.copy();
    _loadProject();
    _logLevelController.text = config.logLevel.name;
    _projectController.text = project?.name ?? config.ratingsContextProjectId?.toString() ?? "(none)";
  }

  Future<void> _loadProject() async {
    project = await AnalystDatabase().getRatingProjectById(config.ratingsContextProjectId ?? -1);
    _projectController.text = project?.name ?? config.ratingsContextProjectId?.toString() ?? "(none)";
  }

  void setProject(DbRatingProject? project) {
    config.ratingsContextProjectId = project?.id;
    _projectController.text = project?.name ?? "(none)";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("App settings"),
          HelpButton(helpTopicId: appSettingsHelpId),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownMenu<Level>(
              dropdownMenuEntries: [
                Level.trace,
                Level.debug,
                Level.info,
                Level.warning,
                Level.error,
              ].map((e) => DropdownMenuEntry(value: e, label: e.name)).toList(),
              onSelected: (value) {
                if(value != null) {
                  config.logLevel = value;
                  _logLevelController.text = value.name;
                }
              },
              controller: _logLevelController,
              label: const Text("Log level"),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text("Play deduplication alert"),
              subtitle: const Text("Play a sound when loading a project and deduplication is required"),
              value: config.playDeduplicationAlert,
              onChanged: (value) {
                setState(() {
                  config.playDeduplicationAlert = value ?? false;
                });
              },
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text("Play ratings calculation complete alert"),
              subtitle: const Text("Play a sound when ratings calculation is complete"),
              value: config.playRatingsCalculationCompleteAlert,
              onChanged: (value) {
                setState(() {
                  config.playRatingsCalculationCompleteAlert = value ?? false;
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _projectController,
                    decoration: const InputDecoration(
                      labelText: "Ratings context",
                    ),
                    readOnly: true,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    project = await SelectProjectDialog.show(context);
                    setProject(project);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    setProject(null);
                  },
                ),
              ],
            )
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Manage credentials for match sources",
              child: TextButton(
                child: const Text("EDIT CREDENTIALS"),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => SourceCredentialsManager()));
                },
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  child: const Text("CANCEL"),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text("SAVE"),
                  onPressed: () {
                    Navigator.of(context).pop(config);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
