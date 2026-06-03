/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// USPSA-specific prediction settings stored on [MatchPrep].
class MatchPrepUspsaPredictionSettings {
  MatchPrepUspsaPredictionSettings._();

  static const loCoGroupUuid = "uspsa-lo-co";
  static const loGroupUuid = "uspsa-limited-optics";
  static const coGroupUuid = "uspsa-carryoptics";

  static bool isSupportedSport(Sport sport) {
    return sport.type == SportType.uspsa;
  }

  /// True when overrides are exactly LO → LO/CO and CO → LO/CO.
  static bool combinesLoCo(MatchPrep prep) {
    final overrides = prep.ratingGroupPredictionSourceOverrides;
    return overrides.length == 2
      && overrides[loGroupUuid] == loCoGroupUuid
      && overrides[coGroupUuid] == loCoGroupUuid;
  }

  /// True when the combined LO/CO rating group is not excluded from predictions.
  ///
  /// When the prep has no exclusion entries and no LO/CO combine override, defaults to false.
  static bool generatesLoCoPredictions(MatchPrep prep) {
    if(prep.excludedRatingGroupUuids.contains(loCoGroupUuid)) {
      return false;
    }
    if(prep.excludedRatingGroupUuids.isEmpty && !combinesLoCo(prep)) {
      return false;
    }
    return true;
  }

  static void applyTo(MatchPrep prep, {
    required bool combineLoCo,
    required bool generateLoCoPredictions,
  }) {
    final overrides = Map<String, String>.from(prep.ratingGroupPredictionSourceOverrides);
    overrides.remove(loGroupUuid);
    overrides.remove(coGroupUuid);
    if(combineLoCo) {
      overrides[loGroupUuid] = loCoGroupUuid;
      overrides[coGroupUuid] = loCoGroupUuid;
    }
    prep.ratingGroupPredictionSourceOverrides = overrides;

    final excluded = [...prep.excludedRatingGroupUuids];
    if(generateLoCoPredictions) {
      excluded.remove(loCoGroupUuid);
    }
    else if(!excluded.contains(loCoGroupUuid)) {
      excluded.add(loCoGroupUuid);
    }
    prep.excludedRatingGroupUuids = excluded;
  }
}
