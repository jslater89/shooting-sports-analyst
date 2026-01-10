/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'match_prep.g.dart';

/// A MatchPrep is a link between a [FutureMatch] and a [DbRatingProject],
/// which is used as a storage location for predictions, shooter information,
/// and other before-the-fact analysis for a particular match.
@collection
class MatchPrep {
  Id get id => synthesizeIdFromIds(projectId, matchId);
  int matchId;
  int projectId;

  /// The match under analysis.
  final futureMatch = IsarLink<FutureMatch>();

  /// The date of the match being analyzed.
  @Index()
  DateTime get matchDate => futureMatch.value!.date;

  /// The last time the match prep was viewed.
  @Index()
  DateTime lastViewed = practicalShootingZeroDate;

  /// The rating project used as context for the analysis.
  final ratingProject = IsarLink<DbRatingProject>();

  /// Prediction sets for this match prep.
  final predictionSets = IsarLinks<PredictionSet>();

  PredictionSet? latestPredictionSet() {
    return predictionSets.filter().sortByCreatedDesc().findFirstSync();
  }

  /// The games that use this match prep.
  final games = IsarLinks<PredictionGame>();

  MatchPrep({
    required this.matchId,
    required this.projectId,
  });

  MatchPrep.from({
    required FutureMatch futureMatch,
    required DbRatingProject project,
  }) : matchId = futureMatch.matchId.stableHash,
    projectId = project.id.stableHash {

    this.futureMatch.value = futureMatch;
    this.ratingProject.value = project;
  }

  static int synthesizeIdFromIds(int projectId, int matchId) {
    return combineHashes(projectId, matchId);
  }

  static int synthesizeIdFromEntities(DbRatingProject project, FutureMatch match) {
    return synthesizeIdFromIds(project.id, match.id);
  }
}
