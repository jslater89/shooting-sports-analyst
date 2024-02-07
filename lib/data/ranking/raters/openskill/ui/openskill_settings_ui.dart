/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_settings.dart';

class OpenskillSettingsController extends RaterSettingsController<OpenskillSettings> with ChangeNotifier {
  OpenskillSettings _currentSettings;

  String? lastError;

  bool _shouldValidate = false;
  bool _restoreDefaults = false;

  OpenskillSettings get currentSettings {
    _shouldValidate = true;
    return _currentSettings;
  }
  set currentSettings(OpenskillSettings s) {
    _currentSettings = s;
    notifyListeners();
  }

  OpenskillSettingsController({OpenskillSettings? initialSettings}) :
        _currentSettings = initialSettings != null ? initialSettings : OpenskillSettings();

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

class OpenskillSettingsWidget extends RaterSettingsWidget<OpenskillSettings, OpenskillSettingsController> {
  OpenskillSettingsWidget({Key? key, required this.controller}) :
        super(key: key, controller: controller);

  final OpenskillSettingsController controller;

  @override
  State<StatefulWidget> createState() {
    return _OpenskillSettingsWidgetState();
  }
}

class _OpenskillSettingsWidgetState extends State<OpenskillSettingsWidget> {
  TextEditingController _betaController = TextEditingController(text: OpenskillSettings.defaultBeta.toStringAsFixed(3));
  TextEditingController _tauController = TextEditingController(text: OpenskillSettings.defaultTau.toStringAsFixed(3));

  late OpenskillSettings settings;

  @override
  void initState() {
    super.initState();
    settings = widget.controller._currentSettings;
    _betaController.text = "${settings.beta.toStringAsFixed(3)}";
    _tauController.text = "${settings.tau.toStringAsFixed(3)}";

    widget.controller.addListener(() {
      setState(() {
        if(widget.controller._shouldValidate) {
          _validateText();
          widget.controller._shouldValidate = false;
        }
        else if(widget.controller._restoreDefaults) {
          settings = widget.controller._currentSettings;
          _betaController.text = "${settings.beta.toStringAsFixed(3)}";
          _tauController.text = "${settings.tau.toStringAsFixed(3)}";
          widget.controller._restoreDefaults = false;
        }
        else {
          settings = widget.controller._currentSettings;
          _betaController.text = "${settings.beta.toStringAsFixed(3)}";
          _tauController.text = "${settings.tau.toStringAsFixed(3)}";
        }
      });
    });

    _betaController.addListener(() {
      if(double.tryParse(_betaController.text) != null) {
        _validateText();
      }
    });
    _tauController.addListener(() {
      if(double.tryParse(_tauController.text) != null) {
        _validateText();
      }
    });
  }

  void _validateText() {
    double? beta = double.tryParse(_betaController.text);
    double? tau = double.tryParse(_tauController.text);

    if(beta == null) {
      widget.controller.lastError = "Beta formatted incorrectly";
      return;
    }

    if(tau == null) {
      widget.controller.lastError = "Tau formatted incorrectly";
      return;
    }

    settings.beta = beta;
    settings.tau = tau;
    widget.controller.lastError = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: "Beta controls the base variability of ratings.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Beta", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  controller: _betaController,
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
              message: "Tau is the increase in each rating's uncertainty per rating event,\n"
                  "which prevents ratings from becoming stagnant over time.",
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text("Tau", style: Theme.of(context).textTheme.subtitle1!),
              ),
            ),
            SizedBox(
              width: 100,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: TextFormField(
                  controller: _tauController,
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
      ],
    );
  }
}