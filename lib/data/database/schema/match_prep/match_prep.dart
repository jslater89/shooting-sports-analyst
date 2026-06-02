/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
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
  Id get id => synthesizeIdFromHashedIds(projectId, matchId);
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

  /// Overrides for prediction source groups: a map of scoring group
  /// UUIDs to rating group UUIDs. The scoring group UUID is the group
  /// used for registrations and scoring, and the rating group UUID is the
  /// group used for ratings/predictions. This is intended for the USPSA
  /// LO/CO case, where LO and CO are close enough so that distinguishing
  /// between them in ratings/prediction terms is not meaningful, but they
  /// remain separately scored.
  @ignore
  Map<String, String> get ratingGroupPredictionSourceOverrides => {
    for(final override in dbRatingGroupPredictionSourceOverrides)
      override.scoringGroupUuid: override.ratingGroupUuid,
  };

  set ratingGroupPredictionSourceOverrides(Map<String, String> value) {
    dbRatingGroupPredictionSourceOverrides = value.entries.map((e) =>
      RatingGroupPredictionSourceOverride(
        scoringGroupUuid: e.key,
        ratingGroupUuid: e.value,
      )
    ).toList();
  }

  /// Returns the rating source group for a given scoring group.
  /// If no override is found, or if the group corresponding to the override does not exist,
  /// returns the scoring group itself.
  RatingGroup ratingSourceGroupFor(DbRatingProject project, RatingGroup scoringGroup) {
    final overrideUuid = ratingGroupPredictionSourceOverrides[scoringGroup.uuid];
    if(overrideUuid == null) {
      return scoringGroup;
    }
    final nullableGroup = project.groups.firstWhereOrNull((group) => group.uuid == overrideUuid);
    return nullableGroup ?? scoringGroup;
  }

  /// DB representation for [ratingGroupPredictionSourceOverrides]. Do not modify directly.
  List<RatingGroupPredictionSourceOverride> dbRatingGroupPredictionSourceOverrides = [];

  /// A list of rating group UUIDs that are excluded from predictions.
  List<String> excludedRatingGroupUuids = [];

  /// Whether the given rating group is excluded from predictions.
  bool isRatingGroupExcluded(RatingGroup group) {
    return excludedRatingGroupUuids.contains(group.uuid);
  }

  @ignore
  List<PredictionSet> get sortedPredictionSets => predictionSets.filter().sortByCreatedDesc().findAllSync();

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

  static int synthesizeIdFromIds(int projectId, String matchId) {
    return synthesizeIdFromHashedIds(projectId.stableHash, matchId.stableHash);
  }

  static int synthesizeIdFromHashedIds(int projectHash, int matchHash) {
    return combineHashes64(projectHash, matchHash);
  }

  static int synthesizeIdFromEntities(DbRatingProject project, FutureMatch match) {
    return synthesizeIdFromIds(project.id, match.matchId);
  }
}

@embedded
class RatingGroupPredictionSourceOverride {
  /// The UUID of the group whose registrations determine what competitors are
  /// included/scored in this prediction.
  String scoringGroupUuid;

  /// The UUID of the group whose ratings are used to generate this prediction.
  String ratingGroupUuid;

  RatingGroupPredictionSourceOverride({
    this.scoringGroupUuid = "",
    this.ratingGroupUuid = "",
  });

  RatingGroupPredictionSourceOverride.from({
    required RatingGroup scoringGroup,
    required RatingGroup ratingGroup,
  }) :
    scoringGroupUuid = scoringGroup.uuid,
    ratingGroupUuid = ratingGroup.uuid;

  operator ==(Object other) {
    if(!(other is RatingGroupPredictionSourceOverride)) return false;
    return scoringGroupUuid == other.scoringGroupUuid && ratingGroupUuid == other.ratingGroupUuid;
  }

  int get hashCode => combineHashes64(scoringGroupUuid.stableHash, ratingGroupUuid.stableHash);
}