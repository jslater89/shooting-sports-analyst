/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_query_element.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/fantasy_user.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/matchups.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/standing.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/schema/preferences.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/database/schema/registration.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/idpa.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("AnalystDb");

class AnalystDatabase {
  static const knownMemberNumbersIndex = "knownMemberNumbers";
  static const allPossibleMemberNumbersIndex = "allPossibleMemberNumbers";
  static const eventNameIndex = "eventNameParts";
  static const sourceIdsIndex = "sourceIds";
  static const dateIndex = "date";
  static const sportNameIndex = "sportName";
  static const memberNumbersAppearingIndex = "memberNumbersAppearing";
  static Future<void> get readyStatic => _readyCompleter.future;
  static Completer<void> _readyCompleter = Completer();

  static const maxSizeMiB = 1024 * 32;
  static int get maxSizeBytes => maxSizeMiB * 1024 * 1024;

  Future<void> get ready => readyStatic;

  static AnalystDatabase? _instance;
  factory AnalystDatabase() {
    if(_instance == null) {
      _instance = AnalystDatabase._();
      _instance!._init();
    }
    return _instance!;
  }

  AnalystDatabase.path(String path) {
    _instance = AnalystDatabase._();
    _instance!._init(path: path);
  }

  static AnalystDatabase? _testInstance;
  factory AnalystDatabase.test() {
    if(_testInstance == null) {
      _testInstance = AnalystDatabase._();
      _testInstance!._init(test: true);
    }
    return _testInstance!;
  }

  late Isar isar;

  Future<void> _init({bool test = false, String? path}) async {
    var db = Directory(path ?? "db/");
    if(!db.existsSync()) {
      db.createSync(recursive: true);
    }
    isar = await Isar.open(
      [
        // Rating-related collections
        DbShootingMatchSchema,
        StandaloneDbMatchEntrySchema,
        DbRatingProjectSchema,
        RatingGroupSchema,
        RatingSetSchema,
        DbRatingEventSchema,
        DbShooterRatingSchema,
        MatchRegistrationMappingSchema,
        MatchHeatSchema,
        ApplicationPreferencesSchema,

        // Fantasy-related collections
        FantasyUserSchema,
        LeagueSchema,
        FantasyRosterSlotTypeSchema,
        RosterSlotSchema,
        LeagueStandingSchema,
        LeagueSeasonSchema,
        LeagueMonthSchema,
        TeamSchema,
        FantasyPlayerSchema,
        MatchupSchema,
        PlayerMatchPerformanceSchema,
        PlayerMonthlyPerformanceSchema,
        MonthlyRosterSchema,
        RosterAssignmentSchema,
      ],
      maxSizeMiB: 1024 * 32,
      directory: db.path,
      name: test ? "test-database" : "database",
    );

    // TODO Fix for broken IDPA databases; remove after releasing alpha11
    var provider = idpaSport.builtinRatingGroupsProvider;
    if(provider != null && (await isar.ratingGroups.getByUuid("icore-pcc")) != null) {
      int deleted = 0;
      for(var group in provider.builtinRatingGroups) {
        var wrongId = group.uuid.replaceFirst("idpa-", "icore-");
        await isar.writeTxn(() async {
          await isar.ratingGroups.deleteByUuid(wrongId);
          await isar.ratingGroups.put(group);
        });
        deleted += 1;
      }
      _log.i("Fixed $deleted broken IDPA rating groups");
    }

    await isar.writeTxn(() async {
      for(var sport in SportRegistry().availableSports) {
        var provider = sport.builtinRatingGroupsProvider;
        if(provider != null) {
          await isar.ratingGroups.putAll(provider.builtinRatingGroups);
        }
      }

      // TODO: fantasy initialization here
    });

    _readyCompleter.complete();
  }

  AnalystDatabase._();

  /// Perform a synchronous write transaction.
  T writeTxnSync<T>(T Function() txn, {bool silent = false}) {
    // Making my life slightly easier if I ever want to move off of Isar.
    return isar.writeTxnSync(txn, silent: silent);
  }

  /// Contains a cache of shooter ratings. By default, [knownShooter] and [maybeKnownShooter]
  /// will not read from the cache. By default, ratings will be saved to the cache when
  /// inserted, updated, or read.
  Map<RatingGroup, Map<String, DbShooterRating>> loadedShooterRatingCache = {};
  DbShooterRating? lookupCachedRating(RatingGroup group, String memberNumber) {
    return loadedShooterRatingCache[group]?[memberNumber];
  }
  void cacheRating(RatingGroup group, DbShooterRating rating) {
    loadedShooterRatingCache[group] ??= {};
    for(var n in rating.allPossibleMemberNumbers) {
      loadedShooterRatingCache[group]![n] = rating;
    }
  }
  void clearLoadedShooterRatingCache() {
    loadedShooterRatingCache.clear();
    loadedShooterRatingCacheHits = 0;
    loadedShooterRatingCacheMisses = 0;
  }
  int loadedShooterRatingCacheHits = 0;
  int loadedShooterRatingCacheMisses = 0;

