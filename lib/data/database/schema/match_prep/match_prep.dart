/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'match_prep.g.dart';

/// A MatchPrep is a link between a [FutureMatch] and a [DbRatingProject],
/// which is used as a storage location for predictions, shooter information,
/// and other before-the-fact analysis for a particular match.
@collection
class MatchPrep {
  Id get id => combineHashes(matchId.stableHash, projectId.stableHash);
  int matchId = -1;
  int projectId = -1;

  /// The match under analysis.
  final futureMatch = IsarLink<FutureMatch>();

  /// The rating project used as context for the analysis.
  final ratingProject = IsarLink<DbRatingProject>();

  /// Predictions from [ratingProject]'s algorithm for [futureMatch].
  final algorithmPredictions = IsarLinks<DbAlgorithmPrediction>();

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
}
