/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_query_element.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/match/translator.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("MatchDb");

class AnalystDatabase {
  static const knownMemberNumbersIndex = "knownMemberNumbers";
  static const allPossibleMemberNumbersIndex = "allPossibleMemberNumbers";
  static const eventNameIndex = "eventNameParts";
  static const sourceIdsIndex = "sourceIds";
  static const dateIndex = "date";
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

  static AnalystDatabase? _testInstance;
  factory AnalystDatabase.test() {
    if(_testInstance == null) {
      _testInstance = AnalystDatabase._();
      _testInstance!._init(test: true);
    }
    return _testInstance!;
  }

  late Isar isar;

  Future<void> _init({bool test = false}) async {
    isar = await Isar.open(
      [
        DbShootingMatchSchema,
        DbRatingProjectSchema,
        RatingGroupSchema,
        DbRatingEventSchema,
        DbShooterRatingSchema,
      ],
      maxSizeMiB: 1024 * 32,
      directory: "db",
      name: test ? "test-database" : "database",
    );

    isar.writeTxn(() async {
      for(var sport in SportRegistry().availableSports) {
        var provider = sport.builtinRatingGroupsProvider;
        if(provider != null) {
          await isar.ratingGroups.putAll(provider.builtinRatingGroups);
        }
      }
    });

    _readyCompleter.complete();
  }

  AnalystDatabase._();

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
  Future<List<DbShootingMatch>> queryMatches({String? name, DateTime? after, DateTime? before, int page = 0, int pageSize = 100, MatchSortField sort = const DateSort()}) {
    Query<DbShootingMatch> finalQuery = _buildMatchQuery(
      [
        if(name != null)
          NamePartsQuery(name),
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
      dbMatch = await isar.writeTxn<DbShootingMatch>(() async {
        var oldMatch = await getMatchByAnySourceId(dbMatch.sourceIds);
        if (oldMatch != null) {
          dbMatch.id = oldMatch.id;
          await isar.dbShootingMatchs.put(dbMatch);
        }
        else {
          dbMatch.id = await isar.dbShootingMatchs.put(dbMatch);
        }
        return dbMatch;
      });
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

  Future<List<DbShootingMatch>> getMatchesByMemberNumbers(List<String> memberNumbers) async {
    var matches = await isar.dbShootingMatchs.getAllByIndex(AnalystDatabase.memberNumbersAppearingIndex, [memberNumbers]);
    return matches.where((e) => e != null).toList().cast<DbShootingMatch>();
  }

  Future<Result<bool, ResultErr>> deleteMatch(int id) async {
    try {
      var result = await isar.dbShootingMatchs.delete(id);
      return Result.ok(result);
    }
    catch(e, stackTrace) {
      _log.e("Failed to delete match", error: e, stackTrace: stackTrace);
      return Result.err(StringError(e.toString()));
    }
  }

  Future<Result<bool, ResultErr>> deleteMatchBySourceId(String id) async {
    try {
      var result = await isar.dbShootingMatchs.deleteBySourceIds([id]);
      return Result.ok(result);
    }
    catch(e, stackTrace) {
      _log.e("Failed to delete match", error: e, stackTrace: stackTrace);
      return Result.err(StringError(e.toString()));
    }
  }

  DbShootingMatch? getMatchByAnySourceIdSync(List<String> ids) {
    for(var id in ids) {
      var match = isar.dbShootingMatchs.getBySourceIdsSync([id]);
      if(match != null) return match;
    }

    return null;
  }

  Future<void> migrateFromMatchCache(ProgressCallback callback) async {
    _log.d("Migrating from match cache");
    var cache = MatchCache();

    int i = 0;
    int matchCount = cache.allIndexEntries().length;
    for(var ie in cache.allIndexEntries()) {
      var oldMatch = await cache.getByIndex(ie);
      var newMatch = MatchTranslator.shootingMatchFrom(oldMatch);
      await saveMatch(newMatch);
      i += 1;
      if(i % 10 == 0) {
        _log.v("Migration: saved $i of $matchCount to database");
        await callback.call(i, matchCount);
      }
    }
    _log.i("Match cache migration complete with $matchCount cache entries processed");
  }

  Query<DbShootingMatch> _buildMatchQuery(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort()}) {
    NamePartsQuery? nameQuery;
    DateQuery? dateQuery;
    LevelNameQuery? levelNameQuery;

    for(var e in elements) {
      switch(e) {
        case NamePartsQuery():
          nameQuery = e;
        case DateQuery():
          dateQuery = e;
        case LevelNameQuery():
          levelNameQuery = e;
      }
    }

    // Defaults. Prefer strongly to 'where' by our sort. Since we do limit/offset
    // for paging, unless an alternate 'where' is highly selective, leaning on the
    // index for sort is probably preferable.
    MatchQueryElement? whereElement;
    if(dateQuery == null && (sort is DateSort)) {
      dateQuery = DateQuery(before: null, after: null);
      whereElement = dateQuery;
    }
    else if(nameQuery == null && (sort is NameSort)) {
      nameQuery = NamePartsQuery("");
      whereElement = nameQuery;
    }
    Iterable<MatchQueryElement> filterElements = elements;

    if(nameQuery?.canWhere ?? false) {
      nameQuery!;

      // If we have a one-word name query of sufficient length, prefer to 'where'
      // on it, since high selectivity will probably outweigh the fast sort on
      // by the other index.
      if(nameQuery.name.length >= 3 || (sort is NameSort)) {
        (whereElement, filterElements) = _buildElementLists(elements, nameQuery);
      }
    }

    var (sortProperties, whereSort) = _buildMatchSortFields(whereElement, sort);

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