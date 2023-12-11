/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:uspsa_result_viewer/data/database/match_query_element.dart';
import 'package:uspsa_result_viewer/data/database/schema/match.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/match/translator.dart';
import 'package:uspsa_result_viewer/util.dart';

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
  Future<List<DbShootingMatch>> query({String? name, DateTime? after, DateTime? before, int page = 0}) {
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

  Future<DbShootingMatch> save(ShootingMatch match) async {
    if(match.sourceIds.isEmpty) {
      throw ArgumentError("Match must have at least one source ID to be saved in the database");
    }
    var dbMatch = DbShootingMatch.from(match);
    dbMatch = await matchDb.writeTxn<DbShootingMatch>(() async {
      try {
        var oldMatch = await getByAnySourceId(dbMatch.sourceIds);
        if (oldMatch != null) {
          dbMatch.id = oldMatch.id;
          await matchDb.dbShootingMatchs.put(dbMatch);
        }
        else {
          dbMatch.id = await matchDb.dbShootingMatchs.put(dbMatch);
        }
        return dbMatch;
      } catch(e) {
        print("Failed to save match: $e");
        print("${dbMatch.sourceIds}");
        rethrow;
      }
    });
    return dbMatch;
  }

  Future<DbShootingMatch?> getByAnySourceId(List<String> ids) async {
    for(var id in ids) {
      var match = await matchDb.dbShootingMatchs.getByIndex("sourceIds", [id]);
      if(match != null) return match;
    }

    return null;
  }

  Future<void> migrateFromCache(ProgressCallback callback) async {
    var cache = MatchCache();

    int i = 0;
    int matchCount = cache.allIndexEntries().length;
    for(var ie in cache.allIndexEntries()) {
      var oldMatch = await cache.getByIndex(ie);
      var newMatch = MatchTranslator.shootingMatchFrom(oldMatch);
      save(newMatch);
      i += 1;
      if(i % 20 == 0) {
        print("[MatchDatabase] Migration: saved $i of $matchCount to database");
      }
    }
  }

  Query<DbShootingMatch> _buildQuery(List<MatchQueryElement> elements, {int? limit, int? offset}) {
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

    // Defaults
    MatchQueryElement? whereElement;
    Iterable<MatchQueryElement> filterElements = elements;

    if(nameQuery?.canWhere ?? false) {
      nameQuery!;

      // If we have a name query, prefer it if the query is longer than N characters,
      // otherwise use the date query if we have it.
      if(nameQuery.name.length >= 4 || dateQuery == null) {
        (whereElement, filterElements) = _buildElementLists(elements, nameQuery);
      }
      else if(dateQuery != null) {
        (whereElement, filterElements) = _buildElementLists(elements, dateQuery);
      }
    }
    else if(dateQuery != null) {
      // If we have no name query but we do have a date query, use it.
      (whereElement, filterElements) = _buildElementLists(elements, dateQuery);
    }

    Query<DbShootingMatch> query = matchDb.dbShootingMatchs.buildQuery(
      whereClauses: whereElement?.whereClauses ?? [],
      filter: filterElements.isEmpty ? null : FilterGroup.and([
        for(var f in filterElements)
          if(f.filterCondition != null)
            f.filterCondition!,
      ]),
      // TODO: decide by what we pass in
      // it's probably almost always going to be better to 'where' whatever we want to
      // sort by, and filter the rest? Unless the filter is specific enough to narrow it
      // down a lot, and that might

      // Sort by date desc, using where-sort if we're using the date index
      // or plain-old-sorting if not.
      sortBy: whereElement == dateQuery ? [] : [
        SortProperty(
          property: 'date',
          sort: Sort.desc,
        ),
      ],
      whereSort: whereElement == dateQuery ? Sort.desc : Sort.asc,
      limit: limit,
      offset: offset,
    );

    return query;
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