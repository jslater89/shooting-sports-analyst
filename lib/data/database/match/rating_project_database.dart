/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/migration_result.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/source/practiscore_report_constants.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("RatingProjectDatabase");

extension RatingProjectDatabase on AnalystDatabase {
  Future<DbRatingProject?> getRatingProjectById(int id) {
    return isar.dbRatingProjects.where().idEqualTo(id).findFirst();
  }

  Future<DbRatingProject?> getRatingProjectByName(String name) {
    return isar.dbRatingProjects.where().nameEqualTo(name).findFirst();
  }

  DbRatingProject? getRatingProjectByNameSync(String name) {
    return isar.dbRatingProjects.where().nameEqualTo(name).findFirstSync();
  }

  Future<DbRatingProject> saveRatingProject(DbRatingProject project, {bool checkName = true, bool saveLinks = true}) async {
    if(checkName) {
      var existingProject = await getRatingProjectByName(project.name);
      if(existingProject != null) {
        project.id = existingProject.id;
      }
    }
    if(project.dbCreated == null) {
      project.created = DateTime.now();
    }

    // This is for backward compatibility.
    if(project.dbUpdated == null) {
      project.updated = DateTime.now();
    }
    await isar.writeTxn(() async {
      await isar.dbRatingProjects.put(project);
      await project.dbGroups.save();
      if(saveLinks) {
        await project.ratings.save();
      }
    });
    return project;
  }

  DbRatingProject saveRatingProjectSync(DbRatingProject project, {bool checkName = true, bool saveLinks = true}) {
    if(checkName) {
      var existingProject = getRatingProjectByNameSync(project.name);
      if(existingProject != null) {
        project.id = existingProject.id;
      }
    }
    if(project.dbCreated == null) {
      project.created = DateTime.now();
    }

    // This is for backward compatibility.
    if(project.dbUpdated == null) {
      project.updated = DateTime.now();
    }
    isar.writeTxnSync(() {
      isar.dbRatingProjects.putSync(project);
      project.dbGroups.saveSync();
      if(saveLinks) {
        project.ratings.saveSync();
      }
    });
    return project;
  }

  Future<List<DbRatingProject>> getAllRatingProjects() async {
    return isar.dbRatingProjects.where().findAll();
  }

  Future<bool> deleteRatingProject(DbRatingProject project, {ProgressCallback? progressCallback}) async {
    int ratingCount = project.ratings.countSync();
    // clear all linked shooter ratings
    return isar.writeTxn(() async {
      if(!project.ratings.isLoaded) {
        await project.ratings.load();
        for(var (i, rating) in project.ratings.indexed) {
          _innerDeleteShooterRating(rating);
          if(progressCallback != null && i % 50 == 0) {
            await progressCallback(i, ratingCount);
          }
        }
      }

      await isar.matchHeats.filter().projectIdEqualTo(project.id).deleteAll();

      return isar.dbRatingProjects.delete(project.id);
    });
  }

  Future<bool> _innerDeleteShooterRating(DbShooterRating rating) async {
      await rating.events.filter().deleteAll();
      // _log.v("Deleted $deleted events while deleting rating");
      return isar.dbShooterRatings.delete(rating.id);
  }

  Future<bool> deleteShooterRating(DbShooterRating rating) async {
    return isar.writeTxn(() async {
      return _innerDeleteShooterRating(rating);
    });
  }

  bool deleteShooterRatingSync(DbShooterRating rating) {
    return isar.writeTxnSync(() {
      return _innerDeleteShooterRatingSync(rating);
    });
  }

  bool _innerDeleteShooterRatingSync(DbShooterRating rating) {
      rating.events.filter().deleteAllSync();
      // _log.v("Deleted $deleted events while deleting rating");
      return isar.dbShooterRatings.deleteSync(rating.id);
  }


