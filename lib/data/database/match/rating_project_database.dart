/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("RatingProjectDatabase");

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
    var deleted = await rating.events.filter().deleteAll();
    _log.v("Deleted $deleted events while deleting rating");
    return isar.dbShooterRatings.delete(rating.id);
  }

  // TODO: cache loaded shooters?
  // Let's do it the dumb way first, and go from there.
  /// Retrieves a possible shooter rating from the database, or null if
  /// a rating is not found. [memberNumber] is assumed to be processed.
  Future<DbShooterRating?> maybeKnownShooter({
    required DbRatingProject project,
    required RatingGroup group,
    required String memberNumber
  }) {
    return isar.dbShooterRatings.where().dbKnownMemberNumbersElementEqualTo(memberNumber)
        .filter()
        .project((q) => q.idEqualTo(project.id))
        .group((q) => q.uuidEqualTo(group.uuid))
        .findFirst();
  }

  Future<DbShooterRating> newShooterRatingFromWrapped({
    required DbRatingProject project,
    required RatingGroup group,
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
        await rating.events.save();
        await rating.project.save();
        await rating.group.save();
      }
      return rating;
    });
  }

  /// Update DbShooterRatings that have changed as part of the rating process.
  Future<int> updateChangedRatings(Iterable<DbShooterRating> ratings) {
    return isar.writeTxn(() async {
      int count = 0;

      for(var r in ratings) {
        if(!r.isPersisted) {
          _log.w("Unexpectedly unpersisted DB rating");
          await r.project.save();
          await r.group.save();
        }
        await isar.dbShooterRatings.put(r);
        await r.events.save();
      }

      return count;
    });

  }

  Future<int> countShooterRatings(DbRatingProject project, RatingGroup group) async {
    return await project.ratings.filter()
        .group((q) => q.idEqualTo(group.id))
        .count();
  }

  Future<List<double>> getConnectedness(DbRatingProject project, RatingGroup group) {
    return project.ratings.filter()
        .group((q) => q.idEqualTo(group.id))
        .connectednessProperty()
        .findAll();
  }

  Future<List<DbRatingEvent>> getRatingEventsFor(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
  }) async {
    var query = _buildShooterEventQuery(rating, limit: limit, offset: offset, after: after, before: before);
    return query.findAll();
  }

  List<DbRatingEvent> getRatingEventsForSync(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
  }) {
    var query = _buildShooterEventQuery(rating, limit: limit, offset: offset, after: after, before: before);
    return query.findAllSync();
  }

  Query<DbRatingEvent> _buildShooterEventQuery(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
  }) {
    var builder = rating.events.filter()
        .sortByDateAndStageNumberDesc();
    Query<DbRatingEvent> query;
    if(limit > 0) {
      if(offset > 0) {
        query = builder.offset(offset).limit(limit).build();
      }
      else {
        query = builder.limit(limit).build();
      }
    }
    else {
      query = builder.build();
    }

    return query;
  }
}