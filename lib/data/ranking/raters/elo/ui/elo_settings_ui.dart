import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';

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

  TextEditingController _kController = TextEditingController(text: "${EloSettings.defaultK}");
  TextEditingController _scaleController = TextEditingController(text: "${EloSettings.defaultScale}");
  TextEditingController _baseController = TextEditingController(text: "${EloSettings.defaultProbabilityBase}");
  TextEditingController _pctWeightController = TextEditingController(text: "${EloSettings.defaultPercentWeight}");
  TextEditingController _placeWeightController = TextEditingController(text: "${EloSettings.defaultPlaceWeight}");
  TextEditingController _matchBlendController = TextEditingController(text: "${EloSettings.defaultMatchBlend}");

  TextEditingController _errorAwareZeroController = TextEditingController(text: "${EloSettings.defaultErrorAwareZeroValue}");
  TextEditingController _errorAwareMinThresholdController = TextEditingController(text: "${EloSettings.defaultErrorAwareMinThreshold}");
  TextEditingController _errorAwareMaxThresholdController = TextEditingController(text: "${EloSettings.defaultErrorAwareMaxThreshold}");
  TextEditingController _errorAwareLowerMultController = TextEditingController(text: "${EloSettings.defaultErrorAwareLowerMultiplier}");
  TextEditingController _errorAwareUpperMultController = TextEditingController(text: "${EloSettings.defaultErrorAwareUpperMultiplier}");

  @override
  void initState() {
    super.initState();
    settings = widget.controller._currentSettings;
    _kController.text = "${settings.K.toStringAsFixed(1)}";
    _scaleController.text = "${settings.scale.round()}";
    _baseController.text = "${settings.probabilityBase.toStringAsFixed(1)}";
    _pctWeightController.text = "${settings.percentWeight}";
    _placeWeightController.text = "${settings.placeWeight}";
    _matchBlendController.text = "${settings.matchBlend}";
    _errorAwareZeroController.text = "${settings.errorAwareZeroValue.toStringAsFixed(0)}";
    _errorAwareMinThresholdController.text = "${settings.errorAwareMinThreshold.toStringAsFixed(0)}";
    _errorAwareMaxThresholdController.text = "${settings.errorAwareMaxThreshold.toStringAsFixed(0)}";
    _errorAwareLowerMultController.text = "${(1 - settings.errorAwareLowerMultiplier).toStringAsFixed(2)}";
    _errorAwareUpperMultController.text = "${(settings.errorAwareUpperMultiplier + 1).toStringAsFixed(2)}";

    widget.controller.addListener(() {
      setState(() {
        if(widget.controller._shouldValidate) {
          _validateText();
          widget.controller._shouldValidate = false;
        }
        else if(widget.controller._restoreDefaults) {
          settings = widget.controller._currentSettings;
          _kController.text = "${settings.K.toStringAsFixed(1)}";
          _baseController.text = "${settings.probabilityBase.toStringAsFixed(1)}";
          _scaleController.text = "${settings.scale.round()}";
          _pctWeightController.text = "${settings.percentWeight}";
          _placeWeightController.text = "${settings.placeWeight}";
          _matchBlendController.text = "${settings.matchBlend}";
          _errorAwareZeroController.text = "${settings.errorAwareZeroValue.toStringAsFixed(0)}";
          _errorAwareMinThresholdController.text = "${settings.errorAwareMinThreshold.toStringAsFixed(0)}";
          _errorAwareMaxThresholdController.text = "${settings.errorAwareMaxThreshold.toStringAsFixed(0)}";
          _errorAwareLowerMultController.text = "${(1 - settings.errorAwareLowerMultiplier).toStringAsFixed(2)}";
          _errorAwareUpperMultController.text = "${(settings.errorAwareUpperMultiplier + 1).toStringAsFixed(2)}";
          widget.controller._restoreDefaults = false;
          _validateText();
        }
        else {
          settings = widget.controller._currentSettings;
          _kController.text = "${settings.K.toStringAsFixed(1)}";
          _baseController.text = "${settings.probabilityBase.toStringAsFixed(1)}";
          _scaleController.text = "${settings.scale.round()}";
          _pctWeightController.text = "${settings.percentWeight}";
          _placeWeightController.text = "${settings.placeWeight}";
          _matchBlendController.text = "${settings.matchBlend}";
          _errorAwareZeroController.text = "${settings.errorAwareZeroValue.toStringAsFixed(0)}";
          _errorAwareMinThresholdController.text = "${settings.errorAwareMinThreshold.toStringAsFixed(0)}";
          _errorAwareMaxThresholdController.text = "${settings.errorAwareMaxThreshold.toStringAsFixed(0)}";
          _errorAwareLowerMultController.text = "${settings.errorAwareLowerMultiplier.toStringAsFixed(2)}";
          _errorAwareUpperMultController.text = "${settings.errorAwareUpperMultiplier.toStringAsFixed(2)}";
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
  }

  void _validateText() {
    double? K = double.tryParse(_kController.text);
    double? scale = double.tryParse(_scaleController.text);
    double? pctWeight = double.tryParse(_pctWeightController.text);
    double? matchBlend = double.tryParse(_matchBlendController.text);
    double? base = double.tryParse(_baseController.text);
    double? errorAwareZero = double.tryParse(_errorAwareZeroController.text);
    double? errorAwareMin = double.tryParse(_errorAwareMinThresholdController.text);
    double? errorAwareMax = double.tryParse(_errorAwareMaxThresholdController.text);
    double? errorAwareUpper = double.tryParse(_errorAwareUpperMultController.text);
    double? errorAwareLower = double.tryParse(_errorAwareLowerMultController.text);

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

    if(errorAwareZero == null || errorAwareZero < 0) {
      widget.controller.lastError = "Error aware zero incorrectly formatted or out of range (> 0)";
      return;
    }

    if(errorAwareMin == null || errorAwareMin < errorAwareZero) {
      widget.controller.lastError = "Error aware minimum threshold incorrectly formatted or out of range (> error aware zero)";
      return;
    }

    if(errorAwareMax == null || errorAwareMax < errorAwareMin) {
      widget.controller.lastError = "Error aware maximum threshold incorrectly formatted or out of range (> minimum threshold)";
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

    settings.K = K;
    settings.scale = scale;
    settings.probabilityBase = base;
    settings.percentWeight = pctWeight;
    settings.matchBlend = matchBlend;
    settings.errorAwareZeroValue = errorAwareZero;
    settings.errorAwareMinThreshold = errorAwareMin;
    settings.errorAwareMaxThreshold = errorAwareMax;

    // Convert from raw multipliers to the forms we expect in the
    // algorithm:
    // lower mult is 1 - (errorAwareLower)
    // upper mult is 1 + (errorAwareUpper)
    settings.errorAwareLowerMultiplier = 1 - errorAwareLower;
    settings.errorAwareUpperMultiplier = errorAwareUpper - 1;

    widget.controller.lastError = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
                    FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                  ],
                ),
              ),
            ),
          ]
        ),
        CheckboxListTile(
            title: Tooltip(
                child: Text("Direction-aware K?"),
                message: "Increase K when a shooter is on a long run in one direction."
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
      ],
    );
  }
}