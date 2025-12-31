import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';

extension MatchPrepDatabase on AnalystDatabase {
  Future<List<MatchPrep>> getMatchPreps() async {
    return isar.matchPreps.where().findAll();
  }

  List<MatchPrep> getMatchPrepsSync() {
    return isar.matchPreps.where().findAllSync();
  }
}