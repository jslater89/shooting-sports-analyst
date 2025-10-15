/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';

class PointsSettingsController extends RaterSettingsController<PointsSettings> with ChangeNotifier {
  PointsSettings _currentSettings;
  String? lastError;

  bool _restoreDefaults = false;

  PointsSettings get currentSettings => _currentSettings;
  set currentSettings(PointsSettings ps) {
    _currentSettings = ps;
    notifyListeners();
  }

  PointsSettingsController({PointsSettings? initialSettings}) :
      _currentSettings = initialSettings != null ? initialSettings : PointsSettings();

  @override
  void restoreDefaults() {
    _currentSettings.restoreDefaults();
    _restoreDefaults = true;
    notifyListeners();
  }

  @override
  void settingsChanged() {
    notifyListeners();
  }

  @override
  String? validate() {
    return lastError;
  }
}

class PointsSettingsWidget extends RaterSettingsWidget<PointsSettings, PointsSettingsController> {
  PointsSettingsWidget({required this.controller}) : super(controller: controller);

  final PointsSettingsController controller;

  @override
  State<PointsSettingsWidget> createState() => _PointsSettingsWidgetState();
}

class _PointsSettingsWidgetState extends State<PointsSettingsWidget> {
  late PointsSettings settings;

  TextEditingController _matchCountController = TextEditingController(text: "${PointsSettings.defaultMatchesToCount}");
  TextEditingController _participationController = TextEditingController(text: "${PointsSettings.defaultParticipationBonus}");
  TextEditingController _decayStartController = TextEditingController(text: "${PointsSettings.defaultDecayingPointsStart}");
  TextEditingController _decayFactorController = TextEditingController(text: "${PointsSettings.defaultDecayingPointsFactor}");
  TextEditingController _stagesRequiredController = TextEditingController(text: "${PointsSettings.defaultStagesRequiredPerMatch}");

  @override
  void initState() {
    super.initState();

    settings = widget.controller.currentSettings;

    _matchCountController.text = "${settings.matchesToCount}";
    _participationController.text = "${settings.participationBonus}";
    _decayStartController.text = "${settings.decayingPointsStart}";
    _decayFactorController.text = "${settings.decayingPointsFactor}";
    _stagesRequiredController.text = "${settings.stagesRequiredPerMatch}";
    _matchCountController.addListener(() {
      var newCount = int.tryParse(_matchCountController.text);
      if(newCount != null) _validateText();
    });

    _decayStartController.addListener(() {
      var newDecay = double.tryParse(_decayStartController.text);
      if(newDecay != null) _validateText();
    });

    _participationController.addListener(() {
      if (_participationController.text.length > 0) {
        var newBonus = double.tryParse(_participationController.text);
        if(newBonus != null) _validateText();
      }
    });

    _decayFactorController.addListener(() {
      if (_decayFactorController.text.length > 0) {
        var newFactor = double.tryParse(_decayFactorController.text);
        if (newFactor != null) {
          if (newFactor > 1) {
            newFactor = 1.0;
          }
          else if (newFactor < 0) {
            newFactor = 0.0;
          }
        }

        _validateText();
      }
    });

    _stagesRequiredController.addListener(() {
      var newStages = int.tryParse(_stagesRequiredController.text);
      if(newStages != null) _validateText();
    });

    widget.controller.addListener(() {
      if(widget.controller._restoreDefaults) {
        setState(() {
          settings = widget.controller._currentSettings;
        });
        widget.controller._restoreDefaults = false;
      }
    });
  }

  void _validateText() {
    int? matchesToCount = int.tryParse(_matchCountController.text);
    double? participationBonus = double.tryParse(_participationController.text);
    double? decayStart = double.tryParse(_decayStartController.text);
    double? decayFactor = double.tryParse(_decayFactorController.text);
    int? stagesRequired = int.tryParse(_stagesRequiredController.text);

    if(matchesToCount == null) {
      widget.controller.lastError = "Matches to count incorrectly formatted";
      return;
    }

    if(participationBonus == null) {
      widget.controller.lastError = "Participation bonus incorrectly formatted";
      return;
    }

    if(decayStart == null || decayStart < 0) {
      widget.controller.lastError = "Decay start incorrectly formatted or out of range";
      return;
    }

    if(decayFactor == null || decayFactor > 1 || decayFactor < 0) {
      widget.controller.lastError = "Decay factor incorrectly formatted or out of range";
      return;
    }

    if(stagesRequired == null || stagesRequired < 0) {
      widget.controller.lastError = "Stages required incorrectly formatted or out of range";
      return;
    }

    settings.matchesToCount = matchesToCount;
    settings.participationBonus = participationBonus;
    settings.decayingPointsStart = decayStart;
    settings.decayingPointsFactor = decayFactor;
    settings.stagesRequiredPerMatch = stagesRequired;
    widget.controller.lastError = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Text("Model", style: Theme.of(context).textTheme.titleMedium!),
            ),
            Tooltip(
              message: settings.mode.tooltip,
              child: Padding(
                padding: const EdgeInsets.only(right: 20.0),
                child: DropdownButton<PointsMode>(
                  value: settings.mode,
                  onChanged: (mode) {
                    if(mode != null) {
                      setState(() {
                        settings.mode = mode;
                      });
                    }
                  },
                  items: PointsMode.values.map((v) =>
                    DropdownMenuItem<PointsMode>(
                      value: v,
                      child: Text(v.uiLabel),
                    )
                  ).toList(),
                ),
              ),
            ),
          ],
        ),
        Row( // match count
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "If 0, use all matches. If greater than 0, use best N matches.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Matches to count", style: Theme.of(context).textTheme.titleMedium!),
              )
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: EdgeInsets.only(right: 20),
                child: TextFormField(
                  controller: _matchCountController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(signed: false, decimal: false),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
              ),
            )
          ],
        ),
        Row( // participation bonus
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
                message: "The number of points to award to each participant for attending a match.\n\n"
                    "Participation bonus is awarded for every match a shooter attends, regardless of\n"
                    "the matches to count setting.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Participation bonus", style: Theme.of(context).textTheme.titleMedium!),
                )
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: EdgeInsets.only(right: 20),
                child: TextFormField(
                  controller: _participationController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(signed: false, decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              ),
            )
          ],
        ),
        Row( // decay start
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
                message: "For decaying score mode, the score to give the winner.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Decay start", style: Theme.of(context).textTheme.titleMedium!),
                )
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.mode == PointsMode.decayingPoints,
                  controller: _decayStartController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(signed: false, decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              ),
            )
          ],
        ),
        Row( // decay factor
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
                message: "For decaying score mode, the factor by which to reduce each score\n"
                    "after the winner's.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Decay factor", style: Theme.of(context).textTheme.titleMedium!),
                )
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.mode == PointsMode.decayingPoints,
                  controller: _decayFactorController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(signed: false, decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              ),
            )
          ],
        ),
        Row( // decay factor
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
                message: "For inverse place mode, the number of attempted/non-DNF stages required for a match entry to count as a\n"
                "valid opponent. Enter 0 to count all match entries, or -1 to count only those with scores on all stages.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Stages required per match", style: Theme.of(context).textTheme.titleMedium!),
                )
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.mode == PointsMode.inversePlace,
                  controller: _stagesRequiredController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(signed: true, decimal: false),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\-]*"), allow: true),
                  ],
                ),
              ),
            )
          ],
        ),
      ],
    );
  }
}
