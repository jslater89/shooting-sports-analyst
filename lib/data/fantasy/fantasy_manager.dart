
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';

/// FantasyManager contains static methods for managing the creation and
/// editing of fantasy leagues.
class FantasyManager {
  static Future<League> createLeague(Sport sport, String name) async {

  }

  /// Create a season for a fantasy league and a given year, according to the
  /// league's settings.
  static Future<LeagueSeason> createSeason(League league, int year) async {

  }

  /// Create the [LeagueMonth] objects for a fantasy league season.
  static Future<List<LeagueMonth>> createSchedule(League league, LeagueSeason season) async {

  }
}
