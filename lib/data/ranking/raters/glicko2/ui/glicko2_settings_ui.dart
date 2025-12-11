/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:shooting_sports_analyst/config/config.dart";
import "package:shooting_sports_analyst/data/help/entries/glicko2_configuration_help.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_settings_ui.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_system_ui.dart";
import "package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_score_functions.dart";
import "package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_settings.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart";

class Glicko2SettingsUi extends RatingSystemUi<Glicko2Settings, Glicko2SettingsController> {
  @override
  Glicko2SettingsController newSettingsController() {
    return Glicko2SettingsController();
  }

  @override
  Glicko2SettingsWidget newSettingsWidget(Glicko2SettingsController controller) {
    return Glicko2SettingsWidget(controller: controller);
  }
}

class Glicko2SettingsController extends RaterSettingsController<Glicko2Settings> with ChangeNotifier {
  Glicko2Settings _currentSettings;

  String? lastError;

  bool _shouldValidate = false;
  bool _restoreDefaults = false;

  Glicko2SettingsController({Glicko2Settings? initialSettings}) :
    _currentSettings = initialSettings != null ? initialSettings : Glicko2Settings();

  @override
  Glicko2Settings get currentSettings => _currentSettings;
  set currentSettings(Glicko2Settings s) {
    _currentSettings = s;
    notifyListeners();
  }