  /// Checks if a shooter exists in the database.
  ///
  /// This is currently no more efficient than [maybeKnownShooter], but it may be
  /// possible to optimize in the future.
  Future<bool> hasShooter({
    required DbRatingProject project,
    required RatingGroup group,
    required String memberNumber,
    bool useCache = false,
    bool usePossibleMemberNumbers = false,
  }) async {
    return (await maybeKnownShooter(project: project, group: group, memberNumber: memberNumber, usePossibleMemberNumbers: usePossibleMemberNumbers, useCache: useCache)) != null;
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
  /// If [useCache] is true, [loadedShooterRatingCache] will be checked for
  /// a cached rating before querying the database.
  ///
  /// If [onlyCache] is true, the cache will be checked, but no database query will be made.
  ///
  /// If [saveToCache] is true (the default), any ratings looked up will be saved to the cache.
  ///
  Future<DbShooterRating?> maybeKnownShooter({
    required DbRatingProject project,
    required RatingGroup group,
    required String memberNumber,
    bool usePossibleMemberNumbers = false,
    bool useCache = false,
    bool onlyCache = false,
    bool saveToCache = true,
  }) async {
    if(useCache) {
      var cachedRating = lookupCachedRating(group, memberNumber);
      if(cachedRating != null) {
        loadedShooterRatingCacheHits++;
        return cachedRating;
      }
      if(onlyCache) {
        return null;
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

  /// Retrieves a possible shooter rating from the database, or null if
  /// a rating is not found. [memberNumber] is assumed to be processed.
  ///
  /// if [useCache] is true, [loadedShooterRatingCache] will be checked for
  /// a cached rating before querying the database. If [onlyCache] is true,
  /// the cache will be checked, but no database query will be made.
  DbShooterRating? maybeKnownShooterSync({
    required DbRatingProject project,
    required RatingGroup group,
    required String memberNumber,
    bool usePossibleMemberNumbers = false,
    bool useCache = false,
    bool onlyCache = false,
    bool saveToCache = true,
  }) {
    if(useCache) {
      var cachedRating = lookupCachedRating(group, memberNumber);
      if(cachedRating != null) {
        loadedShooterRatingCacheHits++;
        return cachedRating;
      }
      if(onlyCache) {
        return null;
      }
    }
    if(usePossibleMemberNumbers) {
      var rating = isar.dbShooterRatings.where().dbAllPossibleMemberNumbersElementEqualTo(memberNumber)
        .filter()
        .project((q) => q.idEqualTo(project.id))
        .group((q) => q.uuidEqualTo(group.uuid))
        .findFirstSync();
      if(rating != null) {
        if(saveToCache) {
          cacheRating(group, rating);
        }
        loadedShooterRatingCacheMisses++;
        return rating;
      }
    }
    else {
      var rating = isar.dbShooterRatings.where().dbKnownMemberNumbersElementEqualTo(memberNumber)
        .filter()
        .project((q) => q.idEqualTo(project.id))
        .group((q) => q.uuidEqualTo(group.uuid))
        .findFirstSync();
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

  /// Create a new DbShooterRating from a rating engine-specific [ShooterRating].
  ///
  /// If [standalone] is true, the database operation will be wrapped in a write transaction.
  /// Otherwise, the caller is responsible for ensuring that the database operation is wrapped
  /// in a write transaction.
  DbShooterRating newShooterRatingFromWrappedSync({
    required DbRatingProject project,
    required RatingGroup group,
    required ShooterRating rating,
    bool useCache = true,
    bool standalone = true,
  }) {

    var dbRating = rating.wrappedRating;
    dbRating.project.value = project;
    dbRating.group.value = group;
    if(useCache) {
      cacheRating(group, dbRating);
    }
    if(standalone) {
      return isar.writeTxnSync(() {
        isar.dbShooterRatings.putSync(dbRating);

        dbRating.project.saveSync();
        dbRating.group.saveSync();

        return dbRating;
      });
    }
    else {
      isar.dbShooterRatings.putSync(dbRating);

      dbRating.project.saveSync();
      dbRating.group.saveSync();

      return dbRating;
    }
  }

  /// Upsert a DbShooterRating.
  ///
  /// If [linksChanged] is false, the links will not be saved in the write transaction.
  Future<DbShooterRating> upsertDbShooterRating(DbShooterRating rating, {bool linksChanged = true, bool useCache = true}) {
    if(useCache) {
      cacheRating(rating.group.value!, rating);
    }
    return isar.writeTxn(() async {
      return _innerUpsertDbShooterRating(rating, linksChanged);
    });
  }

  Future<List<DbShooterRating>> upsertDbShooterRatings(List<DbShooterRating> ratings, {bool linksChanged = true, bool useCache = true}) async {
    if(useCache) {
      for(var r in ratings) {
        cacheRating(r.group.value!, r);
      }
    }
    return isar.writeTxn(() async {
      List<DbShooterRating> results = [];
      for(var r in ratings) {
        results.add(await _innerUpsertDbShooterRating(r, linksChanged));
      }
      return results;
    });
  }

  Future<DbShooterRating> _innerUpsertDbShooterRating(DbShooterRating rating, bool linksChanged) async {
    await isar.dbShooterRatings.put(rating);
    if(linksChanged) {
      await rating.events.save();
      await rating.project.save();
      await rating.group.save();
    }
    return rating;
  }

  /// Upsert a DbShooterRating.
  ///
  /// If [linksChanged] is false, the links will not be saved in the write transaction.
  ///
  /// If [standalone] is true, the database operation will be wrapped in a write transaction.
  /// Otherwise, the caller is responsible for ensuring that the database operation is wrapped
  /// in a write transaction.
  DbShooterRating upsertDbShooterRatingSync(DbShooterRating rating, {bool linksChanged = true, bool useCache = true, bool standalone = true}) {
    if(useCache) {
      cacheRating(rating.group.value!, rating);
    }
    if(standalone) {
      return isar.writeTxnSync(() {
        return _innerUpsertDbShooterRatingSync(rating, linksChanged);
      });
    }
    else {
      return _innerUpsertDbShooterRatingSync(rating, linksChanged);
    }
  }

  List<DbShooterRating> upsertDbShooterRatingsSync(List<DbShooterRating> ratings, {bool linksChanged = true, bool useCache = true}) {
    if(useCache) {
      for(var r in ratings) {
        cacheRating(r.group.value!, r);
      }
    }
    return isar.writeTxnSync(() {
      List<DbShooterRating> results = [];
      for(var r in ratings) {
        results.add(_innerUpsertDbShooterRatingSync(r, linksChanged));
      }
      return results;
    });
  }

  DbShooterRating _innerUpsertDbShooterRatingSync(DbShooterRating rating, bool linksChanged) {
    isar.dbShooterRatings.putSync(rating);
    if(linksChanged) {
      rating.events.saveSync();
      rating.project.saveSync();
      rating.group.saveSync();
    }
    return rating;
  }

  /// Upsert a DbRatingEvent.
  Future<DbRatingEvent> upsertDbRatingEvent(DbRatingEvent event) {
    return isar.writeTxn(() async {
      await isar.dbRatingEvents.put(event);
      return event;
    });
  }

  /// Update DbShooterRatings that have changed as part of the rating process.
  Future<void> updateChangedRatings(Iterable<DbShooterRating> ratings, {bool useCache = true}) async {
    await isar.writeTxn(() async {
      late DateTime start;

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
                  DbShootingMatch placeholder = DbShootingMatch.dbPlaceholder(m.databaseId!);
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
            isar.dbRatingEvents.putSync(event);
            r.events.add(event);
          }
        }
        r.newRatingEvents.clear();
        r.events.saveSync();

        if(Timings.enabled) Timings().add(TimingType.persistEvents, DateTime.now().difference(start).inMicroseconds);
      }
    });

    if(useCache) {
      for(var r in ratings) {
        cacheRating(r.group.value!, r);
      }
    }
  }

  /// Update DbShooterRatings that have changed as part of the rating process.
  void updateChangedRatingsSync(Iterable<DbShooterRating> ratings, {bool useCache = true, ChangedRatingPersistedSyncCallback? onPersisted}) {
    late DateTime outerStart;
    if(Timings.enabled) outerStart = DateTime.now();
    isar.writeTxnSync(() {
      int progress = 0;
      late DateTime start;

      Map<String, DbShootingMatch> matches = {};

      for(var r in ratings) {
        if(Timings.enabled) start = DateTime.now();
        if(!r.isPersisted) {
          _log.w("Unexpectedly unpersisted DB rating");
          r.project.saveSync();
          r.group.saveSync();
        }
        isar.dbShooterRatings.putSync(r);
        if(Timings.enabled) Timings().add(TimingType.saveDbRating, DateTime.now().difference(start).inMicroseconds);

        if(Timings.enabled) start = DateTime.now();
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
                  DbShootingMatch placeholder = DbShootingMatch.dbPlaceholder(m.databaseId!);
                  match = placeholder;
                }
              }

              // Otherwise, check our local cache.
              if(match == null) {
                match = matches[event.matchId];
              }

              // If it still isn't available, ask the DB.
              if(match == null) {
                match = this.getMatchByAnySourceIdSync([event.matchId]);
                matches[event.matchId] = match!;
              }
              event.match.value = match;
              if(Timings.enabled) Timings().add(TimingType.getEventMatches, DateTime.now().difference(matchStart).inMicroseconds);
            }
            isar.dbRatingEvents.putSync(event);
            event.match.saveSync();
            r.events.add(event);
          }
        }
        r.newRatingEvents.clear();
        r.events.saveSync();

        if(Timings.enabled) Timings().add(TimingType.persistEvents, DateTime.now().difference(start).inMicroseconds);
        if(onPersisted != null) {
          onPersisted(
            progress: progress,
            total: ratings.length,
            message: r.toString(),
          );
          progress += 1;
        }
      }
    });
    if(Timings.enabled) Timings().add(TimingType.dbRatingUpdateTransaction, DateTime.now().difference(outerStart).inMicroseconds);

    if(Timings.enabled) outerStart = DateTime.now();
    if(useCache) {
      for(var r in ratings) {
        cacheRating(r.group.value!, r);
      }
    }
    if(Timings.enabled) Timings().add(TimingType.cacheUpdatedRatings, DateTime.now().difference(outerStart).inMicroseconds);

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

  List<double> getConnectivitySync(DbRatingProject project, RatingGroup group) {
    return project.ratings.filter()
        .group((q) => q.uuidEqualTo(group.uuid))
        .connectivityProperty()
        .findAllSync();
  }

  Future<double> getConnectivitySum(DbRatingProject project, RatingGroup group) {
    return project.ratings.filter()
        .group((q) => q.uuidEqualTo(group.uuid))
        .connectivityProperty()
        .sum();
  }

  double getConnectivitySumSync(DbRatingProject project, RatingGroup group) {
    return project.ratings.filter()
        .group((q) => q.uuidEqualTo(group.uuid))
        .connectivityProperty()
        .sumSync();
  }

  Future<List<DbRatingEvent>> getRatingEventsFor(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
    Order order = Order.descending,
  }) async {
    var query = _buildShooterEventQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order);
    return query.findAll();
  }

  List<DbRatingEvent> getRatingEventsForSync(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
    Order order = Order.descending,
  }) {
    var query = _buildShooterEventQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order);
    return query.findAllSync();
  }

  /// Delete rating events from a shooter rating.
  ///
  /// If [loadLink] is true, the event link will be loaded from the database before
  /// the deletion operation if not already loaded. If [loadLink] is false, the caller
  /// is responsible for ensuring that the event link is loaded.
  ///
  /// This operation does not perform any rater-specific work. Callers should generally
  /// use the [ShooterRating.rollbackEvents] method instead, implementations of which should
  /// a) call this method to update the database, and b) do any rater-specific work such
  /// as updateTrends() after it returns.
  ///
  /// Returns the number of events deleted.
  Future<int> deleteRatingEvents(DbShooterRating rating, List<DbRatingEvent> events, {bool loadLink = true}) async {
    if(loadLink && !rating.events.isLoaded) {
      await rating.events.load();
    }

    List<int> eventIds = events.map((e) => e.id).toList();
    DbRatingEvent? firstEvent;
    for(var e in events) {
      if(firstEvent == null) {
        firstEvent = e;
      }
      else {
        if(e.dateAndStageNumber < firstEvent.dateAndStageNumber) {
          firstEvent = e;
        }
      }
    }

    if(firstEvent == null) {
      return 0;
    }

    var originalLength = rating.events.length;
    rating.events.removeWhere((e) => eventIds.contains(e.id));
    rating.cachedLength -= events.length;

    rating.lastSeen = rating.events.last.date;
    rating.rating = rating.events.last.newRating;

    await upsertDbShooterRating(rating, linksChanged: true);
    return originalLength - rating.events.length;
  }

  Future<List<DbShootingMatch>> getMostRecentMatchesFor(DbShooterRating rating, {int window = 5}) async {
    var query = rating.events.filter()
      .sortByDateAndStageNumberDesc()
      .distinctByMatchId()
      .limit(window);
    var events = await query.findAll();
    var matches = <DbShootingMatch>[];
    for(var e in events) {
      var id = e.matchId;
      var match = await getMatchBySourceId(id);
      if(match != null) {
        matches.add(match);
      }
    }
    return matches;
  }

  Future<List<DbRatingEvent>> getRatingEventsByMatchIds(DbShooterRating rating, {required List<String> matchIds}) async {
    if(matchIds.isEmpty) return [];

    var query = rating.events.filter();
    QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterFilterCondition> finishedQuery;
    if(matchIds.length > 1) {
      finishedQuery = query.anyOf(matchIds, (q, id) => q.matchIdEqualTo(id));
    }
    else {
      finishedQuery = query.matchIdEqualTo(matchIds.first);
    }

    return finishedQuery.findAll();
  }

  List<DbRatingEvent> getRatingEventsByMatchIdsSync(DbShooterRating rating, {required List<String> matchIds}) {
    if(matchIds.isEmpty) return [];

    var query = rating.events.filter();
    QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterFilterCondition> finishedQuery;
    if(matchIds.length > 1) {
      finishedQuery = query.anyOf(matchIds, (q, id) => q.matchIdEqualTo(id));
    }
    else {
      finishedQuery = query.matchIdEqualTo(matchIds.first);
    }

    return finishedQuery.findAllSync();
  }

  List<List<double>> getRatingEventDoubleDataForSync(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
    Order order = Order.ascending,
    bool nonzeroChange = false,
  }) {
    var query = _buildShooterEventDoubleDataQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order, nonzeroChange: nonzeroChange);
    return query.findAllSync();
  }

  List<double> getRatingEventChangeForSync(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
    Order order = Order.descending,
    bool nonzeroChange = false,
  }) {
    var query = _buildShooterEventRatingChangeQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order, nonzeroChange: nonzeroChange);
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
    bool nonzeroChange = false,
  }) {
    QueryBuilder<DbRatingEvent, double, QQueryOperations> query;
    if(newRating) {
      query = _buildShooterEventNewRatingQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order, nonzeroChange: nonzeroChange);
    }
    else {
      query = _buildShooterEventOldRatingQuery(rating, limit: limit, offset: offset, after: after, before: before, order: order, nonzeroChange: nonzeroChange);
    }
    return query.findAllSync();
  }

  /// Migrate an old in-memory project to the new database format.
  ///
  /// [nameOverride] allows the caller to specify a name for the new project.
  /// If not provided, and the name of the old project is already in use, the migration will fail.
  ///
  /// On success, the caller will receive a [ProjectMigrationResult] containing the new project and a list of match IDs that failed to migrate.
  Future<Result<ProjectMigrationResult, ResultErr>> migrateOldProject(OldRatingProject project, {String? nameOverride}) async {
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

    List<String> failedMatchIds = [];
    List<DbShootingMatch> matches = [];
    var shortIdRegex = RegExp(r"^[0-9]{4,8}$");
    for(var matchUrl in project.matchUrls) {
      var id = matchUrl.split("/").last;
      String? prefixedId = null;
      if(shortIdRegex.hasMatch(id)) {
        prefixedId = "${uspsaCode}:$id";
      }
      var match = await getMatchByAnySourceId([
        id,
        if(prefixedId != null) prefixedId,
      ]);
      if(match != null) {
        matches.add(match);
      }
      else {
        _log.w("Failed to find match $id (prefixed: $prefixedId) in database");
        failedMatchIds.add(id);
      }
    }

    p.matchPointers.addAll(matches.map((m) => MatchPointer.fromDbMatch(m)));
    // TODO: see if I can do this better
    p.dbGroups.addAll(p.sport.builtinRatingGroupsProvider?.defaultRatingGroups ?? []);

    _log.i("Migrated ${p.name} to DB ratings with ${matches.length} matches (vs. ${project.matchUrls.length} in old project)");

    await saveRatingProject(p, checkName: false);
    return Result.ok(ProjectMigrationResult(
      project: p,
      failedMatchIds: failedMatchIds,
    ));
  }



  Query<DbRatingEvent> _buildShooterEventQuery(DbShooterRating rating, {
    int limit = 0,
    int offset = 0,
    DateTime? after,
    DateTime? before,
    Order order = Order.descending,
    bool nonzeroChange = false,
  }) {
    QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterFilterCondition> b1 = rating.events.filter();
    if(nonzeroChange) {
      b1 = b1.not().ratingChangeEqualTo(0.0, epsilon: 0);
    }
    if(after != null) {
      b1 = b1.group((q) => q.dateGreaterThan(after).or().dateEqualTo(after));
    }
    if(before != null) {
      b1 = b1.group((q) => q.dateLessThan(before).or().dateEqualTo(before));
    }
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

QueryBuilder<DbRatingEvent, List<double>, QQueryOperations> _buildShooterEventDoubleDataQuery(DbShooterRating rating, {
  int limit = 0,
  int offset = 0,
  DateTime? after,
  DateTime? before,
  Order order = Order.descending,
  bool nonzeroChange = false,
}) {
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterFilterCondition> b1 = rating.events.filter();
  if(nonzeroChange) {
    b1 = b1.not().ratingChangeEqualTo(0.0, epsilon: 0);
  }
  if(after != null) {
    b1 = b1.group((q) => q.dateGreaterThan(after).or().dateEqualTo(after));
  }
  if(before != null) {
    b1 = b1.group((q) => q.dateLessThan(before).or().dateEqualTo(before));
  }
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterSortBy> builder;
  if(order == Order.descending) {
    builder = b1.sortByDateAndStageNumberDesc();
  }
  else {
    builder = b1.sortByDateAndStageNumber();
  }
  QueryBuilder<DbRatingEvent, List<double>, QQueryOperations> query;
  if(limit > 0) {
    if(offset > 0) {
      query = builder.offset(offset).limit(limit).doubleDataProperty();
    }
    else {
      query = builder.limit(limit).doubleDataProperty();
    }
  }
  else {
    query = builder.doubleDataProperty();
  }

  return query;
}

QueryBuilder<DbRatingEvent, double, QQueryOperations> _buildShooterEventRatingChangeQuery(DbShooterRating rating, {
  int limit = 0,
  int offset = 0,
  DateTime? after,
  DateTime? before,
  Order order = Order.descending,
  bool nonzeroChange = false,
}) {
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterFilterCondition> b1 = rating.events.filter();
  if(nonzeroChange) {
    b1 = b1.not().ratingChangeEqualTo(0.0, epsilon: 0);
  }
  if(after != null) {
    b1 = b1.group((q) => q.dateGreaterThan(after).or().dateEqualTo(after));
  }
  if(before != null) {
    b1 = b1.group((q) => q.dateLessThan(before).or().dateEqualTo(before));
  }
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterSortBy> builder;
  if(order == Order.descending) {
    builder = b1.sortByDateAndStageNumberDesc();
  }
  else if (order == Order.ascending) {
    builder = b1.sortByDateAndStageNumber();
  }
  else {
    builder = b1.sortByRatingChangeDesc();
  }
  QueryBuilder<DbRatingEvent, double, QQueryOperations> query;
  if(limit > 0) {
    if(offset > 0) {
      query = builder.offset(offset).limit(limit).ratingChangeProperty();
    }
    else {
      query = builder.limit(limit).ratingChangeProperty();
    }
  }
  else {
    query = builder.ratingChangeProperty();
  }

  return query;
}

QueryBuilder<DbRatingEvent, double, QQueryOperations> _buildShooterEventNewRatingQuery(DbShooterRating rating, {
  int limit = 0,
  int offset = 0,
  DateTime? after,
  DateTime? before,
  Order order = Order.descending,
  bool nonzeroChange = false,
}) {
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterFilterCondition> b1 = rating.events.filter();
  if(nonzeroChange) {
    b1 = b1.not().ratingChangeEqualTo(0.0, epsilon: 0);
  }
  if(after != null) {
    b1 = b1.group((q) => q.dateGreaterThan(after).or().dateEqualTo(after));
  }
  if(before != null) {
    b1 = b1.group((q) => q.dateLessThan(before).or().dateEqualTo(before));
  }
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterSortBy> builder;
  if(order == Order.descending) {
    builder = b1.sortByDateAndStageNumberDesc();
  }
  else {
    builder = b1.sortByDateAndStageNumber();
  }
  QueryBuilder<DbRatingEvent, double, QQueryOperations> query;
  if(limit > 0) {
    if(offset > 0) {
      query = builder.offset(offset).limit(limit).newRatingProperty();
    }
    else {
      query = builder.limit(limit).newRatingProperty();
    }
  }
  else {
    query = builder.newRatingProperty();
  }

  return query;
}

QueryBuilder<DbRatingEvent, double, QQueryOperations> _buildShooterEventOldRatingQuery(DbShooterRating rating, {
  int limit = 0,
  int offset = 0,
  DateTime? after,
  DateTime? before,
  Order order = Order.descending,
  bool nonzeroChange = false,
}) {
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterFilterCondition> b1 = rating.events.filter();
  if(nonzeroChange) {
    b1 = b1.not().ratingChangeEqualTo(0.0);
  }
  if(after != null) {
    b1 = b1.group((q) => q.dateGreaterThan(after).or().dateEqualTo(after));
  }
  if(before != null) {
    b1 = b1.group((q) => q.dateLessThan(before).or().dateEqualTo(before));
  }
  QueryBuilder<DbRatingEvent, DbRatingEvent, QAfterSortBy> builder;
  if(order == Order.descending) {
    builder = b1.sortByDateAndStageNumberDesc();
  }
  else {
    builder = b1.sortByDateAndStageNumber();
  }
  QueryBuilder<DbRatingEvent, double, QQueryOperations> query;
  if(limit > 0) {
    if(offset > 0) {
      query = builder.offset(offset).limit(limit).oldRatingProperty();
    }
    else {
      query = builder.limit(limit).oldRatingProperty();
    }
  }
  else {
    query = builder.oldRatingProperty();
  }

  return query;
}

enum RatingMigrationError implements ResultErr {
  nameOverlap;

  String get message => switch(this) {
    nameOverlap => "Ratings database already contains a project with that name."
  };
}

typedef ChangedRatingPersistedCallback = Future<void> Function({
  required int progress,
  required int total,
  String? message
});

typedef ChangedRatingPersistedSyncCallback = void Function({
  required int progress,
  required int total,
  String? message
});
