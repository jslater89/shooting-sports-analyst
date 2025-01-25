/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/source/practiscore_report.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

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

  /// Retrieves a known shooter rating from the database.
  /// 
  /// if [useCache] is true, [loadedShooterRatingCache] will be checked for
  /// a cached rating before querying the database.
  Future<DbShooterRating> knownShooter({
    required DbRatingProject project,
    required RatingGroup group,
    required String memberNumber,
    bool usePossibleMemberNumbers = false,
    bool useCache = false,
    bool saveToCache = true,
  }) async {
    return (await maybeKnownShooter(project: project, group: group, memberNumber: memberNumber, usePossibleMemberNumbers: usePossibleMemberNumbers, useCache: useCache))!;
  }
  
  /// Retrieves a possible shooter rating from the database, or null if
  /// a rating is not found. [memberNumber] is assumed to be processed.
  /// 
  /// if [useCache] is true, [loadedShooterRatingCache] will be checked for
  /// a cached rating before querying the database.
  Future<DbShooterRating?> maybeKnownShooter({
    required DbRatingProject project,
    required RatingGroup group,
    required String memberNumber,
    bool usePossibleMemberNumbers = false,
    bool useCache = false,
    bool saveToCache = true,
  }) async {
    if(useCache) {
      var cachedRating = lookupCachedRating(group, memberNumber);
      if(cachedRating != null) {
        loadedShooterRatingCacheHits++;
        return cachedRating;
      }
    }
    if(usePossibleMemberNumbers) {
      var rating = await isar.dbShooterRatings.where().dbAllPossibleMemberNumbersElementEqualTo(memberNumber)
        .filter()
        .project((q) => q.idEqualTo(project.id))
        .group((q) => q.uuidEqualTo(group.uuid))
        .findFirst();
      if(rating != null) {
        if(saveToCache) {
          cacheRating(group, rating);
        }
        loadedShooterRatingCacheMisses++;
        return rating;
      }
    }
    else {
      var rating = await isar.dbShooterRatings.where().dbKnownMemberNumbersElementEqualTo(memberNumber)
        .filter()
        .project((q) => q.idEqualTo(project.id))
        .group((q) => q.uuidEqualTo(group.uuid))
        .findFirst();
      if(rating != null && saveToCache) {
        loadedShooterRatingCacheMisses++;
        cacheRating(group, rating);
      }
      return rating;
    }
    return null;
  }

  Future<DbShooterRating> newShooterRatingFromWrapped({
    required DbRatingProject project,
    required RatingGroup group,
    required ShooterRating rating,
    bool useCache = true,
  }) {
    
    var dbRating = rating.wrappedRating;
    dbRating.project.value = project;
    dbRating.group.value = group;
    if(useCache) {
      cacheRating(group, dbRating);
    }
    return isar.writeTxn(() async {
      await isar.dbShooterRatings.put(dbRating);

      await dbRating.project.save();
      await dbRating.group.save();

      return dbRating;
    });
  }

  /// Upsert a DbShooterRating.
  /// 
  /// If [linksChanged] is false, the links will not be saved in the write transaction.
  Future<DbShooterRating> upsertDbShooterRating(DbShooterRating rating, {bool linksChanged = true, bool useCache = true}) {
    if(useCache) {
      cacheRating(rating.group.value!, rating);
    }
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
  Future<int> updateChangedRatings(Iterable<DbShooterRating> ratings, {bool useCache = true}) async {
    var count = await isar.writeTxn(() async {
      late DateTime start;
      int count = 0;

      Map<String, DbShootingMatch> matches = {};

      for(var r in ratings) {
        if(Timings.enabled) start = DateTime.now();
        if(!r.isPersisted) {
          _log.w("Unexpectedly unpersisted DB rating");
          await r.project.save();
          await r.group.save();
        }
        await isar.dbShooterRatings.put(r);
        if(Timings.enabled) Timings().add(TimingType.saveDbRating, DateTime.now().difference(start).inMicroseconds);

        if(Timings.enabled) start = DateTime.now();
        var eventFutures = <Future>[];
        for(var event in r.newRatingEvents) {
          if(!event.isPersisted) {
            if(event.matchId.isNotEmpty && (!event.match.isLoaded || event.match.value == null)) {
              late DateTime matchStart;
              if(Timings.enabled) matchStart = DateTime.now();
              // If the hydrated match is cached, build a dummy match with the correct DB ID for the event.
              var cacheResult = HydratedMatchCache().getBySourceId(event.matchId);
              DbShootingMatch? match = null;
              if(cacheResult.isOk()) {
                var m = cacheResult.unwrap();
                if(m.databaseId != null) {
                  DbShootingMatch placeholder = DbShootingMatch.placeholder(m.databaseId!);
                  match = placeholder;
                }
              }

              // Otherwise, check our local cache.
              if(match == null) {
                match = matches[event.matchId];
              }

              // If it still isn't available, ask the DB.
              if(match == null) {
                match = await this.getMatchByAnySourceId([event.matchId]);
                matches[event.matchId] = match!;
              }
              event.match.value = match;
              if(Timings.enabled) Timings().add(TimingType.getEventMatches, DateTime.now().difference(matchStart).inMicroseconds);
            }
            eventFutures.add(isar.dbRatingEvents.put(event).then((_) => event.match.save()));
            r.events.add(event);
          }
        }
        await Future.wait(eventFutures);
        r.newRatingEvents.clear();
        await r.events.save();

        if(Timings.enabled) Timings().add(TimingType.persistEvents, DateTime.now().difference(start).inMicroseconds);
      }

      return count;
    });

    if(useCache) {
      for(var r in ratings) {
        cacheRating(r.group.value!, r);
      }
    }
    return count;
  }

  Future<int> countShooterRatings(DbRatingProject project, RatingGroup group) async {
    return await project.ratings.filter()
        .group((q) => q.uuidEqualTo(group.uuid))
        .count();
  }

  Future<List<double>> getConnectivity(DbRatingProject project, RatingGroup group) {
    return project.ratings.filter()
        .group((q) => q.uuidEqualTo(group.uuid))
        .connectivityProperty()
        .findAll();
  }

  Future<double> getConnectivitySum(DbRatingProject project, RatingGroup group) {
    return project.ratings.filter()
        .group((q) => q.uuidEqualTo(group.uuid))
        .connectivityProperty()
        .sum();
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

  List<List<double>> getRatingEventDoubleDataForSync(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
    Order order = Order.ascending,
  }) {
    var query = _buildShooterEventDoubleDataQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order);
    return query.findAllSync();
  }

  List<double> getRatingEventChangeForSync(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
    Order order = Order.descending,
  }) {
    var query = _buildShooterEventRatingChangeQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order);
    return query.findAllSync();
  }

  /// Get a list of historical rating values for a given competitor.
  /// 
  /// [limit] and [offset] specify the range of values to return.
  /// [after] and [before] limit results by date.
  /// [order] specifies the order of the results (descending by default, or ascending)
  /// [newRating] specifies whether to return the rating following this event's change (true),
  /// or the rating before its change is applied (false).
  List<double> getRatingEventRatingForSync(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
    Order order = Order.descending,
    bool newRating = true,
  }) {
    Query<double> query;
    if(newRating) {
      query = _buildShooterEventNewRatingQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order);
    }
    else {
      query = _buildShooterEventOldRatingQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order);
    }
    return query.findAllSync();
  }

  Future<Result<DbRatingProject, ResultErr>> migrateOldProject(OldRatingProject project, {String? nameOverride}) async {
    var projectName = project.name;
    var existingProject = await getRatingProjectByName(projectName);
    if(existingProject != null) {
      if(nameOverride != null) {
        projectName = nameOverride;
      }
      else {
        return Result.err(RatingMigrationError.nameOverlap);
      }
    }
    else if(nameOverride != null) {
      projectName = nameOverride;
    }

    DbRatingProject p = DbRatingProject(
      name: projectName,
      sportName: uspsaName,
      settings: RatingProjectSettings.fromOld(project),
    );

    List<DbShootingMatch> matches = [];
    var shortIdRegex = RegExp(r"^[0-9]{4,8}$");
    for(var matchUrl in project.matchUrls) {
      var id = matchUrl.split("/").last;
      String? prefixedId = null;
      if(shortIdRegex.hasMatch(id)) {
        prefixedId = "${PractiscoreHitFactorReportParser.uspsaCode}:$id";
      }
      var match = await getMatchByAnySourceId([
        id,
        if(prefixedId != null) prefixedId,
      ]);
      if(match != null) {
        matches.add(match);
      }
      else {
        _log.w("Failed to find match $id in database");
      }
    }

    p.matches.addAll(matches);
    // TODO: see if I can do this better
    p.dbGroups.addAll(p.sport.builtinRatingGroupsProvider?.defaultRatingGroups ?? []);

    _log.i("Migrated ${p.name} to DB ratings with ${matches.length} matches (vs. ${project.matchUrls.length} in old project)");

    await saveRatingProject(p, checkName: false);
    return Result.ok(p);
  }

  Query<DbRatingEvent> _buildShooterEventQuery(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
    Order order = Order.descending,
  }) {
    var b1 = rating.events.filter();
    QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterSortBy> builder;
    if(order == Order.descending) {
      builder = b1.sortByDateAndStageNumberDesc();
    }
    else {
      builder = b1.sortByDateAndStageNumber();
    }
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

Query<List<double>> _buildShooterEventDoubleDataQuery(DbShooterRating rating, {
  int limit = 0,
  int offset = 0,
  DateTime? after,
  DateTime? before,
  Order order = Order.descending,
}) {
  var b1 = rating.events.filter();
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterSortBy> builder;
  if(order == Order.descending) {
    builder = b1.sortByDateAndStageNumberDesc();
  }
  else {
    builder = b1.sortByDateAndStageNumber();
  }
  Query<List<double>> query;
  if(limit > 0) {
    if(offset > 0) {
      query = builder.offset(offset).limit(limit).doubleDataProperty().build();
    }
    else {
      query = builder.limit(limit).doubleDataProperty().build();
    }
  }
  else {
    query = builder.doubleDataProperty().build();
  }

  return query;
}

Query<double> _buildShooterEventRatingChangeQuery(DbShooterRating rating, {
  int limit = 0,
  int offset = 0,
  DateTime? after,
  DateTime? before,
  Order order = Order.descending,
}) {
  var b1 = rating.events.filter();
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterSortBy> builder;
  if(order == Order.descending) {
    builder = b1.sortByDateAndStageNumberDesc();
  }
  else {
    builder = b1.sortByDateAndStageNumber();
  }
  Query<double> query;
  if(limit > 0) {
    if(offset > 0) {
      query = builder.offset(offset).limit(limit).ratingChangeProperty().build();
    }
    else {
      query = builder.limit(limit).ratingChangeProperty().build();
    }
  }
  else {
    query = builder.ratingChangeProperty().build();
  }

  return query;
}

Query<double> _buildShooterEventNewRatingQuery(DbShooterRating rating, {
  int limit = 0,
  int offset = 0,
  DateTime? after,
  DateTime? before,
  Order order = Order.descending,
}) {
  var b1 = rating.events.filter();
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterSortBy> builder;
  if(order == Order.descending) {
    builder = b1.sortByDateAndStageNumberDesc();
  }
  else {
    builder = b1.sortByDateAndStageNumber();
  }
  Query<double> query;
  if(limit > 0) {
    if(offset > 0) {
      query = builder.offset(offset).limit(limit).newRatingProperty().build();
    }
    else {
      query = builder.limit(limit).newRatingProperty().build();
    }
  }
  else {
    query = builder.newRatingProperty().build();
  }

  return query;
}

Query<double> _buildShooterEventOldRatingQuery(DbShooterRating rating, {
  int limit = 0,
  int offset = 0,
  DateTime? after,
  DateTime? before,
  Order order = Order.descending,
}) {
  var b1 = rating.events.filter();
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterSortBy> builder;
  if(order == Order.descending) {
    builder = b1.sortByDateAndStageNumberDesc();
  }
  else {
    builder = b1.sortByDateAndStageNumber();
  }
  Query<double> query;
  if(limit > 0) {
    if(offset > 0) {
      query = builder.offset(offset).limit(limit).oldRatingProperty().build();
    }
    else {
      query = builder.limit(limit).oldRatingProperty().build();
    }
  }
  else {
    query = builder.oldRatingProperty().build();
  }

  return query;
}

enum RatingMigrationError implements ResultErr {
  nameOverlap;

  String get message => switch(this) {
    nameOverlap => "Ratings database already contains a project with that name."
  };
}