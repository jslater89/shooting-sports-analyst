/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'match_heat.g.dart';

@collection
class MatchHeat {
  Id get id => combineHashes(projectId.stableHash, matchSourceId.stableHash);

  @Index(composite: [CompositeIndex('matchSourceId')], unique: true)
  int projectId;
  String get matchSourceId => matchPointer.sourceIds.first;

  MatchPointer matchPointer;
  double topTenPercentAverageRating;
  double weightedTopTenPercentAverageRating;
  double medianRating;
  double weightedMedianRating;
  double classificationStrength;
  double weightedClassificationStrength;
  int ratedCompetitorCount;
  int unratedCompetitorCount;
  int rawCompetitorCount;
  int get usedCompetitorCount => ratedCompetitorCount + unratedCompetitorCount;

  MatchHeat({
    required this.projectId,
    required this.matchPointer,
    required this.topTenPercentAverageRating,
    required this.weightedTopTenPercentAverageRating,
    required this.medianRating,
    required this.weightedMedianRating,
    required this.classificationStrength,
    required this.weightedClassificationStrength,
    required this.ratedCompetitorCount,
    required this.unratedCompetitorCount,
    required this.rawCompetitorCount,
  });

  @override
  String toString() {
    return
"""MatchHeat(
  topTenPercentAverageRating: $topTenPercentAverageRating,
  medianRating: $medianRating,
  classificationStrength: $classificationStrength,
  ratedCompetitorCount: $ratedCompetitorCount,
  unratedCompetitorCount: $unratedCompetitorCount,
)""";
  }
}
