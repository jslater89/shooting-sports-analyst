/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/util.dart';

/// A registration-backed row for match-prep or prediction-game competitor lists.
///
/// [scoringGroup] is the division group the registration belongs to (the tab/market context).
/// [dbPrediction] / [algorithmPrediction] are attached when the [PredictionSet] has a matching
/// algorithm row. [displayRating] follows the same rating-source rules as [createPredictionSet].
class MatchPrepCompetitorRow {
  final MatchRegistration registration;
  final RatingGroup scoringGroup;
  final DbAlgorithmPrediction? dbPrediction;
  final AlgorithmPrediction? algorithmPrediction;
  final ShooterRating? displayRating;

  const MatchPrepCompetitorRow({
    required this.registration,
    required this.scoringGroup,
    this.dbPrediction,
    this.algorithmPrediction,
    this.displayRating,
  });

  bool get hasPrediction => dbPrediction != null || algorithmPrediction != null;

  /// Hydrated prediction when [algorithmPrediction] is set; otherwise hydrates [dbPrediction] if present.
  AlgorithmPrediction? hydratePrediction({RatingSystem? algorithm}) {
    if(algorithmPrediction != null) {
      return algorithmPrediction;
    }
    return dbPrediction?.hydrate(preloadedAlgorithm: algorithm);
  }
}

/// Member numbers used to match a registration to predictions (non-empty [MatchRegistration.shooterMemberNumbers]).
Set<String> registrationMemberNumbers(MatchRegistration registration) {
  return registration.shooterMemberNumbers.where((number) => number.isNotEmpty).toSet();
}

bool _memberNumbersOverlap(Set<String> registrationNumbers, Iterable<String> candidateNumbers) {
  for(var number in candidateNumbers) {
    if(number.isNotEmpty && registrationNumbers.contains(number)) {
      return true;
    }
  }
  return false;
}

/// Whether [prediction] belongs to [registration] and is scored on [scoringGroup].
bool predictionMatchesRegistration(
  DbAlgorithmPrediction prediction,
  MatchRegistration registration,
  RatingGroup scoringGroup,
) {
  if(prediction.effectiveScoringGroup != scoringGroup) {
    return false;
  }
  final registrationNumbers = registrationMemberNumbers(registration);
  if(registrationNumbers.isEmpty) {
    return false;
  }
  if(_memberNumbersOverlap(registrationNumbers, [prediction.memberNumber])) {
    return true;
  }
  final known = prediction.rating.value?.knownMemberNumbers;
  if(known != null && _memberNumbersOverlap(registrationNumbers, known)) {
    return true;
  }
  return false;
}

/// Whether [prediction] belongs to [registration] and is scored on [scoringGroup].
bool algorithmPredictionMatchesRegistration(
  AlgorithmPrediction prediction,
  MatchRegistration registration,
  RatingGroup scoringGroup,
) {
  if(prediction.effectiveScoringGroup != scoringGroup) {
    return false;
  }
  final registrationNumbers = registrationMemberNumbers(registration);
  if(registrationNumbers.isEmpty) {
    return false;
  }
  return _memberNumbersOverlap(registrationNumbers, prediction.shooter.knownMemberNumbers);
}

/// Resolves a [RatingGroup] from [uuid] or [name] / [uiLabel] within [project].
RatingGroup? resolveScoringGroup(DbRatingProject project, {String? uuid, String? name}) {
  if(uuid != null && uuid.isNotEmpty) {
    return project.groups.firstWhereOrNull((group) => group.uuid == uuid);
  }
  if(name != null && name.isNotEmpty) {
    return project.groups.firstWhereOrNull((group) => group.name == name || group.uiLabel == name);
  }
  return null;
}

/// Scoring groups to include when building competitor rows.
Iterable<RatingGroup> scoringGroupsForCompetitorRows({
  required DbRatingProject project,
  required MatchPrep matchPrep,
  PredictionSet? predictionSet,
  PredictionGame? game,
}) {
  var groups = project.groups.where((group) => !matchPrep.isRatingGroupExcluded(group));
  if(game != null && predictionSet != null) {
    groups = groups.where((group) => game.isRatingGroupAvailableForWagers(predictionSet, group));
  }
  return groups;
}

/// Counts competitors per scoring group from hydrated predictions (e.g. wager [checkValidity]).
Map<RatingGroup, int> competitorCountByScoringGroup(Iterable<AlgorithmPrediction> predictions) {
  final counts = <RatingGroup, int>{};
  for(var prediction in predictions) {
    counts.increment(prediction.effectiveScoringGroup);
  }
  return counts;
}

/// Counts competitors per scoring group from [DbAlgorithmPrediction] rows (links must be loaded).
Map<RatingGroup, int> competitorCountByScoringGroupFromDb(Iterable<DbAlgorithmPrediction> predictions) {
  final counts = <RatingGroup, int>{};
  for(var prediction in predictions) {
    counts.increment(prediction.effectiveScoringGroup);
  }
  return counts;
}

DbAlgorithmPrediction? findDbPredictionForRegistration(
  Iterable<DbAlgorithmPrediction> predictions,
  MatchRegistration registration,
  RatingGroup scoringGroup,
) {
  return predictions.firstWhereOrNull((prediction) =>
    predictionMatchesRegistration(prediction, registration, scoringGroup));
}