  /// The standard match query: index on name if present or date if not.
  Future<List<DbShootingMatch>> queryMatches({
    String? name,
    DateTime? after,
    DateTime? before,
    int page = 0,
    int pageSize = 100,
    MatchSortField sort = const DateSort(),
    Sport? sport,
  }) {
    Query<DbShootingMatch> finalQuery = _buildMatchQuery(
      [
        if(name != null)
          NamePartsQuery(name),
        if(sport != null)
          SportQuery([sport]),
        if(after != null || before != null)
          DateQuery(after: after, before: before),
      ],
      limit: pageSize,
      offset: page * pageSize,
    );

    return finalQuery.findAll();
  }

  /// Return Isar match IDs matching the query.
  Future<List<int>> queryMatchIds({
    String? name,
    DateTime? after,
    DateTime? before,
    int page = 0,
    int pageSize = 100,
    MatchSortField sort = const DateSort(),
    List<Sport>? sports,
  }) {
    Query<int> finalQuery = _buildMatchIdQuery(
      [
        if(name != null)
          NamePartsQuery(name),
        if(sports != null)
          SportQuery(sports),
        if(after != null || before != null)
          DateQuery(after: after, before: before),
      ],
      limit: pageSize,
      offset: page * pageSize,
    );

    return finalQuery.findAll();
  }

  Future<List<DbShootingMatch>> queryMatchesByCompetitorMemberNumbers(List<String> memberNumbers, {int page = 0, int pageSize = 10}) async {
    if(memberNumbers.isEmpty) return [];

    List<WhereClause> whereClauses = [];
    for(var memberNumber in memberNumbers) {
      whereClauses.add(IndexWhereClause.equalTo(
        indexName: AnalystDatabase.memberNumbersAppearingIndex,
        value: [memberNumber],
      ));
    }

    Query<DbShootingMatch> query = isar.dbShootingMatchs.buildQuery(
      whereClauses: whereClauses,
      sortBy: [
        SortProperty(property: DateQuery().property, sort: Sort.desc),
      ],
      limit: pageSize,
      offset: page * pageSize,
    );

    return await query.findAll();
  }

  Future<List<String>> queryMatchNamesByCompetitorMemberNumbers(List<String> memberNumbers, {int page = 0, int pageSize = 10}) async {
    if(memberNumbers.isEmpty) return [];

    List<WhereClause> whereClauses = [];
    for(var memberNumber in memberNumbers) {
      whereClauses.add(IndexWhereClause.equalTo(
        indexName: AnalystDatabase.memberNumbersAppearingIndex,
        value: [memberNumber],
      ));
    }

    Query<String> query = isar.dbShootingMatchs.buildQuery(
      whereClauses: whereClauses,
      sortBy: [
        SortProperty(property: DateQuery().property, sort: Sort.desc),
      ],
      limit: pageSize,
      offset: page * pageSize,
      property: "eventName",
    );

    return await query.findAll();
  }

  /// Save a match.
  ///
  /// The provided ShootingMatch will have its database ID set if the save succeeds.
  Future<Result<DbShootingMatch, ResultErr>> saveMatch(ShootingMatch match) async {
    if(match.sourceIds.isEmpty || match.sourceCode.isEmpty) {
      throw ArgumentError("Match must have at least one source ID and a source code to be saved in the database");
    }
    var dbMatch = DbShootingMatch.from(match);
    try {
      var oldMatch = await getMatchByAnySourceId(dbMatch.sourceIds);
      dbMatch = await isar.writeTxn<DbShootingMatch>(() async {
        if (oldMatch != null) {
          dbMatch.id = oldMatch.id;
          await isar.dbShootingMatchs.put(dbMatch);
        }
        else {
          dbMatch.id = await isar.dbShootingMatchs.put(dbMatch);
        }
        return dbMatch;
      });

      if(dbMatch.shootersStoredSeparately) {
        // We need to load outside the write transaction, because load can't be done inside.
        // It should be lightweight because dbMatch shouldn't have any DB entries (just the newly inserted ones).
        await dbMatch.shooterLinks.load();
        await isar.writeTxn(() async {
          if(oldMatch != null) {
            var deletedEntries = await deleteStandaloneMatchEntriesForMatchSourceIds(oldMatch.sourceIds);
            _log.d("Deleted $deletedEntries standalone match entries while updating match ${oldMatch.eventName}");
          }
          await isar.standaloneDbMatchEntrys.putAll(dbMatch.shooterLinks.toList());
          await dbMatch.shooterLinks.save();
        });
      }
    }
    catch(e, stackTrace) {
      _log.e("Failed to save match", error: e, stackTrace: stackTrace);
      _log.i("Failed source IDs: ${dbMatch.sourceIds}");
      return Result.err(StringError("$e"));
    }

    // For least confusion
    match.databaseId = dbMatch.id;
    return Result.ok(dbMatch);
  }

