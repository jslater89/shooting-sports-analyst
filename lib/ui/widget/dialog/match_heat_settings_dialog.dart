/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';

enum MatchHeatValue {
  topTenPercentAverageRating,
  medianRating,
  averageClassification,
  matchSize;

  String get label => switch(this) {
    topTenPercentAverageRating => "Top 10% average rating",
    medianRating => "Median rating",
    averageClassification => "Average classification",
    matchSize => "Match size",
  };

  String get axisLabel => switch(this) {
    topTenPercentAverageRating => "Average of Top Ratings",
    medianRating => "Median Rating",
    averageClassification => "Average Classification",
    matchSize => "Competitor Count",
  };

  String get tooltip => switch(this) {
    topTenPercentAverageRating => "The average rating of the top 10% of competitors at the match.",
    medianRating => "The median rating of the competitors at the match.",
    averageClassification => "The average classification of the competitors at the match.",
    matchSize => "The number of competitors at the match.",
  };
}

class MatchHeatSettings {
  MatchHeatValue xAxis;
  MatchHeatValue yAxis;
  MatchHeatValue dotSize;
  MatchHeatValue dotColor;

  MatchHeatSettings({
    this.xAxis = MatchHeatValue.matchSize,
    this.yAxis = MatchHeatValue.topTenPercentAverageRating,
    this.dotSize = MatchHeatValue.medianRating,
    this.dotColor = MatchHeatValue.averageClassification,
  });

  MatchHeatSettings copy() => MatchHeatSettings(
    xAxis: xAxis,
    yAxis: yAxis,
    dotSize: dotSize,
    dotColor: dotColor,
  );
}

class MatchHeatSettingsDialog extends StatefulWidget {
  const MatchHeatSettingsDialog({super.key, required this.settings});

  final MatchHeatSettings settings;

  static Future<MatchHeatSettings?> show({required BuildContext context, required MatchHeatSettings settings}) {
    return showDialog<MatchHeatSettings>(context: context, builder: (context) => MatchHeatSettingsDialog(settings: settings));
  }

  @override
  State<MatchHeatSettingsDialog> createState() => _MatchHeatSettingsDialogState();
}

class _MatchHeatSettingsDialogState extends State<MatchHeatSettingsDialog> {
  late MatchHeatSettings workingSettings;

  @override
  void initState() {
    super.initState();
    workingSettings = widget.settings.copy();
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text("Display settings"),
      content: SizedBox(
        width: 300 * uiScaleFactor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16 * uiScaleFactor,
          children: [
            DropdownMenu<MatchHeatValue>(
              width: 275 * uiScaleFactor,
              label: Text("X Axis"),
              initialSelection: workingSettings.xAxis,
              dropdownMenuEntries: MatchHeatValue.values.map((e) => DropdownMenuEntry(value: e, label: e.label)).toList(),
              onSelected: (value) {
                if(value != null) {
                  setState(() {
                    workingSettings.xAxis = value;
                  });
                }
              },
            ),
            DropdownMenu<MatchHeatValue>(
              width: 275 * uiScaleFactor,
              label: Text("Y Axis"),
              initialSelection: workingSettings.yAxis,
              dropdownMenuEntries: MatchHeatValue.values.map((e) => DropdownMenuEntry(value: e, label: e.label)).toList(),
              onSelected: (value) {
                if(value != null) {
                  setState(() {
                    workingSettings.yAxis = value;
                  });
                }
              },
            ),
            DropdownMenu<MatchHeatValue>(
              width: 275 * uiScaleFactor,
              label: Text("Dot Size"),
              initialSelection: workingSettings.dotSize,
              dropdownMenuEntries: MatchHeatValue.values.map((e) => DropdownMenuEntry(value: e, label: e.label)).toList(),
              onSelected: (value) {
                if(value != null) {
                  setState(() {
                    workingSettings.dotSize = value;
                  });
                }
              },
            ),
            DropdownMenu<MatchHeatValue>(
              width: 275 * uiScaleFactor,
              label: Text("Dot Color"),
              initialSelection: workingSettings.dotColor,
              dropdownMenuEntries: MatchHeatValue.values.map((e) => DropdownMenuEntry(value: e, label: e.label)).toList(),
              onSelected: (value) {
                if(value != null) {
                  setState(() {
                    workingSettings.dotColor = value;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(MatchHeatSettings()), child: Text("DEFAULTS")),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("CANCEL")),
        TextButton(onPressed: () => Navigator.of(context).pop(workingSettings), child: Text("SAVE")),
      ],
    );
  }
}
