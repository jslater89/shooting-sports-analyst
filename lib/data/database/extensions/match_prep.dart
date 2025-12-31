/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
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

  /// Get a match prep for a specific project and match ID, in both cases the database ID
  /// rather than any other ID.
  Future<MatchPrep?> getMatchPrepForProjectAndMatchIds(int projectId, int matchId) async {
    var syntheticId = MatchPrep.synthesizeIdFromIds(projectId, matchId);
    return isar.matchPreps.get(syntheticId);
  }

  /// Get a match prep for a specific project and match ID, in both cases the database ID
  /// rather than any other ID, synchronously.
  MatchPrep? getMatchPrepForProjectAndMatchIdsSync(int projectId, int matchId) {
    var syntheticId = MatchPrep.synthesizeIdFromIds(projectId, matchId);
    return isar.matchPreps.getSync(syntheticId);
  }

  /// Get a match prep for a specific project and match, if one exists.
  Future<MatchPrep?> getMatchPrepForProjectAndMatch(DbRatingProject project, FutureMatch match) async {
    return getMatchPrepForProjectAndMatchIds(project.id, match.id);
  }

  /// Get a match prep for a specific project and match, if one exists, synchronously.
  MatchPrep? getMatchPrepForProjectAndMatchSync(DbRatingProject project, FutureMatch match) {
    return getMatchPrepForProjectAndMatchIdsSync(project.id, match.id);
  }

  /// Save a match prep to the database.
  Future<MatchPrep> saveMatchPrep(MatchPrep matchPrep, {bool saveOwnLinks = true, bool savePredictionSetLinks = true}) async {
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
    return matchPrep;
  }

  /// Save a match prep to the database synchronously.
  MatchPrep saveMatchPrepSync(MatchPrep matchPrep) {
    isar.writeTxnSync(() {
      // sync recursively saves
      isar.matchPreps.putSync(matchPrep);
    });
    return matchPrep;
  }
}