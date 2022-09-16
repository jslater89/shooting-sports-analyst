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
  TextEditingController _pctWeightController = TextEditingController(text: "${EloSettings.defaultPercentWeight}");
  TextEditingController _placeWeightController = TextEditingController(text: "${EloSettings.defaultPlaceWeight}");
  TextEditingController _matchBlendController = TextEditingController(text: "${EloSettings.defaultMatchBlend}");

  @override
  void initState() {
    super.initState();
    settings = widget.controller._currentSettings;
    _kController.text = "${settings.K.toStringAsFixed(1)}";
    _scaleController.text = "${settings.scale.round()}";
    _pctWeightController.text = "${settings.percentWeight}";
    _placeWeightController.text = "${settings.placeWeight}";
    _matchBlendController.text = "${settings.matchBlend}";

    widget.controller.addListener(() {
      setState(() {
        if(widget.controller._shouldValidate) {
          print("validating text");
          _validateText();
          widget.controller._shouldValidate = false;
        }
        else if(widget.controller._restoreDefaults) {
          print("restoring defaults");
          settings = widget.controller._currentSettings;
          _kController.text = "${settings.K.toStringAsFixed(1)}";
          _scaleController.text = "${settings.scale.round()}";
          _pctWeightController.text = "${settings.percentWeight}";
          _placeWeightController.text = "${settings.placeWeight}";
          _matchBlendController.text = "${settings.matchBlend}";
        }
        else {
          print("other notification");
          settings = widget.controller._currentSettings;
          _kController.text = "${settings.K.toStringAsFixed(1)}";
          _scaleController.text = "${settings.scale.round()}";
          _pctWeightController.text = "${settings.percentWeight}";
          _placeWeightController.text = "${settings.placeWeight}";
          _matchBlendController.text = "${settings.matchBlend}";
        }
      });
    });

    _kController.addListener(() {
      if(int.tryParse(_kController.text) != null) {
        _validateText();
      }
    });
    _scaleController.addListener(() {
      if(int.tryParse(_scaleController.text) != null) {
        _validateText();
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

        _validateText();
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

        _validateText();
      }
    });
  }

  void _validateText() {
    double? K = double.tryParse(_kController.text);
    double? scale = double.tryParse(_scaleController.text);
    double? pctWeight = double.tryParse(_pctWeightController.text);
    double? matchBlend = double.tryParse(_matchBlendController.text);

    if(K == null) {
      widget.controller.lastError = "K factor incorrectly formatted";
      return;
    }

    if(scale == null) {
      widget.controller.lastError = "Scale factor incorrectly formatted";
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

    settings.K = K;
    settings.scale = scale;
    settings.percentWeight = pctWeight;
    settings.matchBlend = matchBlend;
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
        CheckboxListTile(
          title: Tooltip(
            child: Text("Error-aware K?"),
            message: "Modify K based on error in shooter rating.",
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
      ],
    );
  }
}