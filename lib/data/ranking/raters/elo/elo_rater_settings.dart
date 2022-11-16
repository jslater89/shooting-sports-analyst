import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';

const _kKey = "k";
const _probBaseKey = "probBase";
const _pctWeightKey = "pctWt";
const _scaleKey = "scale";
const _matchBlendKey = "matchBlend";
const _errorAwareKKey = "errK";

class EloSettings extends RaterSettings<EloSettings> {
  static const defaultK = 60.0;
  static const defaultProbabilityBase = 10.0;
  static const defaultPercentWeight = 0.4;
  static const defaultPlaceWeight = 0.6;
  static const defaultScale = 800.0;
  static const defaultMatchBlend = 0.3;

  double K;
  double probabilityBase;
  double percentWeight;
  double get placeWeight => 1 - percentWeight;
  double scale;
  double _matchBlend;

  bool errorAwareK;
  bool byStage;

  double get matchBlend => _matchBlend;
  set matchBlend(double m) => _matchBlend = m;

  double get stageBlend => 1 - _matchBlend;

  EloSettings({
    this.K = defaultK,
    this.percentWeight = defaultPercentWeight,
    this.probabilityBase = defaultProbabilityBase,
    this.scale = defaultScale,
    double matchBlend = defaultMatchBlend,
    this.errorAwareK = true,
    this.byStage = true,
  }) : _matchBlend = matchBlend;

  void restoreDefaults() {
    this.K = defaultK;
    this.percentWeight = defaultPercentWeight;
    this.probabilityBase = defaultProbabilityBase;
    this.scale = defaultScale;
    this._matchBlend = defaultMatchBlend;
    this.errorAwareK = true;
    this.byStage = true;
  }

  @override
  encodeToJson(Map<String, dynamic> json) {
    json[RatingProject.byStageKey] = byStage;
    json[_kKey] = K;
    json[_probBaseKey] = probabilityBase;
    json[_pctWeightKey] = percentWeight;
    json[_scaleKey] = scale;
    json[_matchBlendKey] = _matchBlend;
    json[_errorAwareKKey] = errorAwareK;
  }

  @override
  loadFromJson(Map<String, dynamic> json) {
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
  }
}