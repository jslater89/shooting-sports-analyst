/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/entity_changes.dart';
import 'package:shooting_sports_analyst/data/database/extensions/entity_changes.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("MatchPrepDatabase");

extension MatchPrepDatabase on AnalystDatabase {
  /// Get all match preps.
  Future<List<MatchPrep>> getMatchPreps({DbRatingProject? singleProject}) async {
    if(singleProject != null) {
      return isar.matchPreps.filter().projectIdEqualTo(singleProject.id.stableHash).sortByMatchDateDesc().findAll();
    }
    else {
      return isar.matchPreps.where().sortByMatchDateDesc().findAll();
    }
  }

  /// Get all match preps synchronously.
  List<MatchPrep> getMatchPrepsSync({DbRatingProject? singleProject}) {
    if(singleProject != null) {
      return isar.matchPreps.filter().projectIdEqualTo(singleProject.id.stableHash).sortByMatchDateDesc().findAllSync();
    }
    else {
      return isar.matchPreps.where().sortByMatchDateDesc().findAllSync();
    }
  }

  Future<List<MatchPrep>> queryMatchPreps({
    String? nameFilter,
    DateTime? after,
    DateTime? before,
    int limit = 10,
    bool hasPredictionsOnly = false,
    List<int>? excludeIds,
    DbRatingProject? project,
  }) {
    var queryBase = isar.matchPreps.where();
    var filteredQuery = queryBase.filter();
    QueryBuilder<MatchPrep, MatchPrep, QAfterFilterCondition>? afterQuery;
    if(project != null) {
      afterQuery = filteredQuery.projectIdEqualTo(project.id.stableHash);
    }
    if(nameFilter != null) {
      if(afterQuery == null) {
        afterQuery = filteredQuery.futureMatch((m) => m.eventNameContains(nameFilter, caseSensitive: false));
      }
      else {
        afterQuery = afterQuery.futureMatch((m) => m.eventNameContains(nameFilter, caseSensitive: false));
      }
    }
    if(after != null) {
      if(afterQuery == null) {
        afterQuery = filteredQuery.futureMatch((m) => m.dateGreaterThan(after));
      }
      else {
        afterQuery = afterQuery.futureMatch((m) => m.dateGreaterThan(after));
      }
    }
    if(before != null) {
      if(afterQuery == null) {
        afterQuery = filteredQuery.futureMatch((m) => m.dateLessThan(before));
      }
      else {
        afterQuery = afterQuery.futureMatch((m) => m.dateLessThan(before));
      }
    }
    if(hasPredictionsOnly) {
      if(afterQuery == null) {
        afterQuery = filteredQuery.predictionSetsIsNotEmpty();
      }
      else {
        afterQuery = afterQuery.predictionSetsIsNotEmpty();
      }
    }
    if(excludeIds != null) {
      if(afterQuery == null) {
        afterQuery = filteredQuery.allOf(excludeIds, (q, id) => q.not().idEqualTo(id));
      }
      else {
        afterQuery = afterQuery.allOf(excludeIds, (q, id) => q.not().idEqualTo(id));
      }
    }

    if(afterQuery != null) {
      return afterQuery.sortByMatchDateDesc().limit(limit).findAll();
    }
    else {
      return queryBase.sortByMatchDateDesc().limit(limit).findAll();
    }
  }

  /// Get a match prep for a specific project and match ID, in both cases the database ID
  /// rather than any other ID.
  Future<MatchPrep?> getMatchPrepForProjectAndMatchIds(int projectId, String matchId) async {
    var syntheticId = MatchPrep.synthesizeIdFromIds(projectId, matchId);
    return isar.matchPreps.get(syntheticId);
  }

  /// Get a match prep for a specific project and match ID, in both cases the database ID
  /// rather than any other ID, synchronously.
  MatchPrep? getMatchPrepForProjectAndMatchIdsSync(int projectId, String matchId) {
    var syntheticId = MatchPrep.synthesizeIdFromIds(projectId, matchId);
    return isar.matchPreps.getSync(syntheticId);
  }

  /// Get a match prep for a specific project and match, if one exists.
  Future<MatchPrep?> getMatchPrepForProjectAndMatch(DbRatingProject project, FutureMatch match) async {
    return getMatchPrepForProjectAndMatchIds(project.id, match.matchId);
  }

  /// Get a match prep for a specific project and match, if one exists, synchronously.S
  MatchPrep? getMatchPrepForProjectAndMatchSync(DbRatingProject project, FutureMatch match) {
    return getMatchPrepForProjectAndMatchIdsSync(project.id, match.matchId);
  }

