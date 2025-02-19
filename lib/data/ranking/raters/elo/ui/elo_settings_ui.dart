/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/data/help/elo_configuration_help.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';

class EloSettingsController extends RaterSettingsController<EloSettings> with ChangeNotifier {
  EloSettings _currentSettings;
  String? lastError;

  bool _shouldValidate = false;
  bool _restoreDefaults = false;

  EloSettings get currentSettings {
    _shouldValidate = true;
    return _currentSettings;
  }

  set currentSettings(EloSettings s) {
    _currentSettings = s;
    notifyListeners();
  }

  EloSettingsController({EloSettings? initialSettings}) :
      _currentSettings = initialSettings != null ? initialSettings : EloSettings();

  @override
  void restoreDefaults() {
    _restoreDefaults = true;
    _currentSettings.restoreDefaults();
    notifyListeners();
  }

  void settingsChanged() {
    notifyListeners();
  }

  @override
  String? validate() {
    return lastError;
  }
}

class EloSettingsWidget extends RaterSettingsWidget<EloSettings, EloSettingsController> {
  EloSettingsWidget({Key? key, required this.controller}) :
        super(controller: controller);

  final EloSettingsController controller;

  @override
  State<StatefulWidget> createState() {
    return _EloSettingsWidgetState();
  }
}

class _EloSettingsWidgetState extends State<EloSettingsWidget> {
  late EloSettings settings;

  var _kController = TextEditingController(text: "${EloSettings.defaultK}");
  var _scaleController = TextEditingController(text: "${EloSettings.defaultScale}");
  var _baseController = TextEditingController(text: "${EloSettings.defaultProbabilityBase}");
  var _pctWeightController = TextEditingController(text: "${EloSettings.defaultPercentWeight}");
  var _placeWeightController = TextEditingController(text: "${EloSettings.defaultPlaceWeight}");
  var _matchBlendController = TextEditingController(text: "${EloSettings.defaultMatchBlend}");

  var _errorAwareZeroController = TextEditingController(text: "${EloSettings.defaultErrorAwareZeroValue}");
  var _errorAwareMaxController = TextEditingController(text: "${EloSettings.defaultScale}");
  var _errorAwareMinThresholdController = TextEditingController(text: "${EloSettings.defaultErrorAwareMinThreshold}");
  var _errorAwareMaxThresholdController = TextEditingController(text: "${EloSettings.defaultErrorAwareMaxThreshold}");
  var _errorAwareLowerMultController = TextEditingController(text: "${EloSettings.defaultErrorAwareLowerMultiplier}");
  var _errorAwareUpperMultController = TextEditingController(text: "${EloSettings.defaultErrorAwareUpperMultiplier}");

  var _offStreakMultiplierController = TextEditingController(text: "${EloSettings.defaultDirectionAwareOffStreakMultiplier}");
  var _onStreakMultiplierController = TextEditingController(text: "${EloSettings.defaultDirectionAwareOnStreakMultiplier}");
  var _streakLimitController = TextEditingController(text: "${EloSettings.defaultStreakLimit}");

  var _bombProtectionMaxKController = TextEditingController(text: "${EloSettings.defaultBombProtectionMaxKReduction}");
  var _bombProtectionMinKController = TextEditingController(text: "${EloSettings.defaultBombProtectionMinKReduction}");
  var _bombProtectionMaxPercentController = TextEditingController(text: "${EloSettings.defaultBombProtectionMaximumPercent}");
  var _bombProtectionMinPercentController = TextEditingController(text: "${EloSettings.defaultBombProtectionMinimumPercent}");
  var _bombProtectionLowerThreshholdController = TextEditingController(text: "${EloSettings.defaultBombProtectionLowerThreshold}");
  var _bombProtectionUpperThresholdController = TextEditingController(text: "${EloSettings.defaultBombProtectionUpperThreshold}");


