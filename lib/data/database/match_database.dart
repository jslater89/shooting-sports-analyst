/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:isar/isar.dart';
import 'package:uspsa_result_viewer/data/database/schema/match.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';

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
      var oldMatch = await matchDb.dbShootingMatchs.getByIndex("sourceIds", dbMatch.sourceIds);
      if(oldMatch != null) {
        dbMatch.id = oldMatch.id;
        await matchDb.dbShootingMatchs.put(dbMatch);
      }
      else {
        dbMatch.id = await matchDb.dbShootingMatchs.put(dbMatch);
      }
      return dbMatch;
    });
    return dbMatch;
  }
}