  /// Save a match prep to the database.
  Future<MatchPrep> saveMatchPrep(MatchPrep matchPrep, {bool saveOwnLinks = true, bool savePredictionSetLinks = true}) async {
    if(!matchPrep.futureMatch.isLoaded) {
      // Need to load to get matchDate
      await matchPrep.futureMatch.load();
    }
    await isar.writeTxn(() async {
      await isar.matchPreps.put(matchPrep);
      if(saveOwnLinks) {
        await matchPrep.futureMatch.save();
        await matchPrep.ratingProject.save();
        await matchPrep.predictionSets.save();
      }
    });
    if(savePredictionSetLinks) {
      for(var predictionSet in matchPrep.predictionSets) {
        await predictionSet.algorithmPredictions.save();
      }
    }

    await notifyEntityChange(EntityType.matchPrep, matchPrep.id);
    return matchPrep;
  }

  /// Save a match prep to the database synchronously.
  MatchPrep saveMatchPrepSync(MatchPrep matchPrep) {
    isar.writeTxnSync(() {
      // sync recursively saves
      isar.matchPreps.putSync(matchPrep);
    });
    notifyEntityChangeSync(EntityType.matchPrep, matchPrep.id);
    return matchPrep;
  }

  /// Save a prediction set to the database.
  Future<PredictionSet> savePredictionSet(PredictionSet predictionSet, {bool savePredictions = true}) async {
    var predictions = savePredictions ? predictionSet.algorithmPredictions.toList() : <DbAlgorithmPrediction>[];
    await isar.writeTxn(() async {
      await isar.predictionSets.put(predictionSet);
      if(savePredictions) {
        await isar.dbAlgorithmPredictions.putAll(predictions);
        for(var prediction in predictions) {
          await prediction.saveLinks();
        }
        await predictionSet.algorithmPredictions.save();
      }
    });
    await notifyEntityChange(EntityType.matchPrep, predictionSet.matchPrepId);
    return predictionSet;
  }

  /// Save a prediction set to the database synchronously, along with its linked predictions.
  void savePredictionSetSync(PredictionSet predictionSet) {
    isar.writeTxnSync(() {
      isar.predictionSets.putSync(predictionSet);
    });
    notifyEntityChangeSync(EntityType.matchPrep, predictionSet.matchPrepId);
  }

  Future<Result<void, ResultErr>> deleteMatchPrep(MatchPrep matchPrep, {bool force = false}) async {
    if(!force) {
      // Don't delete match preps whose predictions are being used in prediction games.
      var predictionGames = await getPredictionGamesForMatchPrep(matchPrep);
      if(predictionGames.isNotEmpty) {
        return Result.err(StringError("Match prep used in prediction games"));
      }
    }

    await isar.writeTxn(() async {
      await matchPrep.predictionSets.filter().deleteAll();
      await isar.matchPreps.delete(matchPrep.id);
    });
    await notifyEntityChange(EntityType.matchPrep, matchPrep.id);
    return Result.ok(null);
  }

  Future<Result<void, ResultErr>> deletePredictionSet(PredictionSet predictionSet, {bool force = false}) async {
    if(!force && await hasWagersForPredictionSet(predictionSet)) {
      return Result.err(StringError("Prediction set used in prediction game wagers"));
    }

    await isar.writeTxn(() async {
      await predictionSet.algorithmPredictions.filter().deleteAll();
      await isar.predictionSets.where().idEqualTo(predictionSet.id).deleteAll();
    });
    await notifyEntityChange(EntityType.matchPrep, predictionSet.matchPrepId);
    return Result.ok(null);
  }

  Result<void, ResultErr> deletePredictionSetSync(PredictionSet predictionSet, {bool force = false}) {
    if(!force && hasWagersForPredictionSetSync(predictionSet)) {
      return Result.err(StringError("Prediction set used in prediction game wagers"));
    }

    isar.writeTxnSync(() {
      predictionSet.algorithmPredictions.filter().deleteAllSync();
      isar.predictionSets.where().idEqualTo(predictionSet.id).deleteAllSync();
    });
    notifyEntityChangeSync(EntityType.matchPrep, predictionSet.matchPrepId);
    return Result.ok(null);
  }

  Future<void> saveAlgorithmPrediction(DbAlgorithmPrediction prediction, {bool saveLinks = true}) async {
    await isar.writeTxn(() async {
      await isar.dbAlgorithmPredictions.put(prediction);
      if(saveLinks) {
        await prediction.rating.save();
        await prediction.project.save();
        await prediction.group.save();
        await prediction.predictionSet.save();
        await prediction.scoringGroup.save();
      }
    });
  }

