import 'dart:convert';

import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';

const _kKey = "k";
const _probBaseKey = "probBase";
const _pctWeightKey = "pctWt";
const _scaleKey = "scale";
const _matchBlendKey = "matchBlend";
const _errorAwareKKey = "errK";
const _errorAwareMaxThresholdKey = "errMaxThresh";
const _errorAwareMinThresholdKey = "errMinThresh";
const _errorAwareZeroValueKey = "errZero";
const _errorAwareLowerMultiplierKey = "errLow";
const _errorAwareUpperMultiplierKey = "errUp";
const _streakAwareKKey = "streakK";
const _directionAwareKKey = "directionK";

class EloSettings extends RaterSettings {
  static const defaultK = 40.0;
  static const defaultProbabilityBase = 4.0;
  static const defaultPercentWeight = 0.4;
  static const defaultPlaceWeight = 0.6;
  static const defaultScale = 400.0;
  static const defaultMatchBlend = 0.3;
  static const defaultErrorAwareMaxThreshold = 40.0;
  static const defaultErrorAwareMinThreshold = 10.0;
  static const defaultErrorAwareZeroValue = 0.0;
  static const defaultErrorAwareUpperMultiplier = 3.0;
  static const defaultErrorAwareLowerMultiplier = 0.2;

  double K;
  /// The base of the exponent in the Elo win probability format.
  ///
  /// For a difference in rating of [scale], the higher-rated player is
  /// [probabilityBase] times more likely to win.
  double probabilityBase;
  double percentWeight;
  double get placeWeight => 1 - percentWeight;
  /// The scale in the Elo win probability format. A player with a rating advantage
  /// of [scale] is [probabilityBase] times more likely to win than the lower-rated player.
  double scale;
  double matchBlend;
  bool byStage;

  /// Whether to adjust K based on shooter rating error.
  bool errorAwareK;
  //
  // /// The value at which K will receive the maximum error-aware multiplier.
  // double errorAwareMaxValue;

  /// If error is greater than this value, K will be increased.
  double errorAwareMaxThreshold;
  /// Controls K when error is greater than [errorAwareMaxThreshold].
  ///
  /// K will be multiplied by 1 + (ratio between actual error - maxThreshold and [errorAwareMaxValue] - maxThreshold) * [errorAwareUpperMultiplier];
  /// that is, when error is equal to scale, K will be multiplied by 1 + (this).
  double errorAwareUpperMultiplier;

  /// If error is less than this value, K will be decreased.
  double errorAwareMinThreshold;
  /// K will be multiplied by the full value of [errorAwareLowerMultiplier] at or below this level.
  double errorAwareZeroValue;
  /// Controls K when error is less than [errorAwareMinThreshold].
  ///
  /// K will be multiplied by 1 - (ratio between minThreshold - actualError and minThreshold) * [errorAwareLowerMultiplier];
  /// that is, when error is equal to 0, K will be multiplied by 1 - (this).
  double errorAwareLowerMultiplier;

  double get stageBlend => 1 - matchBlend;

  /// If true, error-aware K will not apply to shooters on streaks (strong directional trend)
  /// TODO: real streak detection, maybe no more than 1-2 opposite events in (window)?
  bool streakAwareK;

  /// If true, K will be increased for shooters on strong directional trends.
  bool directionAwareK;

  EloSettings({
    this.K = defaultK,
    this.percentWeight = defaultPercentWeight,
    this.probabilityBase = defaultProbabilityBase,
    this.scale = defaultScale,
    this.matchBlend = defaultMatchBlend,
    this.errorAwareK = true,
    this.streakAwareK = false,
    this.byStage = true,
    this.errorAwareZeroValue = defaultErrorAwareZeroValue,
    this.errorAwareLowerMultiplier = defaultErrorAwareLowerMultiplier,
    this.errorAwareMinThreshold = defaultErrorAwareMinThreshold,
    this.errorAwareMaxThreshold = defaultErrorAwareMaxThreshold,
    this.errorAwareUpperMultiplier = defaultErrorAwareUpperMultiplier,
    this.directionAwareK = false,
  });

  void restoreDefaults() {
    this.K = defaultK;
    this.percentWeight = defaultPercentWeight;
    this.probabilityBase = defaultProbabilityBase;
    this.scale = defaultScale;
    this.matchBlend = defaultMatchBlend;
    this.errorAwareK = true;
    this.streakAwareK = false;
    this.byStage = true;
    this.errorAwareZeroValue = defaultErrorAwareZeroValue;
    this.errorAwareLowerMultiplier = defaultErrorAwareLowerMultiplier;
    this.errorAwareMinThreshold = defaultErrorAwareMinThreshold;
    this.errorAwareMaxThreshold = defaultErrorAwareMaxThreshold;
    this.errorAwareUpperMultiplier = defaultErrorAwareUpperMultiplier;
    this.directionAwareK = false;
  }

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[RatingProject.byStageKey] = byStage;
    json[_kKey] = K;
    json[_probBaseKey] = probabilityBase;
    json[_pctWeightKey] = percentWeight;
    json[_scaleKey] = scale;
    json[_matchBlendKey] = matchBlend;
    json[_errorAwareKKey] = errorAwareK;
    json[_errorAwareLowerMultiplierKey] = errorAwareLowerMultiplier;
    json[_errorAwareMaxThresholdKey] = errorAwareMaxThreshold;
    json[_errorAwareMinThresholdKey] = errorAwareMinThreshold;
    json[_errorAwareUpperMultiplierKey] = errorAwareUpperMultiplier;
    json[_errorAwareZeroValueKey] = errorAwareZeroValue;
    json[_streakAwareKKey] = streakAwareK;
    json[_directionAwareKKey] = directionAwareK;
  }

  @override
  void loadFromJson(Map<String, dynamic> json) {
    // fix my oopsie
    if(!(json[_errorAwareKKey] is bool)) {
      json[_errorAwareKKey] = true;
    }

    K = (json[_kKey] ?? defaultK) as double;
    percentWeight = (json[_pctWeightKey] ?? defaultPercentWeight) as double;
    probabilityBase = (json[_probBaseKey] ?? defaultProbabilityBase) as double;
    scale = (json[_scaleKey] ?? defaultScale) as double;
    matchBlend = (json[_matchBlendKey] ?? defaultMatchBlend) as double;
    byStage = (json[RatingProject.byStageKey] ?? true) as bool;
    errorAwareK = (json[_errorAwareKKey] ?? true) as bool;
    errorAwareZeroValue = (json[_errorAwareZeroValueKey] ?? defaultErrorAwareZeroValue) as double;
    errorAwareMinThreshold = (json[_errorAwareMinThresholdKey] ?? defaultErrorAwareMinThreshold) as double;
    errorAwareMaxThreshold = (json[_errorAwareMaxThresholdKey] ?? defaultErrorAwareMaxThreshold) as double;
    errorAwareLowerMultiplier = (json[_errorAwareLowerMultiplierKey] ?? defaultErrorAwareLowerMultiplier) as double;
    errorAwareUpperMultiplier = (json[_errorAwareUpperMultiplierKey] ?? defaultErrorAwareUpperMultiplier) as double;
    streakAwareK = (json[_streakAwareKKey] ?? false) as bool;
    directionAwareK = (json[_directionAwareKKey] ?? false) as bool;
  }

  @override
  String toString() {
    var encoder = JsonEncoder.withIndent("  ");
    var json = <String, dynamic>{};
    encodeToJson(json);
    return encoder.convert(json);
  }
}