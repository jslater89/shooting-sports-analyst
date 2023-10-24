/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';

class ScoreListSettingsDialog extends StatefulWidget {
  const ScoreListSettingsDialog({Key? key, required this.initialSettings, required this.showRatingsSettings}) : super(key: key);

  final ScoreDisplaySettings initialSettings;
  final bool showRatingsSettings;

  @override
  State<ScoreListSettingsDialog> createState() => _ScoreListSettingsDialogState();
}

class _ScoreListSettingsDialogState extends State<ScoreListSettingsDialog> {
  late ScoreDisplaySettings settings;

  @override
  void initState() {
    super.initState();
    settings = ScoreDisplaySettings.copy(widget.initialSettings);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Display Settings"),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: Text("Available points count penalties"),
              value: settings.availablePointsCountPenalties,
              onChanged: (v) {
                if(v != null) {
                  setState(() {
                    settings.availablePointsCountPenalties = v;
                  });
                }
              },
            ),
            CheckboxListTile(
              title: Text("Improved fixed time available points"),
              subtitle: Text("Fixed time stages use highest achieved points as 100%"),
              value: settings.fixedTimeAvailablePointsFromDivisionMax,
              onChanged: (v) {
                if(v != null) {
                  setState(() {
                    settings.fixedTimeAvailablePointsFromDivisionMax = v;
                  });
                }
              },
            ),
            if(widget.showRatingsSettings) ListTile(
              title: Text("Rating display mode"),
              trailing: DropdownButton<RatingDisplayMode>(
                value: settings.ratingMode,
                items: RatingDisplayMode.values.map((v) => DropdownMenuItem<RatingDisplayMode>(
                  child: Text(v.uiLabel),
                  value: v,
                )).toList(),
                onChanged: (v) {
                  if(v != null) {
                    setState(() {
                      settings.ratingMode = v;
                    });
                  }
                },
              ),
            ),
            ListTile(
              title: Text("Match prediction mode"),
              trailing: DropdownButton<MatchPredictionMode>(
                value: settings.predictionMode,
                items: MatchPredictionMode.dropdownValues(widget.showRatingsSettings).map((v) => DropdownMenuItem<MatchPredictionMode>(
                  child: Text(v.uiLabel),
                  value: v,
                )).toList(),
                onChanged: (v) {
                  if(v != null) {
                    setState(() {
                      settings.predictionMode = v;
                    });
                  }
                },
              ),
            ),
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
          child: Text("OK"),
          onPressed: () {
            Navigator.of(context).pop(settings);
          },
        )
      ],
    );
  }
}
