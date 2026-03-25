/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:math";

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

class _LatentLogSettingsWidgetState extends State<LatentLogSettingsWidget> {
  late LatentLogSettings settings;

  final TextEditingController _scaleOffsetController = TextEditingController();
  final TextEditingController _scaleFactorController = TextEditingController();
  final TextEditingController _sportVarianceInternal =TextEditingController();
  final TextEditingController _skillDriftInternal = TextEditingController();
  final TextEditingController _startingVarianceInternal = TextEditingController();
  final TextEditingController _maximumVarianceInternal = TextEditingController();
  final TextEditingController _matchDifficultyInternal = TextEditingController();
  final TextEditingController _predictionSportInternal = TextEditingController();
  final TextEditingController _predictionBehavioralKappaController =
      TextEditingController();
  final TextEditingController _intraclassCorrelationController = TextEditingController();
  final TextEditingController _dispersionAdaptController = TextEditingController();
  final TextEditingController _surpriseAdaptController = TextEditingController();
  final TextEditingController _pairwiseBlendController = TextEditingController();
  final TextEditingController _baselineRobustnessZController = TextEditingController();
  final TextEditingController _tailNoiseStartPercentController = TextEditingController();
  final TextEditingController _tailNoiseVarianceController = TextEditingController();
  final TextEditingController _weakFieldVarianceController = TextEditingController();
  final TextEditingController _weakFieldMaxSizeController = TextEditingController();
  final TextEditingController _weakFieldWeakFinishThresholdController = TextEditingController();
  final TextEditingController _weakFieldWeakFractionThresholdController = TextEditingController();

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
        }
        else if (widget.controller._restoreDefaults) {
          settings = widget.controller._currentSettings;
          _fillTextFieldsFromSettings();
          widget.controller._restoreDefaults = false;
        }
        else {
          settings = widget.controller._currentSettings;
          _fillTextFieldsFromSettings(shouldSetScaleFactor: false);
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
    attachNumericListener(_sportVarianceInternal, () {
      _validateText();
    });
    attachNumericListener(_skillDriftInternal, () {
      _validateText();
    });
    attachNumericListener(_startingVarianceInternal, () {
      _validateText();
    });
    attachNumericListener(_maximumVarianceInternal, () {
      _validateText();
    });
    attachNumericListener(_matchDifficultyInternal, () {
      _validateText();
    });
    attachNumericListener(_predictionSportInternal, () {
      _validateText();
    });
    attachNumericListener(_predictionBehavioralKappaController, () {
      _validateText();
    });
    attachNumericListener(_intraclassCorrelationController, () {
      if (!widget.controller._restoreDefaults) {
        _validateText();
      }
    });
    attachNumericListener(_dispersionAdaptController, () {
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
    _sportVarianceInternal.dispose();
    _skillDriftInternal.dispose();
    _startingVarianceInternal.dispose();
    _maximumVarianceInternal.dispose();
    _matchDifficultyInternal.dispose();
    _predictionSportInternal.dispose();
    _predictionBehavioralKappaController.dispose();
    _intraclassCorrelationController.dispose();
    _dispersionAdaptController.dispose();
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

  void _fillTextFieldsFromSettings({bool shouldSetScaleFactor = true}) {
    _scaleOffsetController.text = settings.scaleOffset.toStringAsFixed(1);
    if(shouldSetScaleFactor) _scaleFactorController.text = settings.scaleFactor.toStringAsFixed(1);

    _sportVarianceInternal.text = settings.sportVariance.toStringAsFixed(4);
    _skillDriftInternal.text = settings.skillDriftRate.toStringAsFixed(6);
    _startingVarianceInternal.text = settings.startingVariance.toStringAsFixed(4);
    _maximumVarianceInternal.text = settings.maximumVariance.toStringAsFixed(4);
    _matchDifficultyInternal.text = settings.matchDifficultyVariance.toStringAsFixed(4);
    _predictionSportInternal.text = settings.predictionSportVariance.toStringAsFixed(5);
    _predictionBehavioralKappaController.text =
        settings.predictionBehavioralDispersionKappa.toStringAsFixed(3);
    _dispersionAdaptController.text = settings.dispersionAdaptationRate.toStringAsFixed(4);
    _surpriseAdaptController.text = settings.surpriseAdaptationRate.toStringAsFixed(4);
    _intraclassCorrelationController.text = settings.intraclassCorrelation.toStringAsFixed(3);

    _pairwiseBlendController.text = settings.pairwiseBlendWeight.toStringAsFixed(4);
    _baselineRobustnessZController.text = settings.baselineRobustnessZ.toStringAsFixed(4);
    _tailNoiseStartPercentController.text = settings.tailNoiseStartPercent.toStringAsFixed(4);
    _tailNoiseVarianceController.text = settings.tailNoiseVariance.toStringAsFixed(4);
    _weakFieldVarianceController.text = settings.weakFieldVariance.toStringAsFixed(4);
    _weakFieldMaxSizeController.text = settings.weakFieldMaxSize.toStringAsFixed(1);
    _weakFieldWeakFinishThresholdController.text = settings.weakFieldWeakFinishThreshold.toStringAsFixed(4);
    _weakFieldWeakFractionThresholdController.text = settings.weakFieldWeakFractionThreshold.toStringAsFixed(4);
  }

  void _onScaleFactorTextChanged() {
    _validateText(changedScaleFactor: true);
    if (widget.controller.lastError == null) {
      widget.controller.settingsChanged();
    }
  }

  double? _parseVariance({
    required TextEditingController controller,
  }) {
    return double.tryParse(controller.text);
  }

  void _validateText({bool changedScaleFactor = false}) {
    widget.controller.lastError = null;

    final scaleOffset = double.tryParse(_scaleOffsetController.text);
    if (scaleOffset == null) {
      widget.controller.lastError = "Scale offset formatted incorrectly";
      return;
    }
    final scaleFactor = double.tryParse(_scaleFactorController.text);
    if (scaleFactor == null) {
      widget.controller.lastError = "Scale factor formatted incorrectly";
      return;
    }
    if (scaleFactor <= 0) {
      widget.controller.lastError = "Scale factor must be positive";
      return;
    }

    final sportV = _parseVariance(controller: _sportVarianceInternal);
    if (sportV == null) {
      widget.controller.lastError = "Sport volatility formatted incorrectly";
      return;
    }
    if (sportV <= 0) {
      widget.controller.lastError = "Sport volatility must be positive";
      return;
    }

    final drift = _parseVariance(controller: _skillDriftInternal);
    if (drift == null) {
      widget.controller.lastError = "Skill drift rate formatted incorrectly";
      return;
    }
    if (drift <= 0) {
      widget.controller.lastError = "Skill drift rate must be positive";
      return;
    }

    final startVar = _parseVariance(controller: _startingVarianceInternal);
    if (startVar == null) {
      widget.controller.lastError = "Starting variance formatted incorrectly";
      return;
    }
    if (startVar <= 0) {
      widget.controller.lastError = "Starting variance must be positive";
      return;
    }

    final maxVar = _parseVariance(controller: _maximumVarianceInternal);
    if (maxVar == null) {
      widget.controller.lastError = "Maximum variance formatted incorrectly";
      return;
    }
    if (maxVar <= 0) {
      widget.controller.lastError = "Maximum variance must be positive";
      return;
    }
    if (maxVar < startVar) {
      widget.controller.lastError =
          "Maximum variance must be at least starting variance";
      return;
    }

    final intraclassCorrelation = double.tryParse(_intraclassCorrelationController.text);
    if (intraclassCorrelation == null) {
      widget.controller.lastError = "Intraclass correlation formatted incorrectly";
      return;
    }
    if (intraclassCorrelation > 1) {
      widget.controller.lastError = "Intraclass correlation must be between 0 and 1";
      return;
    }
    if (intraclassCorrelation <= 0) {
      widget.controller.lastError = "Intraclass correlation must be positive";
      return;
    }

    final volAdapt = double.tryParse(_dispersionAdaptController.text);
    if (volAdapt == null) {
      widget.controller.lastError =
          "Dispersion adaptation rate formatted incorrectly";
      return;
    }
    if (volAdapt <= 0 || volAdapt >= 1) {
      widget.controller.lastError =
          "Dispersion adaptation rate must be between 0 and 1";
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

    final pairwise = double.tryParse(_pairwiseBlendController.text);
    if (pairwise == null) {
      widget.controller.lastError =
          "Pairwise blend weight formatted incorrectly";
      return;
    }
    if (pairwise < 0) {
      widget.controller.lastError = "Pairwise blend weight must be nonnegative";
      return;
    }

    final matchDiff = _parseVariance(controller: _matchDifficultyInternal);
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

    final baselineRobustnessZ = double.tryParse(
      _baselineRobustnessZController.text,
    );
    if (baselineRobustnessZ == null) {
      widget.controller.lastError =
          "Baseline robustness z formatted incorrectly";
      return;
    }
    if (baselineRobustnessZ < 0) {
      widget.controller.lastError = "Baseline robustness z must be nonnegative";
      return;
    }

    final tailNoiseStartPercent = double.tryParse(
      _tailNoiseStartPercentController.text,
    );
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

    final tailNoiseVariance = double.tryParse(
      _tailNoiseVarianceController.text,
    );
    if (tailNoiseVariance == null) {
      widget.controller.lastError = "Tail noise variance formatted incorrectly";
      return;
    }
    if (tailNoiseVariance < 0) {
      widget.controller.lastError = "Tail noise variance must be nonnegative";
      return;
    }

    final weakFieldVariance = double.tryParse(
      _weakFieldVarianceController.text,
    );
    if (weakFieldVariance == null) {
      widget.controller.lastError = "Weak-field variance formatted incorrectly";
      return;
    }
    if (weakFieldVariance < 0) {
      widget.controller.lastError = "Weak-field variance must be nonnegative";
      return;
    }

    final weakFieldMaxSize = double.tryParse(_weakFieldMaxSizeController.text);
    if (weakFieldMaxSize == null) {
      widget.controller.lastError = "Weak-field max size formatted incorrectly";
      return;
    }
    if (weakFieldMaxSize <= 2) {
      widget.controller.lastError =
          "Weak-field max size must be greater than 2";
      return;
    }

    final weakFieldWeakFinishThreshold = double.tryParse(
      _weakFieldWeakFinishThresholdController.text,
    );
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

    final weakFieldWeakFractionThreshold = double.tryParse(
      _weakFieldWeakFractionThresholdController.text,
    );
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

    final predSport = _parseVariance(controller: _predictionSportInternal);
    if (predSport == null) {
      widget.controller.lastError =
          "Prediction sport variance formatted incorrectly";
      return;
    }
    if (predSport < 0) {
      widget.controller.lastError =
          "Prediction sport variance must be nonnegative";
      return;
    }

    final predKappa = double.tryParse(
      _predictionBehavioralKappaController.text,
    );
    if (predKappa == null) {
      widget.controller.lastError =
          "Prediction behavioral kappa formatted incorrectly";
      return;
    }
    if (predKappa < 0 || predKappa > 2) {
      widget.controller.lastError =
          "Prediction behavioral kappa must be between 0 and 2";
      return;
    }

    setState(() {
      settings.scaleOffset = scaleOffset;
      settings.scaleFactor = scaleFactor;
      settings.sportVariance = sportV;
      settings.skillDriftRate = drift;
      settings.startingVariance = startVar;
      settings.maximumVariance = maxVar;
      settings.dispersionAdaptationRate = volAdapt;
      settings.surpriseAdaptationRate = surp;
      settings.pairwiseBlendWeight = pairwise;
      settings.matchDifficultyVariance = matchDiff;
      settings.baselineRobustnessZ = baselineRobustnessZ;
      settings.tailNoiseStartPercent = tailNoiseStartPercent;
      settings.tailNoiseVariance = tailNoiseVariance;
      settings.weakFieldVariance = weakFieldVariance;
      settings.weakFieldMaxSize = weakFieldMaxSize;
      settings.weakFieldWeakFinishThreshold = weakFieldWeakFinishThreshold;
      settings.weakFieldWeakFractionThreshold = weakFieldWeakFractionThreshold;
      settings.predictionSportVariance = predSport;
      settings.predictionBehavioralDispersionKappa = predKappa;
    });

    widget.controller.lastError = null;
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final panelWidth = 640 * uiScaleFactor;
    final fieldWidth = 108 * uiScaleFactor;
    final columnGap = 8 * uiScaleFactor;
    final trailingSpacerWidth = columnGap + fieldWidth;

    final baselineVariance = settings.sportVariance;

    return SizedBox(
      width: panelWidth,
      child: Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: columnGap,
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
            if(widget.controller.lastError != null)
              Text(
                widget.controller.lastError!,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.error),
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
                    "Scaled",
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const _LatentLogSectionHeading("Scaling Parameters", compactTop: true),
            _LatentLogVarianceRow(
              label: "Scale offset (display points)",
              tooltip:
                  "Additive offset for top-line rating display: display = internal × scale factor + offset. The scaled value is an approximate minimum display rating.",
              internalController: _scaleOffsetController,
              scaledValue: -0.95 * settings.scaleFactor + settings.scaleOffset,
              scaledValuePrecision: 0,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogVarianceRow(
              label: "Scale factor",
              tooltip:
                  "Linear multiplier from internal log units to display rating points. The scaled value is an approximate maximum display rating.",
              internalController: _scaleFactorController,
              scaledValue: 0.5 * settings.scaleFactor + settings.scaleOffset,
              scaledValuePrecision: 0,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            const _LatentLogSectionHeading("Core Parameters"),
            _LatentLogVarianceRow(
              label: "Sport volatility",
              tooltip:
                  "Irreducible variance of the sport; all ratings have this much noise in addition to their own variance.",
              internalController: _sportVarianceInternal,
              scaledValue: sqrt(settings.sportVariance) * settings.scaleFactor,
              scaledValuePrecision: 2,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogVarianceRow(
              label: "Skill drift / period",
              tooltip:
                  "Ratings gain roughly this much variance per month from skill drift.",
              internalController: _skillDriftInternal,
              scaledValue: (sqrt(baselineVariance + settings.skillDriftRate) - sqrt(baselineVariance)) * settings.scaleFactor,
              scaledValuePrecision: 2,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogVarianceRow(
              label: "Starting variance",
              tooltip:
                  "Committed variance for brand-new competitors (internal prior width). Must not exceed maximum variance; scaled is × scale factor.",
              internalController: _startingVarianceInternal,
              scaledValue: sqrt(settings.startingVariance) * settings.scaleFactor,
              scaledValuePrecision: 2,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogVarianceRow(
              label: "Maximum variance",
              tooltip:
                  "Upper cap on committed rating variance after updates and on time-aged variance from skill drift. Can exceed starting variance so veterans may carry more uncertainty than the new-shooter prior.",
              internalController: _maximumVarianceInternal,
              scaledValue: sqrt(settings.maximumVariance) * settings.scaleFactor,
              scaledValuePrecision: 2,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogLabeledNumericRow(
              label: "Intraclass correlation ρ",
              tooltip:
                  "Dimensionless ρ ∈ [0, 1]: minimum baseline uncertainty factor for large fields of unrated competitors..",
              controller: _intraclassCorrelationController,
              fieldWidth: fieldWidth,
              trailingSpacerWidth: trailingSpacerWidth,
            ),
            _LatentLogVarianceRow(
              label: "Dispersion adaptation β",
              tooltip:
                  "Dimensionless β in (0, 1): Smoothing factor for per-competitor dispersion EMA. Scaled value is the half-life in number of rating events.",
              internalController: _dispersionAdaptController,
              scaledValue: log(0.5) / log(1 - settings.dispersionAdaptationRate),
              scaledValuePrecision: 1,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
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
            const _LatentLogSectionHeading("Small / Degenerate Field Parameters"),
            _LatentLogVarianceRow(
              label: "Match difficulty τ²",
              tooltip:
                  "Baseline difficulty for small fields. Smaller = stronger pull toward average difficulty. Values between 0.05 and 0.25 are reasonable for USPSA.",
              internalController: _matchDifficultyInternal,
              scaledValue: sqrt(settings.matchDifficultyVariance) * settings.scaleFactor,
              scaledValuePrecision: 2,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
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
            _LatentLogVarianceRow(
              label: "Tail noise variance",
              tooltip:
                  "Maximum extra observation variance assigned to the deepest tail. Larger values trust very weak finishes less; 0 disables tail-noise inflation.",
              internalController: _tailNoiseVarianceController,
              scaledValue: sqrt(settings.tailNoiseVariance) * settings.scaleFactor,
              scaledValuePrecision: 2,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogVarianceRow(
              label: "Weak-field variance",
              tooltip:
                  "Maximum additional match-level observation variance for tiny, bottom-heavy fields. Larger values suppress pathological gains more aggressively; 0 disables.",
              internalController: _weakFieldVarianceController,
              scaledValue: sqrt(settings.weakFieldVariance) * settings.scaleFactor,
              scaledValuePrecision: 2,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
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
            const _LatentLogSectionHeading("Prediction Parameters"),
            _LatentLogVarianceRow(
              label: "Prediction sport σ²",
              tooltip:
                  "Idiosyncratic per-competitor sport noise for prediction bands. Common-mode match difficulty cancels in relative predictions; only this fraction enters the band. Does not affect rating updates.",
              internalController: _predictionSportInternal,
              scaledValue: sqrt(settings.predictionSportVariance) * settings.scaleFactor,
              scaledValuePrecision: 2,
              fieldWidth: fieldWidth,
              columnGap: columnGap,
              labelStyle: Theme.of(context).textTheme.bodyLarge,
              displayTextStyle: Theme.of(context).textTheme.bodyLarge,
            ),
            _LatentLogLabeledNumericRow(
              label: "Prediction behavioral κ",
              tooltip:
                  "Fraction of behavioral variance (σ²) added to predictive bands: κ × (focal σ² + Σ p_w σ_w²). The update rule still uses full σ² in observation noise; κ only scales overlap with rating variance when forming bands. 0 = ignore behavioral volatility in bands.",
              controller: _predictionBehavioralKappaController,
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

class _LatentLogSectionHeading extends StatelessWidget {
  const _LatentLogSectionHeading(this.title, {this.compactTop = false});

  final String title;
  final bool compactTop;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: 4,
          top: compactTop ? 4 : 12,
          bottom: 2,
        ),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(
              spacing: 8 * uiScaleFactor,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Tooltip(
                  message: tooltip,
                  child: Icon(
                  Icons.info_outline,
                    size: 16 * uiScaleFactor,
                  ),
                ),
              ],
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
    required this.scaledValue,
    required this.scaledValuePrecision,
    required this.fieldWidth,
    required this.columnGap,
    required this.labelStyle,
    required this.displayTextStyle,
  });

  final String label;
  final String tooltip;
  final TextEditingController internalController;
  final double scaledValue;
  final int scaledValuePrecision;
  final double fieldWidth;
  final double columnGap;
  final TextStyle? labelStyle;
  final TextStyle? displayTextStyle;

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(
              spacing: 8 * uiScaleFactor,
              children: [
                Text(
                  label,
                  style: labelStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Tooltip(
                  message: tooltip,
                  child: Icon(
                    Icons.info_outline,
                    size: 16 * uiScaleFactor,
                  ),
                )
              ],
            ),
          ),
        ),
        _LatentLogNumericField(
          controller: internalController,
          fieldWidth: fieldWidth,
        ),
        SizedBox(width: columnGap),
        _LatentLogVarianceDisplaySlot(
          value: scaledValue,
          valuePrecision: scaledValuePrecision,
          fieldWidth: fieldWidth,
          textStyle: displayTextStyle,
        ),
      ],
    );
  }
}

/// Read-only mirror of the computed value (no focus, no TextField) so the inactive column is display-only.
class _LatentLogVarianceDisplaySlot extends StatelessWidget {
  const _LatentLogVarianceDisplaySlot({
    required this.value,
    required this.valuePrecision,
    required this.fieldWidth,
    this.textStyle,
  });

  final double value;
  final int valuePrecision;
  final double fieldWidth;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? Theme.of(context).textTheme.bodyLarge;
    return SizedBox(
      width: fieldWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            value.toStringAsFixed(valuePrecision),
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
      ),
    );
  }
}

