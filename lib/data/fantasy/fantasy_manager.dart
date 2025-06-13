
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// FantasyManager contains static methods for managing the creation and
/// editing of fantasy leagues.
class FantasyManager {
  static Future<League> createLeague({
    required Sport sport,
    required String name,
    MonthOfYear startMonth = MonthOfYear.march,
    MonthOfYear endMonth = MonthOfYear.october,
    int headToHeadPerMonth = 0,
  }) async {
    throw UnimplementedError();
  }

  /// Create a season for a fantasy league and a given year, according to the
  /// league's settings.
  static Future<LeagueSeason> createSeason(League league, int year) async {
    throw UnimplementedError();
  }

  /// Create the [LeagueMonth] objects for a fantasy league season.
  static Future<List<LeagueMonth>> createSchedule(League league, LeagueSeason season) async {
    throw UnimplementedError();
  }
}
