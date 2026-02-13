/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/entity_changes.dart';
import 'package:shooting_sports_analyst/data/database/extensions/entity_changes.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

extension MatchPrepDatabase on AnalystDatabase {
  /// Get all match preps.
  Future<List<MatchPrep>> getMatchPreps() async {
    return isar.matchPreps.where().sortByMatchDateDesc().findAll();
  }

  /// Get all match preps synchronously.
  List<MatchPrep> getMatchPrepsSync() {
    return isar.matchPreps.where().sortByMatchDateDesc().findAllSync();
  }

  Future<List<MatchPrep>> queryMatchPreps({
    String? nameFilter,
    DateTime? after,
    DateTime? before,
    int limit = 10,
    bool hasPredictionsOnly = false,
    List<int>? excludeIds,
  }) {
    var queryBase = isar.matchPreps.where();
    var filteredQuery = queryBase.filter();
    QueryBuilder<MatchPrep, MatchPrep, QAfterFilterCondition>? afterQuery;
    if(nameFilter != null) {
      afterQuery = filteredQuery.futureMatch((m) => m.eventNameContains(nameFilter, caseSensitive: false));
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

  /// Get a match prep for a specific project and match, if one exists, synchronously.
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

    notifyEntityChange(EntityType.matchPrep, matchPrep.id);
    return matchPrep;
  }

  /// Save a match prep to the database synchronously.
  MatchPrep saveMatchPrepSync(MatchPrep matchPrep) {
    isar.writeTxnSync(() {
      // sync recursively saves
      isar.matchPreps.putSync(matchPrep);
    });
    notifyEntityChange(EntityType.matchPrep, matchPrep.id);
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
    return predictionSet;
  }

  /// Save a prediction set to the database synchronously, along with its linked predictions.
  void savePredictionSetSync(PredictionSet predictionSet) {
    isar.writeTxnSync(() {
      isar.predictionSets.putSync(predictionSet);
    });
  }

  Future<void> deletePredictionSet(PredictionSet predictionSet) async {
    await isar.writeTxn(() async {
      await predictionSet.algorithmPredictions.filter().deleteAll();
      await isar.predictionSets.where().idEqualTo(predictionSet.id).deleteAll();
    });
  }

  void deletePredictionSetSync(PredictionSet predictionSet) {
    isar.writeTxnSync(() {
      predictionSet.algorithmPredictions.filter().deleteAllSync();
      isar.predictionSets.where().idEqualTo(predictionSet.id).deleteAllSync();
    });
  }

  Future<void> saveAlgorithmPrediction(DbAlgorithmPrediction prediction, {bool saveLinks = true}) async {
    await isar.writeTxn(() async {
      await isar.dbAlgorithmPredictions.put(prediction);
      if(saveLinks) {
        await prediction.rating.save();
        await prediction.project.save();
        await prediction.group.save();
        await prediction.predictionSet.save();
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
}