  Future<void> saveAlgorithmPredictions(List<DbAlgorithmPrediction> predictions, {bool saveLinks = true}) async {
    await isar.writeTxn(() async {
      await isar.dbAlgorithmPredictions.putAll(predictions);
      if(saveLinks) {
        for(var prediction in predictions) {
          await prediction.saveLinks();
        }
      }
    });
  }

  /// Create a prediction set for a given match prep.
  ///
  /// If not provided, [name] defaults to the current date and time in YYYY-MM-DD HH:MM format.
  ///
  /// If not provided, [seed] defaults to the Unix timestamp of the match date (i.e., stable for a
  /// given FutureMatch).
  ///
  /// If [prematchedRegistrations] is provided, this method will look up ratings for the given registrations
  /// instead of making database lookups.
  Future<PredictionSet> createPredictionSet({
    required MatchPrep matchPrep,
    String? name,
    int? seed,
    Map<MatchRegistration, ShooterRating>? prematchedRegistrations,
  }) async {
    final prep = matchPrep;
    final ratingProject = prep.ratingProject.value!;
    final futureMatch = prep.futureMatch.value!;

    // predict for all rating groups
    Map<RatingGroup, List<AlgorithmPrediction>> predictions = {};
    seed ??= futureMatch.date.millisecondsSinceEpoch;
    final groups = ratingProject.groups.where((group) => !prep.isRatingGroupExcluded(group)).toList();
    for(var scoringGroup in groups) {
      final ratingSourceGroup = prep.ratingSourceGroupFor(ratingProject, scoringGroup);
      final hasGroupOverride = ratingSourceGroup != scoringGroup;

      final registrations = futureMatch.getRegistrationsFor(ratingProject.sport, group: scoringGroup);

      // TODO: deduplicate by rating identity, although we won't generally have multiple registrations per shooter/division.
      List<ShooterRating> ratings = [];
      for(var r in registrations) {
        // MatchRegistration implements database equality, so we can use query results to look up ratings
        // in the provided map.
        bool foundCachedRating = false;
        if(prematchedRegistrations?.containsKey(r) ?? false) {
          final rating = prematchedRegistrations![r];
          if(rating != null && rating.group == ratingSourceGroup) {
            ratings.add(prematchedRegistrations[r]!);
            foundCachedRating = true;
          }
        }
        if(!foundCachedRating) {
          DbShooterRating? rating;
          for(var memberNumber in r.shooterMemberNumbers) {
            rating = await maybeKnownShooter(project: ratingProject, group: ratingSourceGroup, memberNumber: memberNumber, useCache: true);
            if(rating != null) {
              break;
            }
          }
          if(rating == null) {
            continue;
          }
          ratings.add(ratingProject.wrapDbRatingSync(rating));
        }
      }

      var groupPredictions = ratingProject.settings.algorithm.predict(ratings, seed: seed);
      if(hasGroupOverride) {
        for(var prediction in groupPredictions) {
          prediction.scoringGroup = scoringGroup;
        }
      }
      predictions[scoringGroup] = groupPredictions;
    }

    // create and save prediction set
    var predictionSet = PredictionSet.create(
      matchPrep: prep,
      name: name ?? programmerYmdHmFormat.format(DateTime.now()),
      excludedRatingGroupUuids: prep.excludedRatingGroupUuids,
      predictionSourceOverrides: prep.dbRatingGroupPredictionSourceOverrides.where((o) => o.ratingGroupUuid != o.scoringGroupUuid).toList(),
    );
    predictionSet = await savePredictionSet(predictionSet, savePredictions: false);

    // dehydrate and save algorithm predictions
    List<DbAlgorithmPrediction> dbPredictions = [];
    for(var group in predictions.keys) {
      for(var prediction in predictions[group]!) {
        try {
          var dbPrediction = DbAlgorithmPrediction.fromHydrated(ratingProject, predictionSet, prediction);
          dbPredictions.add(dbPrediction);
        } catch(e) {
          _log.e("Error dehydrating prediction for ${prediction.shooter.name}", error: e);
        }
      }
    }

    List<Future> saveFutures = [];
    for(var prediction in dbPredictions) {
      saveFutures.add(saveAlgorithmPrediction(prediction, saveLinks: true));
    }
    await Future.wait(saveFutures);

    // add to prep and save prediction set link, but not the predictions (saved above)
    prep.predictionSets.add(predictionSet);
    await saveMatchPrep(prep, savePredictionSetLinks: false);

    _log.i("Created prediction set ${predictionSet.name} for match ${prep.futureMatch.value!.eventName} with ${dbPredictions.length} predictions for ${predictions.keys.map((k) => k.name).join(", ")}");

    return predictionSet;
  }
}
