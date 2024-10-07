/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';

part 'global_card_settings_dialog.g.dart';

@JsonSerializable()
class GlobalScorecardSettingsModel {
  MatchPredictionMode predictionMode;

  GlobalScorecardSettingsModel({
    this.predictionMode = MatchPredictionMode.none,
  });

  factory GlobalScorecardSettingsModel.fromJson(Map<String, dynamic> json) => _$GlobalScorecardSettingsModelFromJson(json);
  Map<String, dynamic> toJson() => _$GlobalScorecardSettingsModelToJson(this);
}

/// GlobalScorecardSettingsDialog is a modal host for [GlobalScorecardSettingsWidget].
class GlobalScorecardSettingsDialog extends StatelessWidget {
  const GlobalScorecardSettingsDialog({super.key, required this.settings});

  final GlobalScorecardSettingsModel settings;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Global Scorecard Settings"),
      content: GlobalScorecardSettingsWidget(settings: settings),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("CANCEL")),
        TextButton(onPressed: () => Navigator.of(context).pop(settings), child: const Text("SAVE")),
      ],
    );
  }

  static Future<GlobalScorecardSettingsModel?> show(BuildContext context, {required GlobalScorecardSettingsModel settings}) {
    return showDialog<GlobalScorecardSettingsModel>(
      context: context,
      builder: (context) => GlobalScorecardSettingsDialog(settings: settings),
      barrierDismissible: false,
    );
  }
}

/// GlobalScorecardSettingsWidget edits the provided global scorecard settings.
/// Edits happen in place, so use a copy if confirm/discard is needed.
class GlobalScorecardSettingsWidget extends StatefulWidget {
  const GlobalScorecardSettingsWidget({super.key, required this.settings});

  final GlobalScorecardSettingsModel settings;

  @override
  State<GlobalScorecardSettingsWidget> createState() => _GlobalScorecardSettingsWidgetState();
}

class _GlobalScorecardSettingsWidgetState extends State<GlobalScorecardSettingsWidget> {
  late GlobalScorecardSettingsModel settings;

  @override
  void initState() {
    super.initState();
    settings = widget.settings;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<MatchPredictionMode>(
          value: settings.predictionMode,
          decoration: const InputDecoration(labelText: "Prediction mode"),
          items: MatchPredictionMode.dropdownValues(false).map((mode) => DropdownMenuItem(
            value: mode,
            child: Text(mode.uiLabel),
          )).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                settings.predictionMode = value;
              });
            }
          },
        ),
        // Add more global settings here as needed
      ],
    );
  }
}
