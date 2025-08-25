/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/match_prediction_mode.dart';

part 'global_card_settings_dialog.g.dart';

@JsonSerializable()
class GlobalScorecardSettingsModel with ChangeNotifier {
  MatchPredictionMode predictionMode;
  double minScorecardHeight;
  double minScorecardWidth;
  TableTextSize tableTextSize;
  bool hasHorizontalScrollbar;

  GlobalScorecardSettingsModel({
    this.predictionMode = MatchPredictionMode.none,
    this.minScorecardHeight = 400.0,
    this.minScorecardWidth = 900.0,
    this.tableTextSize = TableTextSize.normal,
    this.hasHorizontalScrollbar = false,
  });

  GlobalScorecardSettingsModel copy() => GlobalScorecardSettingsModel(
    predictionMode: predictionMode,
    minScorecardHeight: minScorecardHeight,
    minScorecardWidth: minScorecardWidth,
    tableTextSize: tableTextSize,
    hasHorizontalScrollbar: hasHorizontalScrollbar,
  );

  factory GlobalScorecardSettingsModel.fromJson(Map<String, dynamic> json) => _$GlobalScorecardSettingsModelFromJson(json);
  Map<String, dynamic> toJson() => _$GlobalScorecardSettingsModelToJson(this);

  static GlobalScorecardSettingsModel maybeFromJson(Map<String, dynamic>? json) {
    if(json == null) return GlobalScorecardSettingsModel();
    return GlobalScorecardSettingsModel.fromJson(json);
  }

  bool validate() {
    notifyListeners();
    return minScorecardWidth > 0 && minScorecardWidth <= 4096 && minScorecardHeight > 0 && minScorecardHeight <= 4096;
  }
}

/// GlobalScorecardSettingsDialog is a modal host for [GlobalScorecardSettingsWidget].
class GlobalScorecardSettingsDialog extends StatelessWidget {
  const GlobalScorecardSettingsDialog({super.key, required this.settings});

  final GlobalScorecardSettingsModel settings;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: settings,
      child: AlertDialog(
        title: const Text("Global Scorecard Settings"),
        content: GlobalScorecardSettingsWidget(settings: settings),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("CANCEL")),
          TextButton(onPressed: () {
            if (settings.validate()) {
              Navigator.of(context).pop(settings);
            }
          }, child: const Text("SAVE")),
        ],
      ),
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

  TextEditingController minScorecardWidthController = TextEditingController();
  TextEditingController minScorecardHeightController = TextEditingController();

  @override
  void initState() {
    super.initState();
    settings = context.read<GlobalScorecardSettingsModel>();
    minScorecardWidthController.text = settings.minScorecardWidth.toString();
    minScorecardHeightController.text = settings.minScorecardHeight.toString();
  }

  @override
  Widget build(BuildContext context) {
    var model = context.watch<GlobalScorecardSettingsModel>();
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
              model.predictionMode = value;
              model.validate();
            }
          },
        ),
        DropdownButtonFormField<TableTextSize>(
          value: settings.tableTextSize,
          decoration: const InputDecoration(labelText: "Table text size"),
          items: TableTextSize.values.map((size) => DropdownMenuItem(
            value: size,
            child: Text(size.uiLabel),
          )).toList(),
          onChanged: (value) {
            if (value != null) {
              model.tableTextSize = value;
              model.validate();
            }
          },
        ),
        TextFormField(
          decoration: InputDecoration(
            labelText: "Minimum scorecard width",
            errorText: model.minScorecardWidth <= 0 || model.minScorecardWidth > 4096 ? "Please enter a positive number between 1 and 4096" : null,
          ),
          keyboardType: TextInputType.number,
          controller: minScorecardWidthController,
          onChanged: (value) {
            double? parsed = double.tryParse(value);
            if(parsed != null) {
              model.minScorecardWidth = parsed;
            }
            else {
              model.minScorecardWidth = -1;
            }
            model.validate();
          },
        ),
        TextFormField(
          decoration: InputDecoration(
            labelText: "Minimum scorecard height",
            errorText: model.minScorecardHeight <= 0 || model.minScorecardHeight > 4096 ? "Please enter a positive number between 1 and 4096" : null,
          ),
          keyboardType: TextInputType.number,
          controller: minScorecardHeightController,
          onChanged: (value) {
            double? parsed = double.tryParse(value);
            if(parsed != null) {
              model.minScorecardHeight = parsed;
            }
            else {
              model.minScorecardHeight = -1;
            }
            model.validate();
          },
        ),
        CheckboxListTile(
          title: const Text("Show horizontal scrollbars"),
          value: settings.hasHorizontalScrollbar,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (value) {
            if(value != null) {
              model.hasHorizontalScrollbar = value;
            }
            model.validate();
          },
        ),
      ],
    );
  }
}

enum TableTextSize {
  small,
  normal,
  large;

  String get uiLabel => switch(this) {
    TableTextSize.small => "Small",
    TableTextSize.normal => "Normal",
    TableTextSize.large => "Large",
  };

  double get fontSizeFactor => switch(this) {
    TableTextSize.small => 0.8,
    TableTextSize.normal => 1.0,
    TableTextSize.large => 1.2,
  };
}
