/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';

extension RatingProjectDatabase on AnalystDatabase {
  Future<DbRatingProject?> getRatingProjectById(int id) async {
    return isar.dbRatingProjects.where().idEqualTo(id).findFirst();
  }

  Future<DbRatingProject> saveRatingProject(DbRatingProject project) async {
    await isar.writeTxn(() async {
      await isar.dbRatingProjects.put(project);
      project.dbGroups.save();
      project.ratings.save();
      project.matches.save();
      project.filteredMatches.save();
      project.lastUsedMatches.save();
    });
    return project;
  }

  Future<List<DbRatingProject>> getAllRatingProjects() async {
    return isar.dbRatingProjects.where().findAll();
  }

  Future<bool> deleteRatingProject(DbRatingProject project) async {
    // clear all linked shooter ratings
    if(!project.ratings.isLoaded) {
      await project.ratings.load();
      for(var rating in project.ratings) {
        deleteShooterRating(rating);
      }
    }

    return isar.dbRatingProjects.delete(project.id);
  }

  Future<bool> deleteShooterRating(DbShooterRating rating) async {
    // TODO: clear all linked rating events
    return isar.dbShooterRatings.delete(rating.id);
  }

  // TODO: cache loaded shooters?
  // Let's do it the dumb way first, and go from there.
  Future<DbShooterRating?> maybeKnownShooter({
    required DbRatingProject project,
    required DbRatingGroup group,
    required String processedMemberNumber
  }) {
    return isar.dbShooterRatings.where().dbKnownMemberNumbersElementEqualTo(processedMemberNumber)
        .filter()
        .project((q) => q.idEqualTo(project.id))
        .group((q) => q.uuidEqualTo(group.uuid))
        .findFirst();
  }

  Future<DbShooterRating> newShooterRatingFromWrapped({
    required DbRatingProject project,
    required DbRatingGroup group,
    required ShooterRating rating,
  }) {
    var dbRating = rating.wrappedRating;
    if(!dbRating.isPersisted) {
      dbRating.project.value = project;
      dbRating.group.value = group;
    }
    
    return upsertDbShooterRating(dbRating, linksChanged: dbRating.isPersisted);
  }

  /// Upsert a DbShooterRating.
  /// 
  /// If [linksChanged] is false, the links will not be saved in the write transaction.
  Future<DbShooterRating> upsertDbShooterRating(DbShooterRating rating, {bool linksChanged = true}) {
    return isar.writeTxn(() async {
      await isar.dbShooterRatings.put(rating);
      if(linksChanged) {
        await rating.project.save();
        await rating.group.save();
      }
      return rating;
    });
  }

  Future<int> countShooterRatings(DbRatingProject project, DbRatingGroup group) async {
    return await project.ratings.filter()
        .group((q) => q.idEqualTo(group.id))
        .count();
  }

  Future<List<double>> getConnectedness(DbRatingProject project, DbRatingGroup group) {
    return project.ratings.filter()
        .group((q) => q.idEqualTo(group.id))
        .connectednessProperty()
        .findAll();
  }
}