  Future<DbShootingMatch?> getMatchByAnySourceId(List<String> ids) async {
    for(var id in ids) {
      var match = await isar.dbShootingMatchs.getByIndex(AnalystDatabase.sourceIdsIndex, [id]);
      if(match != null) return match;
    }

    return null;
  }

  Future<List<DbShootingMatch>> getMatchesByAnySourceIds(Iterable<String> ids) async {
    return await isar.dbShootingMatchs.where().anyOf(ids, (query, id) => query.sourceIdsElementEqualTo(id)).findAll();
  }

  DbShootingMatch? getMatchByAnySourceIdSync(List<String> ids) {
    return isar.dbShootingMatchs.where().anyOf(ids, (query, id) => query.sourceIdsElementEqualTo(id)).findFirstSync();
  }

  Future<DbShootingMatch?> getMatchBySourceId(String id) {
    return getMatchByAnySourceId([id]);
  }

  Future<DbShootingMatch?> getMatch(int id) async {
    return await isar.dbShootingMatchs.get(id);
  }

  Future<List<DbShootingMatch>> getMatchesByIds(Iterable<Id> ids) async {
    return await isar.dbShootingMatchs.where().anyOf(ids, (query, id) => query.idEqualTo(id)).findAll();
  }

  Future<List<DbShootingMatch>> getMatchesByMemberNumbers(Iterable<String> memberNumbers) async {
    var matches = await isar.dbShootingMatchs
      .where()
      .anyOf(memberNumbers, (q, memberNumber) => q.memberNumbersAppearingElementEqualTo(memberNumber))
      .findAll();
    return matches;
  }

  Future<int> deleteStandaloneMatchEntriesForMatchSourceIds(List<String> matchSourceIds) async {
    return await isar.standaloneDbMatchEntrys.where().anyOf(matchSourceIds, (q, sourceId) => q.matchSourceIdsElementEqualTo(sourceId)).deleteAll();
  }

  Future<Result<bool, ResultErr>> deleteMatch(int id) async {
    return isar.writeTxn<Result<bool, ResultErr>>(() async {
      try {
        var match = await isar.dbShootingMatchs.get(id);
        if(match?.shootersStoredSeparately ?? false) {
          var deletedEntries = await deleteStandaloneMatchEntriesForMatchSourceIds(match!.sourceIds);
          _log.d("Deleted $deletedEntries standalone match entries while deleting match ${match.eventName}");
        }
        var result = await isar.dbShootingMatchs.delete(id);
        return Result.ok(result);
      }
      catch(e, stackTrace) {
        _log.e("Failed to delete match", error: e, stackTrace: stackTrace);
        return Result.err(StringError(e.toString()));
      }
    });
  }

  Future<Result<bool, ResultErr>> deleteMatchBySourceId(String id) async {
    var match = await getMatchBySourceId(id);
    if(match == null) {
      return Result.ok(false);
    }
    return deleteMatch(match.id);
  }

  // Future<void> migrateFromMatchCache(ProgressCallback callback) async {
  //   _log.d("Migrating from match cache");
  //   var cache = MatchCache();

  //   int i = 0;
  //   int matchCount = cache.allIndexEntries().length;
  //   for(var ie in cache.allIndexEntries()) {
  //     var oldMatch = await cache.getByIndex(ie);
  //     var newMatch = MatchTranslator.shootingMatchFrom(oldMatch);
  //     await saveMatch(newMatch);
  //     i += 1;
  //     if(i % 10 == 0) {
  //       _log.v("Migration: saved $i of $matchCount to database");
  //       await callback.call(i, matchCount);
  //     }
  //   }
  //   _log.i("Match cache migration complete with $matchCount cache entries processed");
  // }

