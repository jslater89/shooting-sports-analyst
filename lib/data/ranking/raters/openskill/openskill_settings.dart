import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';

const _betaKey = "osBeta";
const _tauKey = "osTau";
const _byStageKey = "osByStage";

class OpenskillSettings extends RaterSettings<OpenskillSettings> {
  /// mu is the center of a team's performance distribution.
  static const defaultMu = 25.0;

  /// sigma is the standard deviation of a team's performance distribution,
  /// and is used for determining rating variability along with beta.
  static const defaultSigma = 25/3;

  /// beta is the natural variability of ratings: sigma may eventually
  /// approach 0, but beta means ratings will always be able to move.
  static const defaultBeta = 25/3/2; // half of defaultSigma

  /// tau is an amount to add to sigma at every rating event, which
  /// allows fluidity in ratings as player skill changes.
  static const defaultTau = 25/3/30;

  /// epsilon is a minimum sigma to avoid math hinkiness.
  static const defaultEpsilon = 0.0001;

  double beta;
  double tau;

  bool byStage;

  OpenskillSettings({
    this.beta = defaultBeta,
    this.tau = defaultTau,
    this.byStage = true,
  });

  void restoreDefaults() {
    beta = defaultBeta;
    tau = defaultTau;
    byStage = true;
  }

  @override
  encodeToJson(Map<String, dynamic> json) {
    json[_betaKey] = beta;
    json[_tauKey] = tau;
    json[_byStageKey] = byStage;
  }

  @override
  loadFromJson(Map<String, dynamic> json) {
    beta = (json[_betaKey] ?? defaultBeta) as double;
    tau = (json[_tauKey] ?? defaultTau) as double;
    byStage = (json[_byStageKey] ?? true) as bool;
  }

  String? validate() {
    return null;
  }

}