  @override
  void restoreDefaults() {
    _restoreDefaults = true;
    _currentSettings = Glicko2Settings();
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

class Glicko2SettingsWidget extends RaterSettingsWidget<Glicko2Settings, Glicko2SettingsController> {
  Glicko2SettingsWidget({Key? key, required this.controller}) :
    super(key: key, controller: controller);

  final Glicko2SettingsController controller;

  @override
  State<StatefulWidget> createState() {
    return _Glicko2SettingsWidgetState();
  }
}

class _Glicko2SettingsWidgetState extends State<Glicko2SettingsWidget> {
  TextEditingController _initialRatingController = TextEditingController(text: Glicko2Settings.defaultInitialRating.toStringAsFixed(0));
  TextEditingController _startingRDController = TextEditingController(text: Glicko2Settings.defaultStartingRD.toStringAsFixed(0));
  TextEditingController _maximumRDController = TextEditingController(text: Glicko2Settings.defaultMaximumRD.toStringAsFixed(0));
  TextEditingController _tauController = TextEditingController(text: Glicko2Settings.defaultTau.toStringAsFixed(2));
  TextEditingController _pseudoRatingPeriodLengthController = TextEditingController(text: Glicko2Settings.defaultPseudoRatingPeriodLength.toString());
  TextEditingController _initialVolatilityController = TextEditingController(text: Glicko2Settings.defaultInitialVolatility.toStringAsFixed(4));
  TextEditingController _maximumRatingDeltaController = TextEditingController(text: Glicko2Settings.defaultMaximumRatingDelta.toStringAsFixed(0));
  TextEditingController _perfectVictoryDifferenceController = TextEditingController(text: Glicko2Settings.defaultPerfectVictoryDifference.toStringAsFixed(3));
  TextEditingController _linearRegionController = TextEditingController(text: Glicko2Settings.defaultLinearRegion.toStringAsFixed(3));
  TextEditingController _marginOfVictoryInflationController = TextEditingController(text: Glicko2Settings.defaultMarginOfVictoryInflation.toStringAsFixed(3));
  TextEditingController _maximumOpponentCountController = TextEditingController(text: Glicko2Settings.defaultMaximumOpponentCount.toString());
  TextEditingController _scalingFactorController = TextEditingController();

  late Glicko2Settings settings;

  @override
  void initState() {
    super.initState();
    settings = widget.controller._currentSettings;
    _fillTextFields();

    widget.controller.addListener(() {
      setState(() {
        if(widget.controller._shouldValidate) {
          _validateText();
          widget.controller._shouldValidate = false;
        }
        else if(widget.controller._restoreDefaults) {
          settings = widget.controller._currentSettings;
          _fillTextFields();
          widget.controller._restoreDefaults = false;
        }
        else {
          settings = widget.controller._currentSettings;
          _fillTextFields();
        }
      });
    });

    _initialRatingController.addListener(() {
      if(double.tryParse(_initialRatingController.text) != null) {
        _validateText();
        setState(() {
          _updateScalingFactorDisplay();
        });
      }
    });

    _startingRDController.addListener(() {
      if(double.tryParse(_startingRDController.text) != null) {
        _validateText();
      }
    });

    _maximumRDController.addListener(() {
      if(double.tryParse(_maximumRDController.text) != null) {
        _validateText();
      }
    });

    _tauController.addListener(() {
      if(double.tryParse(_tauController.text) != null) {
        _validateText();
      }
    });

    _pseudoRatingPeriodLengthController.addListener(() {
      if(int.tryParse(_pseudoRatingPeriodLengthController.text) != null) {
        _validateText();
      }
    });

    _initialVolatilityController.addListener(() {
      if(double.tryParse(_initialVolatilityController.text) != null) {
        _validateText();
      }
    });

    _maximumRatingDeltaController.addListener(() {
      if(double.tryParse(_maximumRatingDeltaController.text) != null) {
        _validateText();
      }
    });

    _perfectVictoryDifferenceController.addListener(() {
      if(double.tryParse(_perfectVictoryDifferenceController.text) != null) {
        _validateText();
      }
    });

    _linearRegionController.addListener(() {
      if(double.tryParse(_linearRegionController.text) != null) {
        _validateText();
      }
    });

    _marginOfVictoryInflationController.addListener(() {
      if(double.tryParse(_marginOfVictoryInflationController.text) != null) {
        _validateText();
      }
    });

    _maximumOpponentCountController.addListener(() {
      if(int.tryParse(_maximumOpponentCountController.text) != null) {
        _validateText();
      }
    });

    _scalingFactorController.addListener(() {
      // Don't auto-validate, user needs to click Apply
    });
  }

  void _fillTextFields() {
    _initialRatingController.text = "${settings.initialRating.toStringAsFixed(0)}";
    _startingRDController.text = "${settings.startingRD.toStringAsFixed(0)}";
    _maximumRDController.text = "${settings.maximumRD.toStringAsFixed(0)}";
    _tauController.text = "${settings.tau.toStringAsFixed(2)}";
    _pseudoRatingPeriodLengthController.text = "${settings.pseudoRatingPeriodLength}";
    _initialVolatilityController.text = "${settings.initialVolatility.toStringAsFixed(4)}";
    _maximumRatingDeltaController.text = "${settings.maximumRatingDelta.toStringAsFixed(0)}";
    _perfectVictoryDifferenceController.text = "${settings.perfectVictoryDifference.toStringAsFixed(3)}";
    _linearRegionController.text = "${settings.eLinearRegion.toStringAsFixed(3)}";
    _marginOfVictoryInflationController.text = "${settings.marginOfVictoryInflation.toStringAsFixed(3)}";
    _updateScalingFactorDisplay();
  }

  void _updateScalingFactorDisplay() {
    _scalingFactorController.text = _getCurrentScalingFactor().toStringAsFixed(4);
  }

  void _applyScalingFactor() {
    // Use the current calculated scaling factor to normalize all scalable fields
    final currentScalingFactor = _getCurrentScalingFactor();
    if(currentScalingFactor <= 0) {
      widget.controller.lastError = "Scaling factor must be a positive number";
      return;
    }

    // Calculate new values based on the current scale factor to normalize them
    final newInitialRating = currentScalingFactor / Glicko2Settings.defaultScalingFactor * Glicko2Settings.defaultInitialRating;
    final newStartingRD = currentScalingFactor / Glicko2Settings.defaultScalingFactor * Glicko2Settings.defaultStartingRD;
    final newMaximumRD = currentScalingFactor / Glicko2Settings.defaultScalingFactor * Glicko2Settings.defaultMaximumRD;
    final newMaximumRatingDelta = currentScalingFactor / Glicko2Settings.defaultScalingFactor * Glicko2Settings.defaultMaximumRatingDelta;

    // Update the settings
    settings.initialRating = newInitialRating;
    settings.startingRD = newStartingRD;
    settings.maximumRD = newMaximumRD;
    settings.maximumRatingDelta = newMaximumRatingDelta;

    // Update the text fields
    _initialRatingController.text = newInitialRating.toStringAsFixed(0);
    _startingRDController.text = newStartingRD.toStringAsFixed(0);
    _maximumRDController.text = newMaximumRD.toStringAsFixed(0);
    _maximumRatingDeltaController.text = newMaximumRatingDelta.toStringAsFixed(0);

    // Validate and notify
    _validateText();
    widget.controller.settingsChanged();
    setState(() {});
  }

  double _getCurrentScalingFactor() {
    final initialRatingValue = double.tryParse(_initialRatingController.text);
    if(initialRatingValue != null && initialRatingValue > 0) {
      return initialRatingValue / Glicko2Settings.defaultInitialRating * Glicko2Settings.defaultScalingFactor;
    }
    return settings.scalingFactor;
  }

  void _validateText() {
    double? initialRating = double.tryParse(_initialRatingController.text);
    double? startingRD = double.tryParse(_startingRDController.text);
    double? maximumRD = double.tryParse(_maximumRDController.text);
    double? tau = double.tryParse(_tauController.text);
    int? pseudoRatingPeriodLength = int.tryParse(_pseudoRatingPeriodLengthController.text);
    double? initialVolatility = double.tryParse(_initialVolatilityController.text);
    double? maximumRatingDelta = double.tryParse(_maximumRatingDeltaController.text);
    double? perfectVictoryDifference = double.tryParse(_perfectVictoryDifferenceController.text);
    double? linearRegion = double.tryParse(_linearRegionController.text);
    double? marginOfVictoryInflation = double.tryParse(_marginOfVictoryInflationController.text);
    int? maximumOpponentCount = int.tryParse(_maximumOpponentCountController.text);

    if(initialRating == null) {
      widget.controller.lastError = "Initial rating formatted incorrectly";
      return;
    }

    if(initialRating <= 0) {
      widget.controller.lastError = "Initial rating must be positive";
      return;
    }

    if(startingRD == null) {
      widget.controller.lastError = "Starting RD formatted incorrectly";
      return;
    }

    if(startingRD <= 0) {
      widget.controller.lastError = "Starting RD must be positive";
      return;
    }

    if(maximumRD == null) {
      widget.controller.lastError = "Maximum RD formatted incorrectly";
      return;
    }

    if(maximumRD <= 0) {
      widget.controller.lastError = "Maximum RD must be positive";
      return;
    }

    if(tau == null) {
      widget.controller.lastError = "Tau formatted incorrectly";
      return;
    }

    if(tau <= 0) {
      widget.controller.lastError = "Tau must be positive";
      return;
    }

    if(pseudoRatingPeriodLength == null) {
      widget.controller.lastError = "Pseudo rating period length formatted incorrectly";
      return;
    }

    if(pseudoRatingPeriodLength <= 0) {
      widget.controller.lastError = "Pseudo rating period length must be positive";
      return;
    }

    if(initialVolatility == null) {
      widget.controller.lastError = "Initial volatility formatted incorrectly";
      return;
    }

    if(initialVolatility <= 0) {
      widget.controller.lastError = "Initial volatility must be positive";
      return;
    }

    if(maximumRatingDelta == null) {
      widget.controller.lastError = "Maximum rating delta formatted incorrectly";
      return;
    }

    if(maximumRatingDelta <= 0) {
      widget.controller.lastError = "Maximum rating delta must be positive";
      return;
    }

    if(settings.scoreFunctionType == ScoreFunctionType.linearMarginOfVictory) {
      if(perfectVictoryDifference == null) {
        widget.controller.lastError = "Perfect victory difference formatted incorrectly";
        return;
      }

      if(perfectVictoryDifference <= 0) {
        widget.controller.lastError = "Perfect victory difference must be positive";
        return;
      }
    }

    if(linearRegion == null) {
      widget.controller.lastError = "Linear region formatted incorrectly";
      return;
    }

    if(linearRegion <= 0 || linearRegion >= 1) {
      widget.controller.lastError = "Linear region must be between 0 and 1";
      return;
    }

    if(marginOfVictoryInflation == null) {
      widget.controller.lastError = "Margin of victory inflation formatted incorrectly";
      return;
    }

    if(marginOfVictoryInflation <= 0) {
      widget.controller.lastError = "Margin of victory inflation must be positive";
      return;
    }

    if(maximumOpponentCount == null) {
      widget.controller.lastError = "Maximum opponent count formatted incorrectly";
      return;
    }

    if(maximumOpponentCount <= 0) {
      widget.controller.lastError = "Maximum opponent count must be positive";
      return;
    }

    settings.initialRating = initialRating;
    settings.startingRD = startingRD;
    settings.maximumRD = maximumRD;
    settings.tau = tau;
    settings.pseudoRatingPeriodLength = pseudoRatingPeriodLength;
    settings.initialVolatility = initialVolatility;
    settings.maximumRatingDelta = maximumRatingDelta;
    settings.eLinearRegion = linearRegion;
    settings.marginOfVictoryInflation = marginOfVictoryInflation;
    if(settings.scoreFunctionType == ScoreFunctionType.linearMarginOfVictory) {
      settings.perfectVictoryDifference = perfectVictoryDifference!;
    }
    // Update scaling factor display when initial rating changes
    _updateScalingFactorDisplay();
    widget.controller.lastError = null;
  }

  @override
  Widget build(BuildContext context) {
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(),
          Row(
            children: [
              Text("Glicko-2 configuration", style: Theme.of(context).textTheme.labelLarge!),
              HelpButton(helpTopicId: glicko2ConfigHelpId),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The initial rating for new competitors, in display units. Controls the scaling factor.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Initial rating", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 100 * uiScaleFactor,
                child: TextFormField(
                  controller: _initialRatingController,
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
                message: "The scaling factor to convert between internal and display units. Automatically calculated from initial rating.\n"
                "Use the Apply button to set initial rating, starting RD, maximum RD, and maximum rating delta to match a target scaling factor.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Scaling factor", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 100 * uiScaleFactor,
                    child: TextFormField(
                      enabled: false,
                      controller: _scalingFactorController,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  SizedBox(width: 8),
                  Tooltip(
                    message: "Set initial rating, starting RD, maximum RD, and maximum rating delta to match the current scaling factor proportionally",
                    child: IconButton(
                      onPressed: _applyScalingFactor,
                      icon: Icon(Icons.arrow_forward),
                    ),
                  ),
                ],
              )
            ]
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The starting RD (rating deviation) for new competitors, in display units",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Starting RD", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 100 * uiScaleFactor,
                child: TextFormField(
                  controller: _startingRDController,
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
                message: "The maximum RD (rating deviation) to allow, in display units",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Maximum RD", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 100 * uiScaleFactor,
                child: TextFormField(
                  controller: _maximumRDController,
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
                message: "The largest rating change permitted per match, in display units",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Maximum rating delta", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 100 * uiScaleFactor,
                child: TextFormField(
                  controller: _maximumRatingDeltaController,
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
                message: "The maximum number of opponents to consider when calculating rating updates for new players",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Maximum opponent count", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 100 * uiScaleFactor,
                child: TextFormField(
                  controller: _maximumOpponentCountController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(decimal: false, signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                )
              )
            ]
          ),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "The tau value controls the rate of volatility change. Higher values allow volatility to change more quickly.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Tau", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 100 * uiScaleFactor,
                child: TextFormField(
                  controller: _tauController,
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
                message: "The length of a pseudo-rating-period for increasing RD over time, in days",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Pseudo rating period length", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 100 * uiScaleFactor,
                child: TextFormField(
                  controller: _pseudoRatingPeriodLengthController,
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
                message: "The initial volatility for new competitors",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Initial volatility", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 100 * uiScaleFactor,
                child: TextFormField(
                  controller: _initialVolatilityController,
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
                message: "The method to use for selecting opponents when calculating rating updates",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Opponent selection mode", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 200 * uiScaleFactor,
                child: InputDecorator(
                  decoration: InputDecoration(
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<OpponentSelectionMode>(
                      value: settings.opponentSelectionMode,
                      items: OpponentSelectionMode.values.map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(_opponentSelectionModeDisplayName(e)),
                      )).toList(),
                      onChanged: (value) {
                        setState(() {
                          settings.opponentSelectionMode = value!;
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
                message: "The score function type to use for calculating match scores",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Score function", style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              SizedBox(
                width: 200 * uiScaleFactor,
                child: InputDecorator(
                  decoration: InputDecoration(
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ScoreFunctionType>(
                      value: settings.scoreFunctionType,
                      items: ScoreFunctionType.values.map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.uiLabel),
                      )).toList(),
                      onChanged: (value) {
                        setState(() {
                          settings.scoreFunctionType = value!;
                          _validateText();
                        });
                      },
                    ),
                  ),
                ),
              )
            ],
          ),
          if(settings.scoreFunctionType == ScoreFunctionType.linearMarginOfVictory)
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tooltip(
                  message: "The difference in ratio between shooter and opponent that results in a perfect victory score (1.0) or perfect loss score (0.0)",
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text("Perfect victory difference", style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
                SizedBox(
                  width: 100 * uiScaleFactor,
                  child: TextFormField(
                    controller: _perfectVictoryDifferenceController,
                    textAlign: TextAlign.end,
                    keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
                    inputFormatters: [
                      FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                    ],
                  ),
                )
              ]
            ),
          if(settings.scoreFunctionType == ScoreFunctionType.linearMarginOfVictory)
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tooltip(
                  message: "The region of the score function in predictions, measured in from 0 and 1",
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text("Linear region", style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
                SizedBox(
                  width: 100 * uiScaleFactor,
                  child: TextFormField(
                    controller: _linearRegionController,
                    textAlign: TextAlign.end,
                    keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
                    inputFormatters: [
                      FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                    ],
                  ),
                )
              ]
            ),
          if(settings.scoreFunctionType == ScoreFunctionType.linearMarginOfVictory)
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tooltip(
                  message: "The margin of victory inflation factor for predictions, which can help reduce numerical instability/compression from repeated applications of the score function",
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text("Margin of victory inflation", style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
                SizedBox(
                  width: 100 * uiScaleFactor,
                  child: TextFormField(
                    controller: _marginOfVictoryInflationController,
                    textAlign: TextAlign.end,
                    keyboardType: TextInputType.numberWithOptions(decimal: true, signed: false),
                    inputFormatters: [
                      FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                    ],
                  ),
                )
              ]
            ),

          // CheckboxListTile(
          //   title: Tooltip(
          //     child: Text("By stage? (experimental)"),
          //     message: "Calculate and update ratings after each stage if checked, or after each match if unchecked.\n"
          //       "By-stage mode is experimental and may not work as expected.",
          //   ),
          //   value: settings.byStage,
          //   onChanged: (value) {
          //     if(value != null) {
          //       setState(() {
          //         settings.byStage = value;
          //       });
          //     }
          //   }
          // ),
        ]
      ),
    );
  }

  String _opponentSelectionModeDisplayName(OpponentSelectionMode mode) {
    switch(mode) {
      case OpponentSelectionMode.all:
        return "All opponents";
      case OpponentSelectionMode.top10Pct:
        return "Top 10%";
      case OpponentSelectionMode.nearby:
        return "Nearby opponents";
      case OpponentSelectionMode.topAndNearby:
        return "Top and nearby";
    }
  }
}