  /// Build a match query. Returns either a [Query<DbShootingMatch>] or a [Query<int>], depending on the [idProperty] parameter.
  Query<DbShootingMatch> _buildMatchQuery(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort(), bool idProperty = false}) {
    var (whereElement, filterElements, sortProperties, whereSort) = _buildMatchQueryElements(elements, sort: sort);

    Query<DbShootingMatch> query = isar.dbShootingMatchs.buildQuery(
      whereClauses: whereElement?.whereClauses ?? [],
      filter: filterElements.isEmpty ? null : FilterGroup.and([
        for(var f in filterElements)
          if(f.filterCondition != null)
            f.filterCondition!,
      ]),
      sortBy: sortProperties,
      whereSort: whereSort,
      limit: limit,
      offset: offset,
    );

    return query;
  }


  Query<int> _buildMatchIdQuery(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort()}) {
    var (whereElement, filterElements, sortProperties, whereSort) = _buildMatchQueryElements(elements, sort: sort);

    Query<int> query = isar.dbShootingMatchs.buildQuery(
      whereClauses: whereElement?.whereClauses ?? [],
      filter: filterElements.isEmpty ? null : FilterGroup.and([
        for(var f in filterElements)
          if(f.filterCondition != null)
            f.filterCondition!,
      ]),
      sortBy: sortProperties,
      property: "id",
      whereSort: whereSort,
      limit: limit,
      offset: offset,
    );

    return query;
  }

  (MatchQueryElement?, Iterable<MatchQueryElement>, List<SortProperty>, Sort) _buildMatchQueryElements(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort()}) {
    NamePartsQuery? nameQuery;
    DateQuery? dateQuery;
    // ignore: unused_local_variable
    LevelNameQuery? levelNameQuery;
    SportQuery? sportQuery;

    for(var e in elements) {
      switch(e) {
        case NamePartsQuery():
          nameQuery = e;
        case DateQuery():
          dateQuery = e;
        case LevelNameQuery():
          levelNameQuery = e;
        case SportQuery():
          sportQuery = e;
      }
    }

    // Defaults. Prefer strongly to 'where' by our sort. Since we do limit/offset
    // for paging, unless an alternate 'where' is highly selective, leaning on the
    // index for sort is probably preferable.
    MatchQueryElement? whereElement;
    Iterable<MatchQueryElement> filterElements = elements;
    if(dateQuery == null && (sort is DateSort)) {
      dateQuery = DateQuery(before: null, after: null);
      whereElement = dateQuery;
    }
    else if(nameQuery == null && (sort is NameSort)) {
      nameQuery = NamePartsQuery("");
      whereElement = nameQuery;
    }
    (whereElement, filterElements) = _buildElementLists(elements, whereElement);

    if(nameQuery?.canWhere ?? false) {
      nameQuery!;

      // If we have a one-word name query of sufficient length, prefer to 'where'
      // on it, since high selectivity will probably outweigh the fast sort on
      // by the other index.
      if(nameQuery.name.length >= 3 || (sort is NameSort)) {
        (whereElement, filterElements) = _buildElementLists(elements, nameQuery);
      }
    }
    else if(sportQuery != null && whereElement == null) {
      // If we have a sport query and no other where element, we can where on it.
      // This is very unlikely to happen currently, since we're usually going to end up
      // with a name or date where for sorting, but just in case we add future sorts
      // that aren't where-backed...
      (whereElement, filterElements) = _buildElementLists(elements, sportQuery);
    }

    var (sortProperties, whereSort) = _buildMatchSortFields(whereElement, sort);
    return (whereElement, filterElements, sortProperties, whereSort);
  }

  (List<SortProperty>, Sort) _buildMatchSortFields(MatchQueryElement? whereElement, MatchSortField sort) {
    var direction = sort.desc ? Sort.desc : Sort.asc;
    switch(sort) {
      case NameSort():
        if(whereElement is NamePartsQuery) {
          return ([], direction);
        }
        else {
          return ([SortProperty(property: NamePartsQuery("").property, sort: direction)], direction);
        }
      case DateSort():
        if(whereElement is DateQuery) {
          return ([], direction);
        }
        else {
          return ([SortProperty(property: DateQuery().property, sort: direction)], direction);
        }
    }
  }

  (MatchQueryElement?, Iterable<MatchQueryElement>) _buildElementLists(Iterable<MatchQueryElement> elements, MatchQueryElement? where) {
    if(where == null) {
      return (null, elements);
    }
    else {
      return (where, elements.where((element) => element != where));
    }
  }
}

/// The order of a query.
///
/// Not all elements apply to all queries.
enum Order {
  /// Ascending order, by the most relevant quality of the data.
  ascending,
  /// Descending order, by the most relevant quality of the data.
  descending,

  /// Descending order by rating change.
  ///
  /// Applies only to rating event queries.
  descendingChange,
}
