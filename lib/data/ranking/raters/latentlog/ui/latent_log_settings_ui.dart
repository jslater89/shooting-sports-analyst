/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:shooting_sports_analyst/config/config.dart";
import "package:shooting_sports_analyst/data/help/entries/latent_log_configuration_help.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_settings_ui.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_system_ui.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_settings.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart";

class LatentLogSettingsUi extends RatingSystemUi<LatentLogSettings, LatentLogSettingsController> {
  @override
  LatentLogSettingsController newSettingsController() {
    return LatentLogSettingsController();
  }

  @override
  LatentLogSettingsWidget newSettingsWidget(LatentLogSettingsController controller) {
    return LatentLogSettingsWidget(controller: controller);
  }
}

class LatentLogSettingsController extends RaterSettingsController<LatentLogSettings> with ChangeNotifier {
  LatentLogSettings _currentSettings;

  String? lastError;

  bool _shouldValidate = false;
  bool _restoreDefaults = false;

  LatentLogSettingsController({LatentLogSettings? initialSettings}) :
    _currentSettings = initialSettings != null ? initialSettings : LatentLogSettings();

  @override
  LatentLogSettings get currentSettings => _currentSettings;
  @override
  set currentSettings(LatentLogSettings s) {
    _currentSettings = s;
    notifyListeners();
  }

