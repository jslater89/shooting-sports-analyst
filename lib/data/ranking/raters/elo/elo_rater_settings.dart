import 'dart:convert';

import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';

const _kKey = "k";
const _probBaseKey = "probBase";
const _pctWeightKey = "pctWt";
const _scaleKey = "scale";
const _matchBlendKey = "matchBlend";
const _errorAwareKKey = "errK";
const _errorAwareMaxValueKey = "errMaxVal";
const _errorAwareMaxThresholdKey = "errMaxThresh";
const _errorAwareMinThresholdKey = "errMinThresh";
const _errorAwareZeroValueKey = "errZero";
const _errorAwareLowerMultiplierKey = "errLow";
const _errorAwareUpperMultiplierKey = "errUp";
const _streakAwareKKey = "streakK";
const _directionAwareKKey = "directionK";
const _offStreakMultiplierKey = "offStreakMult";
const _onStreakMultiplierKey = "onStreakMult";
const _streakLimitKey = "streakLim";
const _bombProtectionKey = "bombProtection";
const _bpMaxKKey = "bpMaxK";
const _bpMinKKey = "bpMinK";
const _bpMaxPercentKey = "bpMaxPc";
const _bpMinPercentKey = "bpMinPc";
const _bpUpperThreshKey = "bpUpperThresh";
const _bpLowerThreshKey = "bpLowerThresh";

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
  static const defaultDirectionAwareOffStreakMultiplier = 0.0;
  static const defaultDirectionAwareOnStreakMultiplier = 0.5;
  static const defaultStreakLimit = 0.4;
  static const defaultBombProtectionLowerThreshold = 0.4;
  static const defaultBombProtectionUpperThreshold = 0.6;
  static const defaultBombProtectionMinimumPercent = 75.0;
  static const defaultBombProtectionMaximumPercent = 100.0;
  static const defaultBombProtectionMinKReduction = 0.1;
  static const defaultBombProtectionMaxKReduction = 0.75;

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

  /// [errorAwareUpperMultiplier] will be fully applied at or above this error.
  double errorAwareMaxValue;
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
  bool streakAwareK;

  /// [streakAwareK] and [directionAwareK] will only be applied when the absolute value of a shooter's
  /// direction exceeds this property.
  double streakLimit;

  /// If true, K will be increased for shooters on strong directional trends.
  bool directionAwareK;

  /// The maximum multiplier to K from [directionAwareK] at 1.0 |direction|,
  /// when moving in the direction of the current streak.
  ///
  /// Stored as an amount to add to 1.0 (e.g., 1.5x multiplier is 0.5).
  double directionAwareOnStreakMultiplier;

  /// The maximum multiplier to K from [directionAwareK], when moving opposite
  /// the current streak.
  ///
  /// Stored as an amount to subtract from 1.0 (e.g., 0.75x multiplier is 0.25).
  double directionAwareOffStreakMultiplier;

  /// An Obvious Rules Patch™ for the issue where it's easy for middle-to-upper-echelon
  /// shooters to lose a bunch of Elo bombing one or two stages, after which they have
  /// to slowly gain it back.
  ///
  /// Dramatically reduces K for obvious bombs (rating changes by < -0.4K assuming no other
  /// modifiers), fading in from when a shooter's expected percentage is 75% to 100%.
  bool bombProtection;

  /// If rating change is greater than this value times base K, bomb protection will
  /// begin to fade in.
  double bombProtectionLowerThreshold;
  /// If rating change is greater than this value times K, bomb protection will be fully
  /// active.
  double bombProtectionUpperThreshold;
  /// If a shooter's expected percentage is greater than this value, bomb protection will
  /// begin to fade in.
  double bombProtectionMinimumExpectedPercent;
  /// If a shooter's expected percentage is greater than this value, bomb protection will be
  /// fully active.
  double bombProtectionMaximumExpectedPercent;
  /// The minimum K reduction percentage for bomb protection, when the shooter is at
  /// [bombProtectionMinimumExpectedPercent].
  double bombProtectionMinimumKReduction;
  /// The maximum K reduction percentage for bomb protection, when the shooter is at or above
  /// [bombProtectionMaximumExpectedPercent].
  double bombProtectionMaximumKReduction;


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
    this.errorAwareMaxValue = defaultScale,
    this.directionAwareK = false,
    this.directionAwareOnStreakMultiplier = defaultDirectionAwareOnStreakMultiplier,
    this.directionAwareOffStreakMultiplier = defaultDirectionAwareOffStreakMultiplier,
    this.streakLimit = defaultStreakLimit,
    this.bombProtection = false,
    this.bombProtectionMaximumKReduction = defaultBombProtectionMaxKReduction,
    this.bombProtectionMinimumKReduction = defaultBombProtectionMinKReduction,
    this.bombProtectionMaximumExpectedPercent = defaultBombProtectionMaximumPercent,
    this.bombProtectionMinimumExpectedPercent = defaultBombProtectionMinimumPercent,
    this.bombProtectionUpperThreshold = defaultBombProtectionUpperThreshold,
    this.bombProtectionLowerThreshold = defaultBombProtectionLowerThreshold,
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
    this.errorAwareMaxValue = defaultScale;
    this.directionAwareK = false;
    this.directionAwareOnStreakMultiplier = defaultDirectionAwareOnStreakMultiplier;
    this.directionAwareOffStreakMultiplier = defaultDirectionAwareOffStreakMultiplier;
    this.streakLimit = defaultStreakLimit;
    this.bombProtection = false;
    this.bombProtectionMaximumKReduction = defaultBombProtectionMaxKReduction;
    this.bombProtectionMinimumKReduction = defaultBombProtectionMinKReduction;
    this.bombProtectionMaximumExpectedPercent = defaultBombProtectionMaximumPercent;
    this.bombProtectionMinimumExpectedPercent = defaultBombProtectionMinimumPercent;
    this.bombProtectionUpperThreshold = defaultBombProtectionUpperThreshold;
    this.bombProtectionLowerThreshold = defaultBombProtectionLowerThreshold;
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
    json[_errorAwareMaxValueKey] = errorAwareMaxValue;
    json[_errorAwareLowerMultiplierKey] = errorAwareLowerMultiplier;
    json[_errorAwareMaxThresholdKey] = errorAwareMaxThreshold;
    json[_errorAwareMinThresholdKey] = errorAwareMinThreshold;
    json[_errorAwareUpperMultiplierKey] = errorAwareUpperMultiplier;
    json[_errorAwareZeroValueKey] = errorAwareZeroValue;
    json[_streakAwareKKey] = streakAwareK;
    json[_directionAwareKKey] = directionAwareK;
    json[_offStreakMultiplierKey] = directionAwareOffStreakMultiplier;
    json[_onStreakMultiplierKey] = directionAwareOnStreakMultiplier;
    json[_streakLimitKey] = streakLimit;
    json[_bombProtectionKey] = bombProtection;
    json[_bpMaxKKey] = bombProtectionMaximumKReduction;
    json[_bpMinKKey] = bombProtectionMinimumKReduction;
    json[_bpMaxPercentKey] = bombProtectionMaximumExpectedPercent;
    json[_bpMinPercentKey] = bombProtectionMinimumExpectedPercent;
    json[_bpUpperThreshKey] = bombProtectionUpperThreshold;
    json[_bpLowerThreshKey] = bombProtectionLowerThreshold;
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
    errorAwareMaxValue = (json[_errorAwareMaxValueKey] ?? defaultScale) as double;
    errorAwareZeroValue = (json[_errorAwareZeroValueKey] ?? defaultErrorAwareZeroValue) as double;
    errorAwareMinThreshold = (json[_errorAwareMinThresholdKey] ?? defaultErrorAwareMinThreshold) as double;
    errorAwareMaxThreshold = (json[_errorAwareMaxThresholdKey] ?? defaultErrorAwareMaxThreshold) as double;
    errorAwareLowerMultiplier = (json[_errorAwareLowerMultiplierKey] ?? defaultErrorAwareLowerMultiplier) as double;
    errorAwareUpperMultiplier = (json[_errorAwareUpperMultiplierKey] ?? defaultErrorAwareUpperMultiplier) as double;
    streakAwareK = (json[_streakAwareKKey] ?? false) as bool;
    directionAwareK = (json[_directionAwareKKey] ?? false) as bool;
    directionAwareOffStreakMultiplier = (json[_offStreakMultiplierKey] ?? defaultDirectionAwareOffStreakMultiplier) as double;
    directionAwareOnStreakMultiplier = (json[_onStreakMultiplierKey] ?? defaultDirectionAwareOnStreakMultiplier) as double;
    streakLimit = (json[_streakLimitKey] ?? defaultStreakLimit) as double;
    bombProtection = (json[_bombProtectionKey] ?? false) as bool;
    bombProtectionMaximumKReduction = (json[_bpMaxKKey] ?? defaultBombProtectionMaxKReduction) as double;
    bombProtectionMinimumKReduction = (json[_bpMinKKey] ?? defaultBombProtectionMinKReduction) as double;
    bombProtectionMaximumExpectedPercent = (json[_bpMaxPercentKey] ?? defaultBombProtectionMaximumPercent) as double;
    bombProtectionMinimumExpectedPercent = (json[_bpMinPercentKey] ?? defaultBombProtectionMinimumPercent) as double;
    bombProtectionUpperThreshold = (json[_bpUpperThreshKey] ?? defaultBombProtectionUpperThreshold) as double;
    bombProtectionLowerThreshold = (json[_bpLowerThreshKey] ?? defaultBombProtectionLowerThreshold) as double;
  }

  @override
  String toString() {
    var encoder = JsonEncoder.withIndent("  ");
    var json = <String, dynamic>{};
    encodeToJson(json);
    return encoder.convert(json);
  }
}