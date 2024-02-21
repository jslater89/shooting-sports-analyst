/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match_query_element.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/match/translator.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("MatchDb");

class MatchDatabase {
  static const eventNameIndex = "eventNameParts";
  static const sourceIdsIndex = "sourceIds";
  static const dateIndex = "date";

  static Future<void> get readyStatic => _readyCompleter.future;
  static Completer<void> _readyCompleter = Completer();

  Future<void> get ready => readyStatic;

  static MatchDatabase? _instance;
  factory MatchDatabase() {
    if(_instance == null) {
      _instance = MatchDatabase._();
      _instance!._init();
    }
    return _instance!;
  }

  late Isar matchDb;

  Future<void> _init() async {
    matchDb = await Isar.open([
      DbShootingMatchSchema,
    ], directory: ".");
    _readyCompleter.complete();
  }

  MatchDatabase._();

  /// The standard query: index on name if present or date if not.
  Future<List<DbShootingMatch>> query({String? name, DateTime? after, DateTime? before, int page = 0, MatchSortField sort = const DateSort()}) {
    Query<DbShootingMatch> finalQuery = _buildQuery(
      [
        if(name != null)
          NamePartsQuery(name),
        DateQuery(after: after, before: before),
      ],
      limit: 100,
      offset: page * 100,
    );

    return finalQuery.findAll();
  }

  Future<Result<DbShootingMatch, ResultErr>> save(ShootingMatch match) async {
    if(match.sourceIds.isEmpty) {
      throw ArgumentError("Match must have at least one source ID to be saved in the database");
    }
    var dbMatch = DbShootingMatch.from(match);
    try {
      dbMatch = await matchDb.writeTxn<DbShootingMatch>(() async {
        var oldMatch = await getByAnySourceId(dbMatch.sourceIds);
        if (oldMatch != null) {
          dbMatch.id = oldMatch.id;
          await matchDb.dbShootingMatchs.put(dbMatch);
        }
        else {
          dbMatch.id = await matchDb.dbShootingMatchs.put(dbMatch);
        }
        return dbMatch;
      });
    }
    catch(e, stackTrace) {
      _log.e("Failed to save match", error: e, stackTrace: stackTrace);
      _log.i("Failed source IDs: ${dbMatch.sourceIds}");
      return Result.err(StringError("$e"));
    }

    return Result.ok(dbMatch);
  }

  Future<DbShootingMatch?> getByAnySourceId(List<String> ids) async {
    for(var id in ids) {
      var match = await matchDb.dbShootingMatchs.getByIndex("sourceIds", [id]);
      if(match != null) return match;
    }

    return null;
  }

  Future<void> migrateFromCache(ProgressCallback callback) async {
    _log.d("Migrating from match cache");
    var cache = MatchCache();

    int i = 0;
    int matchCount = cache.allIndexEntries().length;
    for(var ie in cache.allIndexEntries()) {
      var oldMatch = await cache.getByIndex(ie);
      var newMatch = MatchTranslator.shootingMatchFrom(oldMatch);
      await save(newMatch);
      i += 1;
      if(i % 10 == 0) {
        _log.v("Migration: saved $i of $matchCount to database");
        await callback.call(i, matchCount);
      }
    }
    _log.i("Match cache migration complete with $matchCount cache entries processed");
  }

  Query<DbShootingMatch> _buildQuery(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort()}) {
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

    var (sortProperties, whereSort) = _buildSortFields(whereElement, sort);

    Query<DbShootingMatch> query = matchDb.dbShootingMatchs.buildQuery(
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

  (List<SortProperty>, Sort) _buildSortFields(MatchQueryElement? whereElement, MatchSortField sort) {
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