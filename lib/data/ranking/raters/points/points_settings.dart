/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';

const _matchesToCountKey = "ptsMatchesCount";
const _pointsModeKey = "ptsMode";
const _decayingPointsStartKey = "ptsDecayStart";
const _decayingPointsFactorKey = "ptsDecayFtr";
const _participationBonusKey = "ptsParticipationBonus";
const _stagesRequiredPerMatchKey = "ptsStagesRequiredPerMatch";


class PointsSettings extends RaterSettings {
  final bool byStage = false;

  /// About one match a month seems fair.
  static const defaultMatchesToCount = 6;
  static const defaultPointsMode = PointsMode.percentageFinish;
  static const defaultDecayingPointsStart = 30.0;
  static const defaultDecayingPointsFactor = 0.8;
  static const defaultParticipationBonus = 1.0;
  static const defaultStagesRequiredPerMatch = 0;

  static const noStagesRequired = 0;
  static const allStagesRequired = -1;

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

  /// The number of stages required for a match entry to count as a non-DNF.
  ///
  /// If [allStagesRequired], a competitor must enter a score on all stages.
  ///
  /// If [noStagesRequired], all match entries will count regardless of
  /// whether they completed any stages at all.
  int stagesRequiredPerMatch;

  double decayingPointsStart;
  double decayingPointsFactor;

  PointsSettings({
    this.matchesToCount = defaultMatchesToCount,
    this.mode = defaultPointsMode,
    this.decayingPointsFactor = defaultDecayingPointsFactor,
    this.decayingPointsStart = defaultDecayingPointsStart,
    this.participationBonus = defaultParticipationBonus,
    this.stagesRequiredPerMatch = defaultStagesRequiredPerMatch,
  });

  @override
  encodeToJson(Map<String, dynamic> json) {
    json[_matchesToCountKey] = matchesToCount;
    json[_pointsModeKey] = mode.name;
    json[_participationBonusKey] = participationBonus;
    json[_decayingPointsStartKey] = decayingPointsStart;
    json[_decayingPointsFactorKey] = decayingPointsFactor;
    json[_stagesRequiredPerMatchKey] = stagesRequiredPerMatch;
  }

  @override
  loadFromJson(Map<String, dynamic> json) {
    matchesToCount = (json[_matchesToCountKey] ?? defaultMatchesToCount) as int;
    mode = _parsePointsMode(json[_pointsModeKey]);
    participationBonus = (json[_participationBonusKey] ?? defaultParticipationBonus) as double;
    decayingPointsStart = (json[_decayingPointsStartKey] ?? defaultDecayingPointsStart) as double;
    decayingPointsFactor = (json[_decayingPointsFactorKey] ?? defaultDecayingPointsFactor) as double;
    stagesRequiredPerMatch = (json[_stagesRequiredPerMatchKey] ?? defaultStagesRequiredPerMatch) as int;
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

extension PointsModeUtils on PointsMode {
  String get uiLabel {
    switch(this) {
      case PointsMode.f1:
        return "F1-style";
      case PointsMode.inversePlace:
        return "Inverse place";
      case PointsMode.percentageFinish:
        return "Percent finish";
      case PointsMode.decayingPoints:
        return "Decaying points";
    }
  }

  String get tooltip {
    switch(this) {
      case PointsMode.f1:
        return "Points to the top 10 finishers: 25, 18, 15, 12, 10, 8, 6, 4, 2, 1.";
      case PointsMode.inversePlace:
        return "N points to the winner, where N is the number of shooters; minus 1 for each place below 1st.";
      case PointsMode.percentageFinish:
        return "Points equal to each shooter's percentage finish.";
      case PointsMode.decayingPoints:
        return "Exponentially decaying points, starting at (decay start) and multiplied by (decay factor)^N, where N is place.";
    }
  }
}