  @override
  void restoreDefaults() {
    _restoreDefaults = true;
    _currentSettings = LatentLogSettings();
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

class LatentLogSettingsWidget extends RaterSettingsWidget<LatentLogSettings, LatentLogSettingsController> {
  LatentLogSettingsWidget({Key? key, required this.controller}) :
    super(key: key, controller: controller);

  final LatentLogSettingsController controller;

  @override
  State<StatefulWidget> createState() {
    return _LatentLogSettingsWidgetState();
  }
}

enum _VarianceBasis {
  internalUnits,
  displayScaled,
}

class _LatentLogSettingsWidgetState extends State<LatentLogSettingsWidget> {
  late LatentLogSettings settings;

  _VarianceBasis _varianceBasis = _VarianceBasis.internalUnits;

  final TextEditingController _scaleOffsetController = TextEditingController();
  final TextEditingController _scaleFactorController = TextEditingController();
  final TextEditingController _sportVolatilityInternal = TextEditingController();
  final TextEditingController _sportVolatilityScaled = TextEditingController();
  final TextEditingController _skillDriftInternal = TextEditingController();
  final TextEditingController _skillDriftScaled = TextEditingController();
  final TextEditingController _startingVarianceInternal = TextEditingController();
  final TextEditingController _startingVarianceScaled = TextEditingController();
  final TextEditingController _volatilityAdaptController = TextEditingController();
  final TextEditingController _surpriseAdaptController = TextEditingController();
  final TextEditingController _pairwiseBlendController = TextEditingController();

  @override
  void initState() {
    super.initState();
    settings = widget.controller._currentSettings;
    _fillTextFieldsFromSettings();

    widget.controller.addListener(() {
      setState(() {
        if(widget.controller._shouldValidate) {
          _validateText();
          widget.controller._shouldValidate = false;
        }
        else if(widget.controller._restoreDefaults) {
          settings = widget.controller._currentSettings;
          _fillTextFieldsFromSettings();
          widget.controller._restoreDefaults = false;
        }
        else {
          settings = widget.controller._currentSettings;
          _fillTextFieldsFromSettings();
        }
      });
    });

    void attachNumericListener(TextEditingController c, void Function() onOk) {
      c.addListener(() {
        if(double.tryParse(c.text) != null || int.tryParse(c.text) != null) {
          if(!widget.controller._restoreDefaults) {
            onOk();
          }
        }
      });
    }

    attachNumericListener(_scaleOffsetController, () {
      if(!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    _scaleFactorController.addListener(() {
      if(widget.controller._restoreDefaults) {
        return;
      }
      _onScaleFactorTextChanged();
    });
    attachNumericListener(_sportVolatilityInternal, () {
      if(_varianceBasis == _VarianceBasis.internalUnits) {
        _validateText();
      }
    });
    attachNumericListener(_sportVolatilityScaled, () {
      if(_varianceBasis == _VarianceBasis.displayScaled) {
        _validateText();
      }
    });
    attachNumericListener(_skillDriftInternal, () {
      if(_varianceBasis == _VarianceBasis.internalUnits) {
        _validateText();
      }
    });
    attachNumericListener(_skillDriftScaled, () {
      if(_varianceBasis == _VarianceBasis.displayScaled) {
        _validateText();
      }
    });
    attachNumericListener(_startingVarianceInternal, () {
      if(_varianceBasis == _VarianceBasis.internalUnits) {
        _validateText();
      }
    });
    attachNumericListener(_startingVarianceScaled, () {
      if(_varianceBasis == _VarianceBasis.displayScaled) {
        _validateText();
      }
    });
    attachNumericListener(_volatilityAdaptController, () {
      if(!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_surpriseAdaptController, () {
      if(!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_pairwiseBlendController, () {
      if(!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
  }

  @override
  void dispose() {
    _scaleOffsetController.dispose();
    _scaleFactorController.dispose();
    _sportVolatilityInternal.dispose();
    _sportVolatilityScaled.dispose();
    _skillDriftInternal.dispose();
    _skillDriftScaled.dispose();
    _startingVarianceInternal.dispose();
    _startingVarianceScaled.dispose();
    _volatilityAdaptController.dispose();
    _surpriseAdaptController.dispose();
    _pairwiseBlendController.dispose();
    super.dispose();
  }

  void _fillTextFieldsFromSettings() {
    _scaleOffsetController.text = settings.scaleOffset.toStringAsFixed(1);
    _scaleFactorController.text = settings.scaleFactor.toStringAsFixed(3);
    _pairwiseBlendController.text = settings.pairwiseBlendWeight.toStringAsFixed(3);
    _writeVarianceControllersFromSettings();
  }

  void _writeVarianceControllersFromSettings() {
    final sf = settings.scaleFactor;
    _sportVolatilityInternal.text = settings.sportVolatility.toStringAsFixed(6);
    _sportVolatilityScaled.text = (settings.sportVolatility * sf).toStringAsFixed(5);
    _skillDriftInternal.text = settings.skillDriftRate.toStringAsFixed(6);
    _skillDriftScaled.text = (settings.skillDriftRate * sf).toStringAsFixed(5);
    _startingVarianceInternal.text = settings.startingVariance.toStringAsFixed(6);
    _startingVarianceScaled.text = (settings.startingVariance * sf).toStringAsFixed(5);
    _volatilityAdaptController.text = settings.volatilityAdaptationRate.toStringAsFixed(4);
    _surpriseAdaptController.text = settings.surpriseAdaptationRate.toStringAsFixed(4);
  }

  void _onScaleFactorTextChanged() {
    _validateText();
    if(widget.controller.lastError == null) {
      widget.controller.settingsChanged();
    }
  }

  double? _parseVariance({
    required TextEditingController internalC,
    required TextEditingController scaledC,
  }) {
    final sf = double.tryParse(_scaleFactorController.text);
    if(sf == null || sf <= 0) {
      widget.controller.lastError = "Scale factor must be a positive number";
      return null;
    }
    if(_varianceBasis == _VarianceBasis.internalUnits) {
      return double.tryParse(internalC.text);
    }
    final scaled = double.tryParse(scaledC.text);
    if(scaled == null) {
      return null;
    }
    return scaled / sf;
  }

  void _validateText() {
    final scaleOffset = double.tryParse(_scaleOffsetController.text);
    final scaleFactor = double.tryParse(_scaleFactorController.text);
    final pairwise = double.tryParse(_pairwiseBlendController.text);

    if(scaleOffset == null) {
      widget.controller.lastError = "Scale offset formatted incorrectly";
      return;
    }
    if(scaleFactor == null) {
      widget.controller.lastError = "Scale factor formatted incorrectly";
      return;
    }
    if(scaleFactor <= 0) {
      widget.controller.lastError = "Scale factor must be positive";
      return;
    }
    if(pairwise == null) {
      widget.controller.lastError = "Pairwise blend weight formatted incorrectly";
      return;
    }
    if(pairwise < 0) {
      widget.controller.lastError = "Pairwise blend weight must be nonnegative";
      return;
    }

    final sportV = _parseVariance(
      internalC: _sportVolatilityInternal,
      scaledC: _sportVolatilityScaled,
    );
    if(widget.controller.lastError != null) {
      return;
    }
    if(sportV == null) {
      widget.controller.lastError = "Sport volatility formatted incorrectly";
      return;
    }
    if(sportV <= 0) {
      widget.controller.lastError = "Sport volatility must be positive";
      return;
    }

    final drift = _parseVariance(
      internalC: _skillDriftInternal,
      scaledC: _skillDriftScaled,
    );
    if(widget.controller.lastError != null) {
      return;
    }
    if(drift == null) {
      widget.controller.lastError = "Skill drift rate formatted incorrectly";
      return;
    }
    if(drift <= 0) {
      widget.controller.lastError = "Skill drift rate must be positive";
      return;
    }

    final startVar = _parseVariance(
      internalC: _startingVarianceInternal,
      scaledC: _startingVarianceScaled,
    );
    if(widget.controller.lastError != null) {
      return;
    }
    if(startVar == null) {
      widget.controller.lastError = "Starting variance formatted incorrectly";
      return;
    }
    if(startVar <= 0) {
      widget.controller.lastError = "Starting variance must be positive";
      return;
    }

    final volAdapt = double.tryParse(_volatilityAdaptController.text);
    if(volAdapt == null) {
      widget.controller.lastError = "Volatility adaptation rate formatted incorrectly";
      return;
    }
    if(volAdapt <= 0 || volAdapt >= 1) {
      widget.controller.lastError = "Volatility adaptation rate must be between 0 and 1";
      return;
    }

    final surp = double.tryParse(_surpriseAdaptController.text);
    if(surp == null) {
      widget.controller.lastError = "Surprise adaptation rate formatted incorrectly";
      return;
    }
    if(surp < 0) {
      widget.controller.lastError = "Surprise adaptation rate must be nonnegative";
      return;
    }

    settings.scaleOffset = scaleOffset;
    settings.scaleFactor = scaleFactor;
    settings.sportVolatility = sportV;
    settings.skillDriftRate = drift;
    settings.startingVariance = startVar;
    settings.volatilityAdaptationRate = volAdapt;
    settings.surpriseAdaptationRate = surp;
    settings.pairwiseBlendWeight = pairwise;

    _writeVarianceControllersFromSettings();
    widget.controller.lastError = null;
  }

  Widget _numericField({
    required TextEditingController controller,
    required bool enabled,
    required double uiScaleFactor,
  }) {
    return SizedBox(
      width: 108 * uiScaleFactor,
      child: TextFormField(
        enabled: enabled,
        controller: controller,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
        inputFormatters: [
          FilteringTextInputFormatter(RegExp(r"[0-9\.\-]*"), allow: true),
        ],
      ),
    );
  }

  Widget _varianceRow({
    required String label,
    required String tooltip,
    required TextEditingController internalC,
    required TextEditingController scaledC,
    required double uiScaleFactor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Tooltip(
            message: tooltip,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ),
        _numericField(
          controller: internalC,
          enabled: _varianceBasis == _VarianceBasis.internalUnits,
          uiScaleFactor: uiScaleFactor,
        ),
        SizedBox(width: 8 * uiScaleFactor),
        _numericField(
          controller: scaledC,
          enabled: _varianceBasis == _VarianceBasis.displayScaled,
          uiScaleFactor: uiScaleFactor,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final panelWidth = 640 * uiScaleFactor;

    return SizedBox(
      width: panelWidth,
      child: Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(),
            Row(
              children: [
                Text("Latent log ratio configuration", style: Theme.of(context).textTheme.labelLarge!),
                HelpButton(helpTopicId: latentLogConfigHelpId),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: Row(
                children: [
                  Text("Variance parameters: ", style: Theme.of(context).textTheme.bodyMedium),
                  ToggleButtons(
                    isSelected: [
                      _varianceBasis == _VarianceBasis.internalUnits,
                      _varianceBasis == _VarianceBasis.displayScaled,
                    ],
                    onPressed: (i) {
                      setState(() {
                        _validateText();
                        _varianceBasis = i == 0 ? _VarianceBasis.internalUnits : _VarianceBasis.displayScaled;
                        _writeVarianceControllersFromSettings();
                      });
                    },
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("Internal")),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("Scaled")),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(width: 108 * uiScaleFactor, child: Text("Internal", textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelSmall)),
                SizedBox(width: 8 * uiScaleFactor),
                SizedBox(width: 108 * uiScaleFactor, child: Text("× Scale", textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelSmall)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tooltip(
                  message: "Additive offset for top-line rating display: display = internal × scale factor + offset.",
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text("Scale offset (display points)", style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
                _numericField(controller: _scaleOffsetController, enabled: true, uiScaleFactor: uiScaleFactor),
                SizedBox(width: 8 * uiScaleFactor + 108 * uiScaleFactor),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tooltip(
                  message: "Linear multiplier from internal log units to display rating points. Changing this immediately rescales the × Scale column from current internal values.",
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text("Scale factor", style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
                _numericField(controller: _scaleFactorController, enabled: true, uiScaleFactor: uiScaleFactor),
                SizedBox(width: 8 * uiScaleFactor + 108 * uiScaleFactor),
              ],
            ),
            _varianceRow(
              label: "Sport volatility",
              tooltip: "Irreducible log-space variance σ²_sport (internal); scaled column is σ²_sport × scale factor.",
              internalC: _sportVolatilityInternal,
              scaledC: _sportVolatilityScaled,
              uiScaleFactor: uiScaleFactor,
            ),
            _varianceRow(
              label: "Skill drift / period",
              tooltip: "Variance added per rating period from skill drift (internal); scaled is × scale factor.",
              internalC: _skillDriftInternal,
              scaledC: _skillDriftScaled,
              uiScaleFactor: uiScaleFactor,
            ),
            _varianceRow(
              label: "Starting variance",
              tooltip: "Initial / clamp variance for new competitors (internal); scaled is × scale factor.",
              internalC: _startingVarianceInternal,
              scaledC: _startingVarianceScaled,
              uiScaleFactor: uiScaleFactor,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tooltip(
                  message: "Dimensionless β in (0, 1): EMA weight for per-competitor volatility updates.",
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text("Volatility adaptation β", style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
                _numericField(controller: _volatilityAdaptController, enabled: true, uiScaleFactor: uiScaleFactor),
                SizedBox(width: 8 * uiScaleFactor + 108 * uiScaleFactor),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tooltip(
                  message: "Dimensionless γ ≥ 0: extra variance after unexpectedly large innovations.",
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text("Surprise adaptation γ", style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
                _numericField(controller: _surpriseAdaptController, enabled: true, uiScaleFactor: uiScaleFactor),
                SizedBox(width: 8 * uiScaleFactor + 108 * uiScaleFactor),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tooltip(
                  message: "α in P = L + B + αD; dimensionless blend of pairwise residuals.",
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text("Pairwise blend α", style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
                _numericField(controller: _pairwiseBlendController, enabled: true, uiScaleFactor: uiScaleFactor),
                SizedBox(width: 8 * uiScaleFactor + 108 * uiScaleFactor),
              ],
            ),
            SwitchListTile(
              title: const Text("Rate by stage"),
              subtitle: const Text("When off, each match is one rating update (stages still counted)."),
              value: settings.byStage,
              onChanged: (v) {
                setState(() {
                  settings.byStage = v;
                  widget.controller.settingsChanged();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
