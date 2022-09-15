import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';

const _matchesToCountKey = "ptsMatchesCount";
const _pointsModeKey = "ptsMode";
const _decayingPointsStartKey = "ptsDecayStart";
const _decayingPointsFactorKey = "ptsDecayFtr";
const _participationBonusKey = "ptsParticipationBonus";

class PointsSettings extends RaterSettings<PointsSettings> {
  final bool byStage = false;

  /// About one match a month seems fair.
  static const defaultMatchesToCount = 6;
  static const defaultPointsMode = PointsMode.percentageFinish;
  static const defaultDecayingPointsStart = 30.0;
  static const defaultDecayingPointsFactor = 0.8;
  static const defaultParticipationBonus = 0.0;

  /// How many matches to count.
  ///
  /// If positive, use [matchesToCount] best matches.
  ///
  /// If 0, all matches count.
  ///
  /// If negative, use abs([matchesToCount]) as a percentage: -50 is half.
  int matchesToCount;

  /// The points mode to use.
  PointsMode mode;

  /// The percentage of first place to award all participants in a match.
  double participationBonus;

  double decayingPointsStart;
  double decayingPointsFactor;

  PointsSettings({
    this.matchesToCount = defaultMatchesToCount,
    this.mode = defaultPointsMode,
    this.decayingPointsFactor = defaultDecayingPointsFactor,
    this.decayingPointsStart = defaultDecayingPointsStart,
    this.participationBonus = defaultParticipationBonus,
  });

  @override
  encodeToJson(Map<String, dynamic> json) {
    json[_matchesToCountKey] = matchesToCount;
    json[_pointsModeKey] = mode.name;
    json[_participationBonusKey] = participationBonus;
    json[_decayingPointsStartKey] = decayingPointsStart;
    json[_decayingPointsFactorKey] = decayingPointsFactor;
  }

  @override
  loadFromJson(Map<String, dynamic> json) {
    matchesToCount = (json[_matchesToCountKey] ?? defaultMatchesToCount) as int;
    mode = _parsePointsMode(json[_pointsModeKey]);
    participationBonus = (json[_participationBonusKey] ?? defaultParticipationBonus) as double;
    decayingPointsStart = (json[_decayingPointsStartKey] ?? defaultDecayingPointsStart) as double;
    decayingPointsFactor = (json[_decayingPointsFactorKey] ?? defaultDecayingPointsFactor) as double;
  }

  _parsePointsMode(String? name) {
    if(name == PointsMode.f1.name) return PointsMode.f1;
    else if(name == PointsMode.inversePlace.name) return PointsMode.inversePlace;
    else if(name == PointsMode.percentageFinish.name) return PointsMode.percentageFinish;
    else if(name == PointsMode.decayingPoints.name) return PointsMode.decayingPoints;
    else return PointsMode.percentageFinish;
  }

  void restoreDefaults() {
    this.matchesToCount = defaultMatchesToCount;
    this.mode = defaultPointsMode;
    this.decayingPointsFactor = defaultDecayingPointsFactor;
    this.decayingPointsStart = defaultDecayingPointsStart;
    this.participationBonus = defaultParticipationBonus;
  }
}

enum PointsMode {
  /// F1-style points: 25, 18, 15, 12, 10, 8, 6, 4, 2, 1.
  f1,

  /// (participants - (place - 1))
  inversePlace,

  /// percent finish in the match
  percentageFinish,

  /// P * K^(place)
  decayingPoints
}