/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/data/help/entries/marbles_configuration_help.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/marble_model.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/ordinal_power_law_model.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/power_law_model.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/sigmoid_model.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';

class MarbleSettingsController extends RaterSettingsController<MarbleSettings> with ChangeNotifier {
  MarbleSettings _currentSettings;

  String? lastError;

  bool _shouldValidate = false;
  bool _restoreDefaults = false;

  MarbleSettingsController({MarbleSettings? initialSettings}) :
    _currentSettings = initialSettings != null ? initialSettings : MarbleSettings();

  @override
  MarbleSettings get currentSettings => _currentSettings;
  set currentSettings(MarbleSettings s) {
    _currentSettings = s;
    notifyListeners();
  }

  @override
  void restoreDefaults() {
    _restoreDefaults = true;
    _currentSettings.restoreDefaults();
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

class MarbleSettingsWidget extends RaterSettingsWidget<MarbleSettings, MarbleSettingsController> {
  MarbleSettingsWidget({Key? key, required this.controller}) :
    super(key: key, controller: controller);

  final MarbleSettingsController controller;

  @override
  State<StatefulWidget> createState() {
    return _MarbleSettingsWidgetState();
  }
}

class _MarbleSettingsWidgetState extends State<MarbleSettingsWidget> {
  TextEditingController _startingMarblesController = TextEditingController(text: MarbleSettings.defaultStartingMarbles.toString());
  TextEditingController _anteController = TextEditingController(text: MarbleSettings.defaultAnte.toStringAsFixed(3));
  TextEditingController _powerController = TextEditingController(text: PowerLawModel.defaultPower.toStringAsFixed(3));
  TextEditingController _steepnessController = TextEditingController(text: SigmoidModel.defaultSteepness.toStringAsFixed(3));
  TextEditingController _midpointController = TextEditingController(text: SigmoidModel.defaultMidpoint.toStringAsFixed(3));
  TextEditingController _ordinalPowerController = TextEditingController(text: OrdinalPowerLawModel.defaultPower.toStringAsFixed(3));

  late MarbleSettings settings;

  @override
  void initState() {
    super.initState();
    settings = widget.controller._currentSettings;
    _startingMarblesController.text = "${settings.startingMarbles}";
    _anteController.text = "${settings.ante}";
    _powerController.text = "${settings.relativeScorePower}";
    _steepnessController.text = "${settings.sigmoidSteepness}";
    _midpointController.text = "${settings.sigmoidMidpoint}";
    _ordinalPowerController.text = "${settings.ordinalPower}";

    widget.controller.addListener(() {
      setState(() {
        if(widget.controller._shouldValidate) {
          _validateText();
          widget.controller._shouldValidate = false;
        }
        else if(widget.controller._restoreDefaults) {
          settings = widget.controller._currentSettings;
          _startingMarblesController.text = "${settings.startingMarbles}";
          _anteController.text = "${settings.ante.toStringAsFixed(3)}";
          _powerController.text = "${settings.relativeScorePower.toStringAsFixed(3)}";
          _steepnessController.text = "${settings.sigmoidSteepness.toStringAsFixed(3)}";
          _midpointController.text = "${settings.sigmoidMidpoint.toStringAsFixed(3)}";
          _ordinalPowerController.text = "${settings.ordinalPower.toStringAsFixed(3)}";
          widget.controller._restoreDefaults = false;
        }
        else {
          settings = widget.controller._currentSettings;
          _startingMarblesController.text = "${settings.startingMarbles}";
          _anteController.text = "${settings.ante.toStringAsFixed(3)}";
          _powerController.text = "${settings.relativeScorePower.toStringAsFixed(3)}";
          _steepnessController.text = "${settings.sigmoidSteepness.toStringAsFixed(3)}";
          _midpointController.text = "${settings.sigmoidMidpoint.toStringAsFixed(3)}";
          _ordinalPowerController.text = "${settings.ordinalPower.toStringAsFixed(3)}";
        }
      });
    });

    _startingMarblesController.addListener(() {
      if(int.tryParse(_startingMarblesController.text) != null) {
        _validateText();
      }
    });

    _anteController.addListener(() {
      if(double.tryParse(_anteController.text) != null) {
        _validateText();
      }
    });

    _powerController.addListener(() {
      if(double.tryParse(_powerController.text) != null) {
        _validateText();
      }
    });

    _steepnessController.addListener(() {
      if(double.tryParse(_steepnessController.text) != null) {
        _validateText();
      }
    });

    _midpointController.addListener(() {
      if(double.tryParse(_midpointController.text) != null) {
        _validateText();
      }
    });

    _ordinalPowerController.addListener(() {
      if(double.tryParse(_ordinalPowerController.text) != null) {
        _validateText();
      }
    });
  }

  void _validateText() {
    int? startingMarbles = int.tryParse(_startingMarblesController.text);
    double? ante = double.tryParse(_anteController.text);
    double? power = double.tryParse(_powerController.text);
    double? steepness = double.tryParse(_steepnessController.text);
    double? midpoint = double.tryParse(_midpointController.text);
    double? ordinalPower = double.tryParse(_ordinalPowerController.text);

    if(startingMarbles == null) {
      widget.controller.lastError = "Starting marbles formatted incorrectly";
      return;
    }

    if(startingMarbles < 0) {
      widget.controller.lastError = "Starting marbles must be positive";
      return;
    }

    if(ante == null) {
      widget.controller.lastError = "Ante formatted incorrectly";
      return;
    }

    if(ante < 0) {
      widget.controller.lastError = "Ante must be positive";
      return;
    }

    if(power == null) {
      widget.controller.lastError = "Power formatted incorrectly";
      return;
    }

    if(power <= 0) {
      widget.controller.lastError = "Power must be positive";
      return;
    }

    if(steepness == null) {
      widget.controller.lastError = "Steepness formatted incorrectly";
      return;
    }

    if(steepness <= 0) {
      widget.controller.lastError = "Steepness must be positive";
      return;
    }

    if(midpoint == null) {
      widget.controller.lastError = "Midpoint formatted incorrectly";
      return;
    }

    if(midpoint < 0 || midpoint > 1) {
      widget.controller.lastError = "Midpoint must be between 0 and 1";
      return;
    }

    if(ordinalPower == null) {
      widget.controller.lastError = "Ordinal power formatted incorrectly";
      return;
    }

    if(ordinalPower <= 0) {
      widget.controller.lastError = "Ordinal power must be positive";
      return;
    }

    settings.startingMarbles = startingMarbles;
    settings.ante = ante;
    settings.relativeScorePower = power;
    settings.sigmoidSteepness = steepness;
    settings.sigmoidMidpoint = midpoint;
    settings.ordinalPower = ordinalPower;
    widget.controller.lastError = null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(),
          Row(
            children: [
              Text("Marble game configuration", style: Theme.of(context).textTheme.labelLarge!),
              HelpButton(helpTopicId: marblesConfigHelpId),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The number of marbles each competitor begins with",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Starting marbles", style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              SizedBox(
                width: 100,
                child: TextFormField(
                  controller: _startingMarblesController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(decimal: false, signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              )
            ]
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The fraction of their marbles a competitor pays to enter a match",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Match ante", style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              SizedBox(
                width: 100,
                child: TextFormField(
                  controller: _anteController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              )
            ]
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The model to use for distributing marbles",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Model", style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              SizedBox(
                width: 160,
                child: InputDecorator(
                  decoration: InputDecoration(
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<MarbleModels>(
                      value: MarbleModels.fromSettings(settings),
                      items: MarbleModels.values.map((e) => DropdownMenuItem(value: e, child: Text(e.displayName))).toList(),
                      onChanged: (value) {
                        setState(() {
                          settings.model = MarbleModel.fromName(value!.modelName, settings: settings);
                        });
                      },
                    ),
                  ),
                ),
              )
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The term for the marble curve; higher gives more marbles to winners",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Power term", style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              SizedBox(
                width: 100,
                child: TextFormField(
                  enabled: settings.model.name == PowerLawModel.modelName,
                  controller: _powerController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              )
            ]
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The steepness of the sigmoid curve.\n\n"
                  "Higher values separate cluster top and bottom competitors but separate mid-pack competitors more.\n"
                  "Lower values spread competitors more evenly.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Steepness", style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              SizedBox(
                width: 100,
                child: TextFormField(
                  enabled: settings.model.name == SigmoidModel.modelName,
                  controller: _steepnessController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              )
            ]
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The midpoint of the sigmoid curve, controlling what score falls on its midpoint.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Midpoint", style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              SizedBox(
                width: 100,
                child: TextFormField(
                  enabled: settings.model.name == SigmoidModel.modelName,
                  controller: _midpointController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              )
            ]
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The term for the ordinal power law curve; higher gives more marbles to winners",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Ordinal power", style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              SizedBox(
                width: 100,
                child: TextFormField(
                  enabled: settings.model.name == OrdinalPowerLawModel.modelName,
                  controller: _ordinalPowerController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              )
            ]
          )
        ]
      ),
    );
  }
}

enum MarbleModels {
  powerLaw("Power law", PowerLawModel.modelName),
  sigmoid("Sigmoid", SigmoidModel.modelName),
  ordinalPowerLaw("Ordinal power law", OrdinalPowerLawModel.modelName);

  final String displayName;
  final String modelName;

  const MarbleModels(this.displayName, this.modelName);

  static MarbleModels fromSettings(MarbleSettings settings) {
    return MarbleModels.values.firstWhere((e) => e.modelName == settings.modelName);
  }
}
