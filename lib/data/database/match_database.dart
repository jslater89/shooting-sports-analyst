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

  Future<DbShootingMatch> save(ShootingMatch match) async {
    var dbMatch = DbShootingMatch.from(match);
    dbMatch = await matchDb.writeTxn<DbShootingMatch>(() async {
      await matchDb.dbShootingMatchs.put(dbMatch);
      return dbMatch;
    });
    return dbMatch;
  }
}