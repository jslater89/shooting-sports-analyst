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

class LatentLogSettingsUi
    extends RatingSystemUi<LatentLogSettings, LatentLogSettingsController> {
  @override
  LatentLogSettingsController newSettingsController() {
    return LatentLogSettingsController();
  }

  @override
  LatentLogSettingsWidget newSettingsWidget(
    LatentLogSettingsController controller,
  ) {
    return LatentLogSettingsWidget(controller: controller);
  }
}

class LatentLogSettingsController
    extends RaterSettingsController<LatentLogSettings>
    with ChangeNotifier {
  LatentLogSettings _currentSettings;

  String? lastError;

  bool _shouldValidate = false;
  bool _restoreDefaults = false;

  LatentLogSettingsController({LatentLogSettings? initialSettings})
    : _currentSettings = initialSettings != null
          ? initialSettings
          : LatentLogSettings();

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

class LatentLogSettingsWidget
    extends
        RaterSettingsWidget<LatentLogSettings, LatentLogSettingsController> {
  LatentLogSettingsWidget({Key? key, required this.controller})
    : super(key: key, controller: controller);

  final LatentLogSettingsController controller;

  @override
  State<StatefulWidget> createState() {
    return _LatentLogSettingsWidgetState();
  }
}

enum _VarianceBasis { internalUnits, displayScaled }

class _LatentLogSettingsWidgetState extends State<LatentLogSettingsWidget> {
  late LatentLogSettings settings;

  _VarianceBasis _varianceBasis = _VarianceBasis.internalUnits;

  final TextEditingController _scaleOffsetController = TextEditingController();
  final TextEditingController _scaleFactorController = TextEditingController();
  final TextEditingController _sportVolatilityInternal =
      TextEditingController();
  final TextEditingController _sportVolatilityScaled = TextEditingController();
  final TextEditingController _skillDriftInternal = TextEditingController();
  final TextEditingController _skillDriftScaled = TextEditingController();
  final TextEditingController _startingVarianceInternal =
      TextEditingController();
  final TextEditingController _startingVarianceScaled = TextEditingController();
  final TextEditingController _matchDifficultyInternal =
      TextEditingController();
  final TextEditingController _matchDifficultyScaled = TextEditingController();
  final TextEditingController _volatilityAdaptController =
      TextEditingController();
  final TextEditingController _surpriseAdaptController =
      TextEditingController();
  final TextEditingController _pairwiseBlendController =
      TextEditingController();
  final TextEditingController _baselineRobustnessZController =
      TextEditingController();
  final TextEditingController _tailNoiseStartPercentController =
      TextEditingController();
  final TextEditingController _tailNoiseVarianceController =
      TextEditingController();
  final TextEditingController _weakFieldVarianceController =
      TextEditingController();
  final TextEditingController _weakFieldMaxSizeController =
      TextEditingController();
  final TextEditingController _weakFieldWeakFinishThresholdController =
      TextEditingController();
  final TextEditingController _weakFieldWeakFractionThresholdController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    settings = widget.controller._currentSettings;
    _fillTextFieldsFromSettings();

    widget.controller.addListener(() {
      setState(() {
        if (widget.controller._shouldValidate) {
          _validateText();
          widget.controller._shouldValidate = false;
        } else if (widget.controller._restoreDefaults) {
          settings = widget.controller._currentSettings;
          _fillTextFieldsFromSettings();
          widget.controller._restoreDefaults = false;
        } else {
          settings = widget.controller._currentSettings;
          _fillTextFieldsFromSettings();
        }
      });
    });

    void attachNumericListener(TextEditingController c, void Function() onOk) {
      c.addListener(() {
        if (double.tryParse(c.text) != null || int.tryParse(c.text) != null) {
          if (!widget.controller._restoreDefaults) {
            onOk();
          }
        }
      });
    }

    attachNumericListener(_scaleOffsetController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    _scaleFactorController.addListener(() {
      if (widget.controller._restoreDefaults) {
        return;
      }
      _onScaleFactorTextChanged();
    });
    attachNumericListener(_sportVolatilityInternal, () {
      if (_varianceBasis == _VarianceBasis.internalUnits) {
        _validateText();
      }
    });
    attachNumericListener(_sportVolatilityScaled, () {
      if (_varianceBasis == _VarianceBasis.displayScaled) {
        _validateText();
      }
    });
    attachNumericListener(_skillDriftInternal, () {
      if (_varianceBasis == _VarianceBasis.internalUnits) {
        _validateText();
      }
    });
    attachNumericListener(_skillDriftScaled, () {
      if (_varianceBasis == _VarianceBasis.displayScaled) {
        _validateText();
      }
    });
    attachNumericListener(_startingVarianceInternal, () {
      if (_varianceBasis == _VarianceBasis.internalUnits) {
        _validateText();
      }
    });
    attachNumericListener(_startingVarianceScaled, () {
      if (_varianceBasis == _VarianceBasis.displayScaled) {
        _validateText();
      }
    });
    attachNumericListener(_matchDifficultyInternal, () {
      if (_varianceBasis == _VarianceBasis.internalUnits) {
        _validateText();
      }
    });
    attachNumericListener(_matchDifficultyScaled, () {
      if (_varianceBasis == _VarianceBasis.displayScaled) {
        _validateText();
      }
    });
    attachNumericListener(_volatilityAdaptController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_surpriseAdaptController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_pairwiseBlendController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_baselineRobustnessZController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_tailNoiseStartPercentController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_tailNoiseVarianceController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_weakFieldVarianceController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_weakFieldMaxSizeController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_weakFieldWeakFinishThresholdController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_weakFieldWeakFractionThresholdController, () {
      if (!widget.controller._restoreDefaults) {
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
    _matchDifficultyInternal.dispose();
    _matchDifficultyScaled.dispose();
    _volatilityAdaptController.dispose();
    _surpriseAdaptController.dispose();
    _pairwiseBlendController.dispose();
    _baselineRobustnessZController.dispose();
    _tailNoiseStartPercentController.dispose();
    _tailNoiseVarianceController.dispose();
    _weakFieldVarianceController.dispose();
    _weakFieldMaxSizeController.dispose();
    _weakFieldWeakFinishThresholdController.dispose();
    _weakFieldWeakFractionThresholdController.dispose();
    super.dispose();
  }

  void _fillTextFieldsFromSettings() {
    _scaleOffsetController.text = settings.scaleOffset.toStringAsFixed(1);
    _scaleFactorController.text = settings.scaleFactor.toStringAsFixed(1);
    _pairwiseBlendController.text = settings.pairwiseBlendWeight
        .toStringAsFixed(4);
    _baselineRobustnessZController.text = settings.baselineRobustnessZ
        .toStringAsFixed(3);
    _tailNoiseStartPercentController.text = settings.tailNoiseStartPercent
        .toStringAsFixed(3);
    _tailNoiseVarianceController.text = settings.tailNoiseVariance
        .toStringAsFixed(3);
    _weakFieldVarianceController.text = settings.weakFieldVariance
        .toStringAsFixed(3);
    _weakFieldMaxSizeController.text = settings.weakFieldMaxSize
        .toStringAsFixed(1);
    _weakFieldWeakFinishThresholdController.text = settings
        .weakFieldWeakFinishThreshold
        .toStringAsFixed(3);
    _weakFieldWeakFractionThresholdController.text = settings
        .weakFieldWeakFractionThreshold
        .toStringAsFixed(3);
    _writeVarianceControllersFromSettings(_VarianceUpdateMode.both);
  }

  void _writeVarianceControllersFromSettings(_VarianceUpdateMode mode) {
    final sf = settings.scaleFactor;
    bool updateInternal =
        mode == _VarianceUpdateMode.both ||
        mode == _VarianceUpdateMode.internalOnly;
    bool updateScaled =
        mode == _VarianceUpdateMode.both ||
        mode == _VarianceUpdateMode.scaledOnly;

    if (updateInternal) {
      _sportVolatilityInternal.text = settings.sportVolatility.toStringAsFixed(
        4,
      );
      _skillDriftInternal.text = settings.skillDriftRate.toStringAsFixed(6);
      _startingVarianceInternal.text = settings.startingVariance
          .toStringAsFixed(4);
      _matchDifficultyInternal.text = settings.matchDifficultyVariance
          .toStringAsFixed(6);
    }
    if (updateScaled) {
      _sportVolatilityScaled.text = (settings.sportVolatility * sf)
          .toStringAsFixed(2);
      _skillDriftScaled.text = (settings.skillDriftRate * sf).toStringAsFixed(
        2,
      );
      _startingVarianceScaled.text = (settings.startingVariance * sf)
          .toStringAsFixed(2);
      _matchDifficultyScaled.text = (settings.matchDifficultyVariance * sf)
          .toStringAsFixed(2);
    }

    // Only update these if we're updating both; they're always active and should never
    // be updated when updating scaled values.
    if (mode == _VarianceUpdateMode.both) {
      _volatilityAdaptController.text = settings.volatilityAdaptationRate
          .toStringAsFixed(4);
      _surpriseAdaptController.text = settings.surpriseAdaptationRate
          .toStringAsFixed(4);
    }
  }

  void _onScaleFactorTextChanged() {
    _validateText();
    if (widget.controller.lastError == null) {
      widget.controller.settingsChanged();
    }
  }

  double? _parseVariance({
    required TextEditingController internalC,
    required TextEditingController scaledC,
  }) {
    final sf = double.tryParse(_scaleFactorController.text);
    if (sf == null || sf <= 0) {
      widget.controller.lastError = "Scale factor must be a positive number";
      return null;
    }
    if (_varianceBasis == _VarianceBasis.internalUnits) {
      return double.tryParse(internalC.text);
    }
    final scaled = double.tryParse(scaledC.text);
    if (scaled == null) {
      return null;
    }
    return scaled / sf;
  }

  void _validateText() {
    widget.controller.lastError = null;

    final scaleOffset = double.tryParse(_scaleOffsetController.text);
    final scaleFactor = double.tryParse(_scaleFactorController.text);
    final pairwise = double.tryParse(_pairwiseBlendController.text);
    final baselineRobustnessZ = double.tryParse(
      _baselineRobustnessZController.text,
    );
    final tailNoiseStartPercent = double.tryParse(
      _tailNoiseStartPercentController.text,
    );
    final tailNoiseVariance = double.tryParse(
      _tailNoiseVarianceController.text,
    );
    final weakFieldVariance = double.tryParse(
      _weakFieldVarianceController.text,
    );
    final weakFieldMaxSize = double.tryParse(_weakFieldMaxSizeController.text);
    final weakFieldWeakFinishThreshold = double.tryParse(
      _weakFieldWeakFinishThresholdController.text,
    );
    final weakFieldWeakFractionThreshold = double.tryParse(
      _weakFieldWeakFractionThresholdController.text,
    );

    if (scaleOffset == null) {
      widget.controller.lastError = "Scale offset formatted incorrectly";
      return;
    }
    if (scaleFactor == null) {
      widget.controller.lastError = "Scale factor formatted incorrectly";
      return;
    }
    if (scaleFactor <= 0) {
      widget.controller.lastError = "Scale factor must be positive";
      return;
    }
    if (pairwise == null) {
      widget.controller.lastError =
          "Pairwise blend weight formatted incorrectly";
      return;
    }
    if (pairwise < 0) {
      widget.controller.lastError = "Pairwise blend weight must be nonnegative";
      return;
    }
    if (baselineRobustnessZ == null) {
      widget.controller.lastError =
          "Baseline robustness z formatted incorrectly";
      return;
    }
    if (baselineRobustnessZ < 0) {
      widget.controller.lastError = "Baseline robustness z must be nonnegative";
      return;
    }
    if (tailNoiseStartPercent == null) {
      widget.controller.lastError =
          "Tail noise start percent formatted incorrectly";
      return;
    }
    if (tailNoiseStartPercent <= 0 || tailNoiseStartPercent >= 1) {
      widget.controller.lastError =
          "Tail noise start percent must be between 0 and 1";
      return;
    }
    if (tailNoiseVariance == null) {
      widget.controller.lastError = "Tail noise variance formatted incorrectly";
      return;
    }
    if (tailNoiseVariance < 0) {
      widget.controller.lastError = "Tail noise variance must be nonnegative";
      return;
    }
    if (weakFieldVariance == null) {
      widget.controller.lastError = "Weak-field variance formatted incorrectly";
      return;
    }
    if (weakFieldVariance < 0) {
      widget.controller.lastError = "Weak-field variance must be nonnegative";
      return;
    }
    if (weakFieldMaxSize == null) {
      widget.controller.lastError = "Weak-field max size formatted incorrectly";
      return;
    }
    if (weakFieldMaxSize <= 2) {
      widget.controller.lastError =
          "Weak-field max size must be greater than 2";
      return;
    }
    if (weakFieldWeakFinishThreshold == null) {
      widget.controller.lastError =
          "Weak-field weak-finish threshold formatted incorrectly";
      return;
    }
    if (weakFieldWeakFinishThreshold <= 0 ||
        weakFieldWeakFinishThreshold >= 1) {
      widget.controller.lastError =
          "Weak-field weak-finish threshold must be between 0 and 1";
      return;
    }
    if (weakFieldWeakFractionThreshold == null) {
      widget.controller.lastError =
          "Weak-field weak-fraction threshold formatted incorrectly";
      return;
    }
    if (weakFieldWeakFractionThreshold < 0 ||
        weakFieldWeakFractionThreshold >= 1) {
      widget.controller.lastError =
          "Weak-field weak-fraction threshold must be in [0, 1)";
      return;
    }

    final sportV = _parseVariance(
      internalC: _sportVolatilityInternal,
      scaledC: _sportVolatilityScaled,
    );
    if (widget.controller.lastError != null) {
      return;
    }
    if (sportV == null) {
      widget.controller.lastError = "Sport volatility formatted incorrectly";
      return;
    }
    if (sportV <= 0) {
      widget.controller.lastError = "Sport volatility must be positive";
      return;
    }

    final drift = _parseVariance(
      internalC: _skillDriftInternal,
      scaledC: _skillDriftScaled,
    );
    if (widget.controller.lastError != null) {
      return;
    }
    if (drift == null) {
      widget.controller.lastError = "Skill drift rate formatted incorrectly";
      return;
    }
    if (drift <= 0) {
      widget.controller.lastError = "Skill drift rate must be positive";
      return;
    }

    final startVar = _parseVariance(
      internalC: _startingVarianceInternal,
      scaledC: _startingVarianceScaled,
    );
    if (widget.controller.lastError != null) {
      return;
    }
    if (startVar == null) {
      widget.controller.lastError = "Starting variance formatted incorrectly";
      return;
    }
    if (startVar <= 0) {
      widget.controller.lastError = "Starting variance must be positive";
      return;
    }

    final matchDiff = _parseVariance(
      internalC: _matchDifficultyInternal,
      scaledC: _matchDifficultyScaled,
    );
    if (widget.controller.lastError != null) {
      return;
    }
    if (matchDiff == null) {
      widget.controller.lastError =
          "Match difficulty variance formatted incorrectly";
      return;
    }
    if (matchDiff <= 0) {
      widget.controller.lastError =
          "Match difficulty variance must be positive";
      return;
    }

    final volAdapt = double.tryParse(_volatilityAdaptController.text);
    if (volAdapt == null) {
      widget.controller.lastError =
          "Volatility adaptation rate formatted incorrectly";
      return;
    }
    if (volAdapt <= 0 || volAdapt >= 1) {
      widget.controller.lastError =
          "Volatility adaptation rate must be between 0 and 1";
      return;
    }

    final surp = double.tryParse(_surpriseAdaptController.text);
    if (surp == null) {
      widget.controller.lastError =
          "Surprise adaptation rate formatted incorrectly";
      return;
    }
    if (surp < 0) {
      widget.controller.lastError =
          "Surprise adaptation rate must be nonnegative";
      return;
    }

    settings.scaleOffset = scaleOffset;
    settings.scaleFactor = scaleFactor;
    settings.sportVolatility = sportV;
    settings.skillDriftRate = drift;
    settings.startingVariance = startVar;
    settings.matchDifficultyVariance = matchDiff;
    settings.volatilityAdaptationRate = volAdapt;
    settings.surpriseAdaptationRate = surp;
    settings.pairwiseBlendWeight = pairwise;
    settings.baselineRobustnessZ = baselineRobustnessZ;
    settings.tailNoiseStartPercent = tailNoiseStartPercent;
    settings.tailNoiseVariance = tailNoiseVariance;
    settings.weakFieldVariance = weakFieldVariance;
    settings.weakFieldMaxSize = weakFieldMaxSize;
    settings.weakFieldWeakFinishThreshold = weakFieldWeakFinishThreshold;
    settings.weakFieldWeakFractionThreshold = weakFieldWeakFractionThreshold;

    final updateMode = _varianceBasis == _VarianceBasis.internalUnits
        ? _VarianceUpdateMode.scaledOnly
        : _varianceBasis == _VarianceBasis.displayScaled
        ? _VarianceUpdateMode.internalOnly
        : _VarianceUpdateMode.both;
    _writeVarianceControllersFromSettings(updateMode);
    widget.controller.lastError = null;
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final panelWidth = 640 * uiScaleFactor;
    final fieldWidth = 108 * uiScaleFactor;
    final columnGap = 8 * uiScaleFactor;
    final trailingSpacerWidth = columnGap + fieldWidth;

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
                Text(
                  "Latent log ratio configuration",
                  style: Theme.of(context).textTheme.labelLarge!,
                ),
                HelpButton(helpTopicId: latentLogConfigHelpId),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: Row(
                children: [
                  Text(
                    "Variance parameters: ",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  ToggleButtons(
                    isSelected: [
                      _varianceBasis == _VarianceBasis.internalUnits,
                      _varianceBasis == _VarianceBasis.displayScaled,
                    ],
                    onPressed: (i) {
                      setState(() {
                        _validateText();
                        _varianceBasis = i == 0
                            ? _VarianceBasis.internalUnits
                            : _VarianceBasis.displayScaled;
                        final updateMode =
                            _varianceBasis == _VarianceBasis.internalUnits
                            ? _VarianceUpdateMode.scaledOnly
                            : _varianceBasis == _VarianceBasis.displayScaled
                            ? _VarianceUpdateMode.internalOnly
                            : _VarianceUpdateMode.both;
                        _writeVarianceControllersFromSettings(updateMode);
                      });
                    },
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text("Internal"),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text("Scaled"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: Text(
                    "Internal",
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                SizedBox(width: columnGap),
                SizedBox(
                  width: fieldWidth,
                  child: Text(
                    "× Scale",
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            _LatentLogLabeledNumericRow(
              label: "Scale offset (display points)",
              tooltip:
                  "Additive offset for top-line rating display: display = internal × scale factor + offset.",
              controller: _scaleOffsetController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Scale factor",
              tooltip:
                  "Linear multiplier from internal log units to display rating points. Changing this immediately rescales the × Scale column from current internal values.",
              controller: _scaleFactorController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogVarianceRow(
              label: "Sport volatility",
              tooltip:
                  "Irreducible log-space variance σ²_sport (internal); scaled column is σ²_sport × scale factor.",
              internalController: _sportVolatilityInternal,
              scaledController: _sportVolatilityScaled,
              varianceBasis: _varianceBasis,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogVarianceRow(
              label: "Skill drift / period",
              tooltip:
                  "Variance added per rating period from skill drift (internal); scaled is × scale factor.",
              internalController: _skillDriftInternal,
              scaledController: _skillDriftScaled,
              varianceBasis: _varianceBasis,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogVarianceRow(
              label: "Starting variance",
              tooltip:
                  "Initial / clamp variance for new competitors (internal); scaled is × scale factor.",
              internalController: _startingVarianceInternal,
              scaledController: _startingVarianceScaled,
              varianceBasis: _varianceBasis,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogVarianceRow(
              label: "Match difficulty τ²",
              tooltip:
                  "Bayesian prior variance on match difficulty. Smaller = stronger shrinkage in small fields. sqrt(τ²) ≈ ±% finish (1SD) of match-to-match difficulty variation.",
              internalController: _matchDifficultyInternal,
              scaledController: _matchDifficultyScaled,
              varianceBasis: _varianceBasis,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogLabeledNumericRow(
              label: "Volatility adaptation β",
              tooltip:
                  "Dimensionless β in (0, 1): EMA weight for per-competitor volatility updates.",
              controller: _volatilityAdaptController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Surprise adaptation γ",
              tooltip:
                  "Dimensionless γ ≥ 0: extra variance after unexpectedly large innovations.",
              controller: _surpriseAdaptController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Pairwise blend α",
              tooltip:
                  "α in P = L + B + αD; dimensionless blend of pairwise residuals.",
              controller: _pairwiseBlendController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Baseline robustness z",
              tooltip:
                  "Huber-style outlier threshold for baseline residuals, in residual sigmas. Lower values downweight extreme field anchors more aggressively; 0 disables.",
              controller: _baselineRobustnessZController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Tail noise start %",
              tooltip:
                  "Finish percentage ratio in (0, 1) below which deep-tail finishes receive extra observation noise. Scores above this use the ordinary variance model.",
              controller: _tailNoiseStartPercentController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Tail noise variance",
              tooltip:
                  "Maximum extra observation variance assigned to the deepest tail. Larger values trust very weak finishes less; 0 disables tail-noise inflation.",
              controller: _tailNoiseVarianceController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Weak-field variance",
              tooltip:
                  "Maximum additional match-level observation variance for tiny, bottom-heavy fields. Larger values suppress pathological gains more aggressively; 0 disables.",
              controller: _weakFieldVarianceController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Weak-field max size",
              tooltip:
                  "Field size at or above which weak-field damping shuts off completely. Two-person fields get the full size penalty; larger fields taper smoothly to zero.",
              controller: _weakFieldMaxSizeController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Weak finish threshold",
              tooltip:
                  "Non-winning finishes below this ratio count as weak when detecting bottom-heavy fields. 0.50 corresponds to 'below half the winner'.",
              controller: _weakFieldWeakFinishThresholdController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogLabeledNumericRow(
              label: "Weak fraction threshold",
              tooltip:
                  "Minimum fraction of non-winners that must be weak before match-level damping activates. 0.50 means about half the non-winners must be below the weak-finish threshold.",
              controller: _weakFieldWeakFractionThresholdController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            SwitchListTile(
              title: const Text("Rate by stage"),
              subtitle: const Text(
                "When off, each match is one rating update (stages still counted).",
              ),
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

class _LatentLogNumericField extends StatelessWidget {
  const _LatentLogNumericField({
    required this.controller,
    required this.fieldWidth,
  });

  final TextEditingController controller;
  final double fieldWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fieldWidth,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        ),
        inputFormatters: [
          FilteringTextInputFormatter(RegExp(r"[0-9\.\-]*"), allow: true),
        ],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
      ),
    );
  }
}

class _LatentLogLabeledNumericRow extends StatelessWidget {
  const _LatentLogLabeledNumericRow({
    required this.label,
    required this.tooltip,
    required this.controller,
    required this.fieldWidth,
    required this.trailingSpacerWidth,
  });

  final String label;
  final String tooltip;
  final TextEditingController controller;
  final double fieldWidth;
  final double trailingSpacerWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Tooltip(
            message: tooltip,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        _LatentLogNumericField(controller: controller, fieldWidth: fieldWidth),
        SizedBox(width: trailingSpacerWidth),
      ],
    );
  }
}

class _LatentLogVarianceRow extends StatelessWidget {
  const _LatentLogVarianceRow({
    required this.label,
    required this.tooltip,
    required this.internalController,
    required this.scaledController,
    required this.varianceBasis,
    required this.fieldWidth,
    required this.columnGap,
    required this.labelStyle,
    required this.displayTextStyle,
  });

  final String label;
  final String tooltip;
  final TextEditingController internalController;
  final TextEditingController scaledController;
  final _VarianceBasis varianceBasis;
  final double fieldWidth;
  final double columnGap;
  final TextStyle? labelStyle;
  final TextStyle? displayTextStyle;

  @override
  Widget build(BuildContext context) {
    final editInternal = varianceBasis == _VarianceBasis.internalUnits;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Tooltip(
            message: tooltip,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Text(
                label,
                style: labelStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        if (editInternal) ...[
          _LatentLogNumericField(
            controller: internalController,
            fieldWidth: fieldWidth,
          ),
          SizedBox(width: columnGap),
          _LatentLogVarianceDisplaySlot(
            controller: scaledController,
            fieldWidth: fieldWidth,
            textStyle: displayTextStyle,
          ),
        ] else ...[
          _LatentLogVarianceDisplaySlot(
            controller: internalController,
            fieldWidth: fieldWidth,
            textStyle: displayTextStyle,
          ),
          SizedBox(width: columnGap),
          _LatentLogNumericField(
            controller: scaledController,
            fieldWidth: fieldWidth,
          ),
        ],
      ],
    );
  }
}

/// Read-only mirror of the computed value (no focus, no TextField) so the inactive column is display-only.
class _LatentLogVarianceDisplaySlot extends StatelessWidget {
  const _LatentLogVarianceDisplaySlot({
    required this.controller,
    required this.fieldWidth,
    this.textStyle,
  });

  final TextEditingController controller;
  final double fieldWidth;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? Theme.of(context).textTheme.bodyLarge;
    return SizedBox(
      width: fieldWidth,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                controller.text,
                textAlign: TextAlign.end,
                style: style,
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _VarianceUpdateMode { both, internalOnly, scaledOnly }
