
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';

class PointsSettingsController extends RaterSettingsController<PointsSettings> with ChangeNotifier {
  PointsSettings _currentSettings;
  String? lastError;

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

  @override
  void initState() {
    super.initState();

    settings = widget.controller.currentSettings;

    _matchCountController.text = "${settings.matchesToCount}";
    _participationController.text = "${settings.participationBonus}";
    _decayStartController.text = "${settings.decayingPointsStart}";
    _decayFactorController.text = "${settings.decayingPointsFactor}";

    _participationController.addListener(() {
      if (_participationController.text.length > 0) {
        var newBonus = double.tryParse(_participationController.text);
        if (newBonus != null) {
          if (newBonus > 1) {
            newBonus = 1.0;
          }
          else if (newBonus < 0) {
            newBonus = 0.0;
          }
        }

        _validateText();
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
  }

  void _validateText() {
    int? matchesToCount = int.tryParse(_matchCountController.text);
    double? participationBonus = double.tryParse(_participationController.text);
    double? decayStart = double.tryParse(_decayStartController.text);
    double? decayFactor = double.tryParse(_decayFactorController.text);

    if(matchesToCount == null) {
      widget.controller.lastError = "Matches to count incorrectly formatted";
      return;
    }

    if(participationBonus == null || participationBonus > 1 || participationBonus < 0) {
      widget.controller.lastError = "Participation bonus incorrectly formatted or out of range";
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

    settings.matchesToCount = matchesToCount;
    settings.participationBonus = participationBonus;
    settings.decayingPointsStart = decayStart;
    settings.decayingPointsFactor = decayFactor;
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
              child: Text("Mode", style: Theme.of(context).textTheme.subtitle1!),
            ),
            Padding(
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
                    child: Text(v.name),
                  )
                ).toList(),
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
                child: Text("Matches to count", style: Theme.of(context).textTheme.subtitle1!),
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
                message: "The proportion of the top score to add to all participants' scores.",
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text("Participation bonus", style: Theme.of(context).textTheme.subtitle1!),
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
                  child: Text("Decay start", style: Theme.of(context).textTheme.subtitle1!),
                )
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: EdgeInsets.only(right: 20),
                child: TextFormField(
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
                  child: Text("Decay factor", style: Theme.of(context).textTheme.subtitle1!),
                )
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: EdgeInsets.only(right: 20),
                child: TextFormField(
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
      ],
    );
  }
}