/// Display rating from [linkedRatings] or the prediction's linked DB rating (sync paths only).
ShooterRating? resolveDisplayRatingFromCache({
  required MatchPrep matchPrep,
  required DbRatingProject project,
  required MatchRegistration registration,
  required RatingGroup scoringGroup,
  Map<MatchRegistration, ShooterRating>? linkedRatings,
  DbAlgorithmPrediction? dbPrediction,
}) {
  final ratingSourceGroup = matchPrep.ratingSourceGroupFor(project, scoringGroup);
  if(linkedRatings?.containsKey(registration) ?? false) {
    final rating = linkedRatings![registration];
    if(rating != null && rating.group == ratingSourceGroup) {
      return rating;
    }
  }
  if(dbPrediction?.rating.value != null) {
    return project.wrapDbRatingSync(dbPrediction!.rating.value!);
  }
  return null;
}

/// Builds registration-backed rows for each scoring group, mirroring [createPredictionSet] registration
/// selection and optional [PredictionGame] wager exclusions.
///
/// [predictionSet.algorithmPredictions] must be loaded (call [PredictionSet.algorithmPredictions.load]
/// or [PredictionSet.algorithmPredictions.loadSync] first). For DB rating lookup on unrated rows, use
/// [buildCompetitorRowsWithRatingLookup].
List<MatchPrepCompetitorRow> buildCompetitorRows({
  required MatchPrep matchPrep,
  required FutureMatch futureMatch,
  required DbRatingProject project,
  required PredictionSet predictionSet,
  PredictionGame? game,
  Map<MatchRegistration, ShooterRating>? linkedRatings,
}) {
  final sport = project.sport;
  final predictions = predictionSet.algorithmPredictions.toList();
  final rows = <MatchPrepCompetitorRow>[];

  for(var scoringGroup in scoringGroupsForCompetitorRows(
    project: project,
    matchPrep: matchPrep,
    predictionSet: predictionSet,
    game: game,
  )) {
    final registrations = futureMatch.getRegistrationsFor(sport, group: scoringGroup);
    for(var registration in registrations) {
      final dbPrediction = findDbPredictionForRegistration(predictions, registration, scoringGroup);
      final displayRating = resolveDisplayRatingFromCache(
        matchPrep: matchPrep,
        project: project,
        registration: registration,
        scoringGroup: scoringGroup,
        linkedRatings: linkedRatings,
        dbPrediction: dbPrediction,
      );
      rows.add(MatchPrepCompetitorRow(
        registration: registration,
        scoringGroup: scoringGroup,
        dbPrediction: dbPrediction,
        displayRating: displayRating,
      ));
    }
  }

  return rows;
}

/// Like [buildCompetitorRows], but loads predictions and resolves [displayRating] via [AnalystDatabase]
/// when not available from [linkedRatings] or the prediction row.
Future<List<MatchPrepCompetitorRow>> buildCompetitorRowsWithRatingLookup({
  required AnalystDatabase db,
  required MatchPrep matchPrep,
  required FutureMatch futureMatch,
  required DbRatingProject project,
  required PredictionSet predictionSet,
  PredictionGame? game,
  Map<MatchRegistration, ShooterRating>? linkedRatings,
}) async {
  await predictionSet.algorithmPredictions.load();
  final baseRows = buildCompetitorRows(
    matchPrep: matchPrep,
    futureMatch: futureMatch,
    project: project,
    predictionSet: predictionSet,
    game: game,
    linkedRatings: linkedRatings,
  );
  final rows = <MatchPrepCompetitorRow>[];
  for(var row in baseRows) {
    if(row.displayRating != null) {
      rows.add(row);
      continue;
    }
    final displayRating = await lookupDisplayRating(
      db: db,
      matchPrep: matchPrep,
      project: project,
      registration: row.registration,
      scoringGroup: row.scoringGroup,
      linkedRatings: linkedRatings,
      dbPrediction: row.dbPrediction,
    );
    rows.add(MatchPrepCompetitorRow(
      registration: row.registration,
      scoringGroup: row.scoringGroup,
      dbPrediction: row.dbPrediction,
      displayRating: displayRating,
    ));
  }
  return rows;
}

/// Rating lookup using [MatchPrep.ratingSourceGroupFor], matching [createPredictionSet].
Future<ShooterRating?> lookupDisplayRating({
  required AnalystDatabase db,
  required MatchPrep matchPrep,
  required DbRatingProject project,
  required MatchRegistration registration,
  required RatingGroup scoringGroup,
  Map<MatchRegistration, ShooterRating>? linkedRatings,
  DbAlgorithmPrediction? dbPrediction,
}) async {
  final cached = resolveDisplayRatingFromCache(
    matchPrep: matchPrep,
    project: project,
    registration: registration,
    scoringGroup: scoringGroup,
    linkedRatings: linkedRatings,
    dbPrediction: dbPrediction,
  );
  if(cached != null) {
    return cached;
  }
  final ratingSourceGroup = matchPrep.ratingSourceGroupFor(project, scoringGroup);
  for(var memberNumber in registration.shooterMemberNumbers) {
    final rating = await db.maybeKnownShooter(
      project: project,
      group: ratingSourceGroup,
      memberNumber: memberNumber,
      useCache: true,
    );
    if(rating != null) {
      return project.wrapDbRatingSync(rating);
    }
  }
  return null;
}
