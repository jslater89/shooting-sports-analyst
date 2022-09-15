import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';

class EloSettings extends RaterSettings<EloSettings> {
  static const defaultK = 60.0;
  static const defaultPercentWeight = 0.4;
  static const defaultPlaceWeight = 0.6;
  static const defaultScale = 800.0;
  static const defaultMatchBlend = 0.3;

  double K;
  double percentWeight;
  double get placeWeight => 1 - percentWeight;
  double scale;
  double _matchBlend;

  bool errorAwareK;
  bool byStage;

  double get matchBlend => _matchBlend;
  set matchBlend(double m) => _matchBlend = m;

  double get stageBlend => stageBlend;

  EloSettings({
    this.K = defaultK,
    this.percentWeight = defaultPercentWeight,
    this.scale = defaultScale,
    double matchBlend = defaultMatchBlend,
    this.errorAwareK = true,
    this.byStage = true,
  }) : _matchBlend = matchBlend;

  void restoreDefaults() {

  }

  @override
  encodeToJson(Map<String, dynamic> json) {
    // TODO: implement encodeToJson
    throw UnimplementedError();
  }

  @override
  loadFromJson(Map<String, dynamic> json) {
    // TODO: implement fromJson
    throw UnimplementedError();
  }

}