  void _fillTextFields() {
    _kController.text = "${settings.K.toStringAsFixed(1)}";
    _scaleController.text = "${settings.scale.round()}";
    _baseController.text = "${settings.probabilityBase.toStringAsFixed(1)}";
    _pctWeightController.text = "${settings.percentWeight}";
    _placeWeightController.text = "${settings.placeWeight}";
    _matchBlendController.text = "${settings.matchBlend}";
    _errorAwareZeroController.text = "${settings.errorAwareZeroValue.toStringAsFixed(0)}";
    _errorAwareMaxController.text = "${settings.errorAwareMaxValue.toStringAsFixed(0)}";
    _errorAwareMinThresholdController.text = "${settings.errorAwareMinThreshold.toStringAsFixed(0)}";
    _errorAwareMaxThresholdController.text = "${settings.errorAwareMaxThreshold.toStringAsFixed(0)}";
    _errorAwareLowerMultController.text = "${(1 - settings.errorAwareLowerMultiplier).toStringAsFixed(2)}";
    _errorAwareUpperMultController.text = "${(settings.errorAwareUpperMultiplier + 1).toStringAsFixed(2)}";
    _offStreakMultiplierController.text = "${(1 - settings.directionAwareOffStreakMultiplier).toStringAsFixed(2)}";
    _onStreakMultiplierController.text = "${(settings.directionAwareOnStreakMultiplier + 1).toStringAsFixed(2)}";
    _streakLimitController.text = "${settings.streakLimit.toStringAsFixed(2)}";
    _bombProtectionMaxKController.text = "${settings.bombProtectionMaximumKReduction.toStringAsFixed(2)}";
    _bombProtectionMinKController.text = "${settings.bombProtectionMinimumKReduction.toStringAsFixed(2)}";
    _bombProtectionMaxPercentController.text = "${settings.bombProtectionMaximumExpectedPercent.roundToDouble()}";
    _bombProtectionMinPercentController.text = "${settings.bombProtectionMinimumExpectedPercent.roundToDouble()}";
    _bombProtectionLowerThreshholdController.text = "${settings.bombProtectionLowerThreshold}";
    _bombProtectionUpperThresholdController.text = "${settings.bombProtectionUpperThreshold}";
  }

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
        else { // restoring defaults or update from outside
          settings = widget.controller._currentSettings;
          _fillTextFields();
          widget.controller._restoreDefaults = false;
          _validateText();
        }
      });
    });

    _kController.addListener(() {
      if(double.tryParse(_kController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });
    _baseController.addListener(() {
      if(double.tryParse(_baseController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });
    _scaleController.addListener(() {
      if(double.tryParse(_scaleController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _pctWeightController.addListener(() {
      if(_pctWeightController.text.length > 0) {
        var newPctWeight = double.tryParse(_pctWeightController.text);
        if(newPctWeight != null) {
          if(newPctWeight > 1) {
            // _pctWeightController.text = "1.0";
            newPctWeight = 1.0;
          }
          else if(newPctWeight < 0) {
            // _pctWeightController.text = "0.0";
            newPctWeight = 0.0;
          }

          var splitNumber = _pctWeightController.text.split(".");
          int fractionDigits = 2;
          if(splitNumber.length > 1) {
            var lastPart = splitNumber.last;
            if(lastPart.length > 0) {
              fractionDigits = lastPart.length;
            }
          }
          _placeWeightController.text = (1.0 - newPctWeight).toStringAsFixed(fractionDigits);
        }

        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _matchBlendController.addListener(() {
      if(_matchBlendController.text.length > 0) {
        var newBlend = double.tryParse(_matchBlendController.text);
        if(newBlend != null) {
          if(newBlend > 1) {
            newBlend = 1.0;
          }
          else if(newBlend < 0) {
            newBlend = 0.0;
          }
        }

        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _errorAwareZeroController.addListener(() {
      if(double.tryParse(_errorAwareZeroController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _errorAwareMaxController.addListener(() {
      if(double.tryParse(_errorAwareMaxController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _errorAwareMinThresholdController.addListener(() {
      if(double.tryParse(_errorAwareMinThresholdController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _errorAwareMaxThresholdController.addListener(() {
      if(double.tryParse(_errorAwareMaxThresholdController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _errorAwareLowerMultController.addListener(() {
      if(double.tryParse(_errorAwareLowerMultController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _errorAwareUpperMultController.addListener(() {
      if(double.tryParse(_errorAwareLowerMultController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _offStreakMultiplierController.addListener(() {
      if(double.tryParse(_offStreakMultiplierController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _onStreakMultiplierController.addListener(() {
      if(double.tryParse(_onStreakMultiplierController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _streakLimitController.addListener(() {
      if(double.tryParse(_streakLimitController.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });

    _addTryParseDoubleListener(_bombProtectionMaxKController);
    _addTryParseDoubleListener(_bombProtectionMinKController);
    _addTryParseDoubleListener(_bombProtectionMaxPercentController);
    _addTryParseDoubleListener(_bombProtectionMinPercentController);
    _addTryParseDoubleListener(_bombProtectionLowerThreshholdController);
    _addTryParseDoubleListener(_bombProtectionUpperThresholdController);
  }

  void _addTryParseDoubleListener(TextEditingController controller) {
    controller.addListener(() {
      if(double.tryParse(controller.text) != null) {
        if(!widget.controller._restoreDefaults) _validateText();
      }
    });
  }

  void _validateText() {
    double? K = double.tryParse(_kController.text);
    double? scale = double.tryParse(_scaleController.text);
    double? pctWeight = double.tryParse(_pctWeightController.text);
    double? matchBlend = double.tryParse(_matchBlendController.text);
    double? base = double.tryParse(_baseController.text);
    double? errorAwareZeroValue = double.tryParse(_errorAwareZeroController.text);
    double? errorAwareMaxValue = double.tryParse(_errorAwareMaxController.text);
    double? errorAwareMinThreshold = double.tryParse(_errorAwareMinThresholdController.text);
    double? errorAwareMaxThreshold = double.tryParse(_errorAwareMaxThresholdController.text);
    double? errorAwareUpper = double.tryParse(_errorAwareUpperMultController.text);
    double? errorAwareLower = double.tryParse(_errorAwareLowerMultController.text);
    double? onStreakMultiplier = double.tryParse(_onStreakMultiplierController.text);
    double? offStreakMultiplier = double.tryParse(_offStreakMultiplierController.text);
    double? streakLimit = double.tryParse(_streakLimitController.text);
    double? bombProtMaxK = double.tryParse(_bombProtectionMaxKController.text);
    double? bombProtMinK = double.tryParse(_bombProtectionMinKController.text);
    double? bombProtMaxPc = double.tryParse(_bombProtectionMaxPercentController.text);
    double? bombProtMinPc = double.tryParse(_bombProtectionMinPercentController.text);
    double? bombProtLowerThresh = double.tryParse(_bombProtectionLowerThreshholdController.text);
    double? bombProtUpperThresh = double.tryParse(_bombProtectionUpperThresholdController.text);

    if(K == null) {
      widget.controller.lastError = "K factor incorrectly formatted";
      return;
    }

    if(scale == null) {
      widget.controller.lastError = "Scale factor incorrectly formatted";
      return;
    }

    if(base == null) {
      widget.controller.lastError = "Probability base incorrectly formatted";
      return;
    }

    if(pctWeight == null || pctWeight > 1 || pctWeight < 0) {
      widget.controller.lastError = "Percent weight incorrectly formatted or out of range (0-1)";
      return;
    }

    if(matchBlend == null || matchBlend > 1 || matchBlend < 0) {
      widget.controller.lastError = "Match blend incorrectly formatted or out of range (0-1)";
      return;
    }

    if(errorAwareZeroValue == null || errorAwareZeroValue < 0) {
      widget.controller.lastError = "Error aware zero incorrectly formatted or out of range (> 0)";
      return;
    }

    if(errorAwareMinThreshold == null || errorAwareMinThreshold < errorAwareZeroValue) {
      widget.controller.lastError = "Error aware minimum threshold incorrectly formatted or out of range (> error aware zero)";
      return;
    }

    if(errorAwareMaxThreshold == null || errorAwareMaxThreshold < errorAwareMinThreshold) {
      widget.controller.lastError = "Error aware maximum threshold incorrectly formatted or out of range (> minimum threshold)";
      return;
    }

    if(errorAwareMaxValue == null || errorAwareMaxValue < errorAwareMaxThreshold) {
      widget.controller.lastError = "Error aware maximum value incorrectly formatted or out of range (> maximum threshold)";
      return;
    }

    if(errorAwareLower == null || errorAwareLower > 1 || errorAwareLower < 0) {
      widget.controller.lastError = "Error aware lower multiplier incorrectly formatted or out of range (0-1)";
      return;
    }

    if(errorAwareUpper == null || errorAwareUpper < 1) {
      widget.controller.lastError = "Error aware upper multiplier incorrectly formatted or out of range (> 1)";
      return;
    }

    if(streakLimit == null || streakLimit < -1.0 || streakLimit > 1.0) {
      widget.controller.lastError = "Streak limit incorrectly formatted or out of range (-1 to 1)";
      return;
    }

    if(offStreakMultiplier == null || offStreakMultiplier > 1) {
      widget.controller.lastError = "Off-streak multiplier incorrectly formatted or out of range (< 1)";
      return;
    }

    if(onStreakMultiplier == null || onStreakMultiplier < 1) {
      widget.controller.lastError = "On-streak multiplier incorrectly formatted or out of range (> 1)";
      return;
    }

    if(bombProtMinK == null || bombProtMinK >= 1 || bombProtMinK < 0) {
      widget.controller.lastError = "Bomb protection minimum K reduction incorrectly formatted or out of range (0-1)";
      return;
    }

    if(bombProtMaxK == null || bombProtMaxK >= 1 || bombProtMaxK < bombProtMinK) {
      widget.controller.lastError = "Bomb protection maximum K reduction incorrectly formatted or out of range (0-1)";
      return;
    }

    if(bombProtMinPc == null || bombProtMinPc < 0) {
      widget.controller.lastError = "Bomb protection minimum expected percent incorrectly formatted or out of range (> 0)";
      return;
    }

    if(bombProtMaxPc == null || bombProtMaxPc < bombProtMinPc) {
      widget.controller.lastError = "Bomb protection maximum expected percent incorrectly formatted or out of range (> 0)";
      return;
    }

    if(bombProtLowerThresh == null || bombProtLowerThresh < 0 || bombProtLowerThresh > 1) {
      widget.controller.lastError = "Bomb protection lower threshold incorrectly formatted or out of range (0-1)";
      return;
    }

    if(bombProtUpperThresh == null || bombProtUpperThresh < bombProtLowerThresh || bombProtUpperThresh > 1) {
      widget.controller.lastError = "Bomb protection upper threshold incorrectly formatted or out of range (0-1)";
      return;
    }

    settings.K = K;
    settings.scale = scale;
    settings.probabilityBase = base;
    settings.percentWeight = pctWeight;
    settings.matchBlend = matchBlend;
    settings.errorAwareZeroValue = errorAwareZeroValue;
    settings.errorAwareMaxValue = errorAwareMaxValue;
    settings.errorAwareMinThreshold = errorAwareMinThreshold;
    settings.errorAwareMaxThreshold = errorAwareMaxThreshold;
    settings.streakLimit = streakLimit;
    settings.bombProtectionMaximumKReduction = bombProtMaxK;
    settings.bombProtectionMinimumKReduction = bombProtMinK;
    settings.bombProtectionMaximumExpectedPercent = bombProtMaxPc;
    settings.bombProtectionMinimumExpectedPercent = bombProtMinPc;
    settings.bombProtectionLowerThreshold = bombProtLowerThresh;
    settings.bombProtectionUpperThreshold = bombProtUpperThresh;

    // Convert from raw multipliers to the forms we expect in the
    // algorithm:
    // lower mult is 1 - (errorAwareLower)
    // upper mult is 1 + (errorAwareUpper)
    settings.errorAwareLowerMultiplier = 1 - errorAwareLower;
    settings.errorAwareUpperMultiplier = errorAwareUpper - 1;
    settings.directionAwareOffStreakMultiplier = 1 - offStreakMultiplier;
    settings.directionAwareOnStreakMultiplier = onStreakMultiplier - 1;

    widget.controller.lastError = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(endIndent: 20),
        Row(
          children: [
            Text("Elo configuration", style: Theme.of(context).textTheme.labelLarge!),
            HelpButton(helpTopicId: eloConfigHelpId),
          ],
        ),
        CheckboxListTile(
          title: Tooltip(
            child: Text("By stage?"),
            message: "Calculate and update ratings after each stage if checked, or after each match if unchecked.",
          ),
          value: settings.byStage,
          onChanged: (value) {
            if(value != null) {
              setState(() {
                settings.byStage = value;
              });
            }
          }
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "K factor adjusts how volatile ratings are. A higher K means ratings will "
                  "change more rapidly in response to missed predictions.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("K factor", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  controller: _kController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message:
                  "Probability base determines how much a rating difference of the scale factor means, in terms of\n"
                  "win likelihood. A probability base of 4 means that a shooter whose rating is better\n"
                  "than another shooter's by the scale factor is 4 times more likely to win than to lose.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Probability base", style: Theme.of(context).textTheme.subtitle1!),
                ),
              ),
              SizedBox(
                width: 100,
                child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: TextFormField(
                    controller: _baseController,
                    textAlign: TextAlign.end,
                    keyboardType: TextInputType.numberWithOptions(),
                    inputFormatters: [
                      FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                    ],
                  ),
                ),
              ),
            ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message:
                  "Scale factor controls the spread of ratings, and how much predictive weight the algorithm assigns to\n"
                  "small differences in score. A high scale factor increases the range of ratings assigned, and also tells\n"
                  "the algorithm to treat close scores as nearly the same. A low scale factor decreases the range of ratings\n"
                  "assigned, and tells the algorithm that small score differences are more meaningful.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Scale factor", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  controller: _scaleController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message:
                  "In by-stage mode, blend match finish into stage finish, to reduce the impact of single bad stages.\n"
                  "0.3, for example, means that a shooter's calculated score on each stage comes 70% from his finish\n"
                  "on that stage, and 30% from his overall match finish. No effect in by-match mode.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Match blend", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  controller: _matchBlendController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
      ),
      Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Percent and placement weight control how much weight the algorithm gives to percent finish vs. placement.\n"
                  "Place weight allows good shooters in crowded fields an opportunity to gain rating by beating their peers. Percent\n"
                  "weight allows lower-level shooters to advance without having to beat high-level competition outright.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Percent/place weight", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 80,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Tooltip(
                      message: "Edit percent weight to change this field.",
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: "Place Wt.",
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                        enabled: false,
                        controller: _placeWeightController,
                        textAlign: TextAlign.end,
                        keyboardType: TextInputType.numberWithOptions(),
                        inputFormatters: [
                          FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: TextFormField(
                      decoration: InputDecoration(
                        labelText: "Pct Wt.",
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                      controller: _pctWeightController,
                      textAlign: TextAlign.end,
                      keyboardType: TextInputType.numberWithOptions(),
                      inputFormatters: [
                        FilteringTextInputFormatter(RegExp(r"[0-9\-\.]*"), allow: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ]
        ),
        Divider(endIndent: 20),
        CheckboxListTile(
          title: Tooltip(
            child: Text("Error-aware K?"),
            message: "Modify K based on error in shooter rating.\n\n"
                "K will be multiplied by (lower multiplier) when rating error is at the\n"
                "zero value, starting at the minimum threshold. It will remain unchanged when\n"
                "error is between the minimum and maximum thresholds. It will be increased when\n"
                "error is above the maximum threshold, multiplied by (upper multiplier) when\n"
                "error is equal to scale."
          ),
          value: settings.errorAwareK,
          onChanged: (value) {
            if(value != null) {
              setState(() {
                settings.errorAwareK = value;
              });
            }
          }
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the rating error where the lower multiplier will be fully applied.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Zero value", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.errorAwareK,
                  controller: _errorAwareZeroController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the rating error where the lower multiplier will begin to be applied.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Min threshold", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.errorAwareK,
                  controller: _errorAwareMinThresholdController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the rating error where the upper multiplier will begin to be applied.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Max threshold", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.errorAwareK,
                  controller: _errorAwareMaxThresholdController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the rating error where the upper multiplier will be fully applied.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Maximum value", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.errorAwareK,
                  controller: _errorAwareMaxController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the amount of K reduction when rating error is below the minimum threshold.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Lower multiplier", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.errorAwareK,
                  controller: _errorAwareLowerMultController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the amount of K increase when rating error is above the maximum threshold.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Upper multiplier", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.errorAwareK,
                  controller: _errorAwareUpperMultController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Divider(endIndent: 20),
        CheckboxListTile(
          title: Tooltip(
              child: Text("Ignore error-aware on streaks?"),
              message: "Disable error-aware K reductions when a shooter is on a long run in one direction."
          ),
          value: settings.streakAwareK,
          enabled: settings.errorAwareK,
          onChanged: (value) {
            if(value != null) {
              setState(() {
                settings.streakAwareK = value;
              });
            }
          }
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message:
                "Shooters with absolute direction greater than this value will not receive error-aware K reductions, and\n"
                    "will qualify for direction-aware K multipliers. Enter between -1.0 for -100 direction and 1.0 for +100 direction.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Streak limit", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.directionAwareK || settings.streakAwareK,
                  controller: _streakLimitController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        CheckboxListTile(
          title: Tooltip(
              child: Text("Direction-aware K?"),
              message: "Increase K when a shooter is on a long run in one direction (a 'streak'). A streak can be\n"
                  "either positive or negative."
          ),
          value: settings.directionAwareK,
          onChanged: (value) {
            if(value != null) {
              setState(() {
                settings.directionAwareK = value;
              });
            }
          }
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message:
                "For rating events that go opposite the current streak, reduce K by this multiplier.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Off-streak multiplier", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.directionAwareK,
                  controller: _offStreakMultiplierController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: "For rating events that go with the current streak, increase K by this multiplier.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("On-streak multiplier", style: Theme.of(context).textTheme.subtitle1!),
                ),
              ),
              SizedBox(
                width: 100,
                child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: TextFormField(
                    enabled: settings.directionAwareK,
                    controller: _onStreakMultiplierController,
                    textAlign: TextAlign.end,
                    keyboardType: TextInputType.numberWithOptions(),
                    inputFormatters: [
                      FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                    ],
                  ),
                ),
              ),
            ]
        ),
        Divider(endIndent: 20),
        CheckboxListTile(
          title: Tooltip(
              child: Text("Bomb protection?"),
              message: "Dramatically reduce K when middle-and-upper-echelon shooters obviously\n"
                  "bomb a stage."
          ),
          value: settings.bombProtection,
          onChanged: (value) {
            if(value != null) {
              setState(() {
                settings.bombProtection = value;
              });
            }
          }
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the minimum percentage by which K will be reduced when bomb protection activates..",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Bomb minimum K reduction", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.bombProtection,
                  controller: _bombProtectionMinKController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the maximum percentage by which K will be reduced when bomb protection activates.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Bomb maximum K reduction", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.bombProtection,
                  controller: _bombProtectionMaxKController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "When the shooter's rating change without any K multipliers is greater than K times this, bomb protection\n"
                  "will begin to apply.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Bomb threshold", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.bombProtection,
                  controller: _bombProtectionLowerThreshholdController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "When the shooter's rating change without any K multipliers is greater than K times this, bomb protection\n"
                  "will fully apply.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Bomb maximum", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.bombProtection,
                  controller: _bombProtectionUpperThresholdController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the minimum expected percentage a shooter must have on a stage for bomb protection to begin to\n"
                  "apply.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Bomb minimum percentage", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.bombProtection,
                  controller: _bombProtectionMinPercentController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Controls the minimum expected percentage a shooter must have on a stage for bomb protection to fully\n"
                  "apply.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Bomb full percentage", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  enabled: settings.bombProtection,
                  controller: _bombProtectionMaxPercentController,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(),
                  inputFormatters: [
                    FilteringTextInputFormatter(RegExp(r"[0-9.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
      ],
    );
  }
}