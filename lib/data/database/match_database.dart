/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:isar/isar.dart';
import 'package:uspsa_result_viewer/data/database/schema/match.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/match/translator.dart';
import 'package:uspsa_result_viewer/util.dart';

class MatchDatabase {
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
  Future<List<DbShootingMatch>> query({String? name, DateTime? after, DateTime? before}) {
    // TODO: dynamic query, because the query builder syntax is too picky
    Query<DbShootingMatch> finalQuery;
    if(name != null) {
      var whereQuery = matchDb.dbShootingMatchs.where()
          .eventNamePartsElementStartsWith(name);

      if(before != null && after != null) {
        finalQuery = whereQuery.filter()
            .dateBetween(after, before)
            .sortByDateDesc()
            .build();
      }
      else if(before != null) {
        finalQuery = whereQuery.filter()
            .dateLessThan(before)
            .sortByDateDesc()
            .build();
      }
      else if(after != null) {
        finalQuery = whereQuery.filter()
            .dateGreaterThan(after)
            .sortByDateDesc()
            .build();
      }
      else {
        finalQuery = whereQuery.build();
      }
    }
    else if(after != null || before != null) {
      if(before != null && after != null) {
        finalQuery = matchDb.dbShootingMatchs.where(sort: Sort.desc).dateBetween(after, before).build();
      }
      else if(before != null) {
        finalQuery = matchDb.dbShootingMatchs.where(sort: Sort.desc).dateLessThan(before).build();
      }
      else { // (after != null)
        finalQuery = matchDb.dbShootingMatchs.where(sort: Sort.desc).dateGreaterThan(after!).build();
      }
    }
    else {
      finalQuery = matchDb.dbShootingMatchs.where(sort: Sort.desc).anyDate().build();
    }

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
}