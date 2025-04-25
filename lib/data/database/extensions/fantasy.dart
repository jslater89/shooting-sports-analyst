import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';

extension FantasyDatabase on AnalystDatabase {
  Future<League?> getLeague(Id leagueId) async {
    return isar.leagues.get(leagueId);
  }

  /// Get all leagues that are currently active, i.e. those that need to be
  /// processed.
  Future<List<League>> getActiveLeagues() async {
    return isar.leagues.filter().stateEqualTo(LeagueState.active).findAll();
  }
}
