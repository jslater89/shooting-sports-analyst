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

  Future<DbRatingProject?> getRatingProjectByName(String name) async {
    return isar.dbRatingProjects.where().nameEqualTo(name).findFirst();
  }

  Future<DbRatingProject> saveRatingProject(DbRatingProject project, {bool checkName = true}) async {
    if(checkName) {
      var existingProject = await getRatingProjectByName(project.name);
      if(existingProject != null) {
        project.id = existingProject.id;

        await isar.writeTxn(() async {

          await existingProject.matches.reset();
          await existingProject.filteredMatches.reset();
          await existingProject.lastUsedMatches.reset();
          await existingProject.dbGroups.reset();

          return true;
        });
      }
    }
    await isar.writeTxn(() async {
      await isar.dbRatingProjects.put(project);
      await project.dbGroups.save();
      await project.ratings.save();
      await project.matches.save();
      await project.filteredMatches.save();
      await project.lastUsedMatches.save();
    });
    return project;
  }

  Future<List<DbRatingProject>> getAllRatingProjects() async {
    return isar.dbRatingProjects.where().findAll();
  }

  Future<bool> deleteRatingProject(DbRatingProject project) async {
    // clear all linked shooter ratings
    return isar.writeTxn(() async {
      if(!project.ratings.isLoaded) {
        await project.ratings.load();
        for(var rating in project.ratings) {
          _innerDeleteShooterRating(rating);
        }
      }

      return isar.dbRatingProjects.delete(project.id);
    });
  }

  Future<bool> _innerDeleteShooterRating(DbShooterRating rating) async {
      var deleted = await rating.events.filter().deleteAll();
      _log.v("Deleted $deleted events while deleting rating");
      return isar.dbShooterRatings.delete(rating.id);
  }

  Future<bool> deleteShooterRating(DbShooterRating rating) async {
    return isar.writeTxn(() async {
      return _innerDeleteShooterRating(rating);
    });
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
    return isar.writeTxn(() async {
      var dbRating = rating.wrappedRating;
      dbRating.project.value = project;
      dbRating.group.value = group;
      await isar.dbShooterRatings.put(dbRating);

      await dbRating.project.save();
      await dbRating.group.save();

      return dbRating;
    });
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
        var eventFutures = <Future>[];
        for(var event in r.newRatingEvents) {
          if(!event.isPersisted) {
            eventFutures.add(isar.dbRatingEvents.put(event).then((_) => event.match.save()));
            r.events.add(event);
          }
        }
        await Future.wait(eventFutures);

        r.newRatingEvents.clear();

        await r.events.save();
      }

      return count;
    });

  }

  Future<int> countShooterRatings(DbRatingProject project, RatingGroup group) async {
    return await project.ratings.filter()
        .group((q) => q.uuidEqualTo(group.uuid))
        .count();
  }

  Future<List<double>> getConnectedness(DbRatingProject project, RatingGroup group) {
    return project.ratings.filter()
        .group((q) => q.uuidEqualTo(group.uuid))
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