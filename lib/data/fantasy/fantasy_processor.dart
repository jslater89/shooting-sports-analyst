
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/fantasy.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("FantasyProcessor");

class FantasyProcessor {
  /// Process all active leagues.
  static Future<void> processLeagues(DateTime referenceDate, {ProgressCallback? progressCallback}) async {
    var db = AnalystDatabase();
    var leagues = await db.getActiveLeagues();
    for (var (index, league) in leagues.indexed) {
      await processLeague(league, referenceDate);
      await progressCallback?.call(index, leagues.length);
    }
  }

  /// Process a league.
  ///
  /// Processing is idempotent; if the operation completes successfully, future calls to [processLeague]
  /// will not duplicate work.
  static Future<bool> processLeague(League league, DateTime referenceDate) async {
    var season = await league.getCurrentSeason();

    var month = await season.getMonthByDate(referenceDate);
    if(month == null && referenceDate.isBefore(season.endDate)) {
      _log.w("No month in $referenceDate, but $league is still in season");
      return false;
    }
    else if(month != null && referenceDate.isAfter(season.endDate)) {
      // In this case, we process scores.
      _log.w("Found month $month for $referenceDate, but $league is already past season end");
    }
    else if(month == null && referenceDate.isAfter(season.endDate)) {
      _log.i("Season for $league has ended");
    }

    return processMonth(league, season, month!);
  }

  static Future<bool> endSeason(League league, LeagueSeason season) async {

    return true;
  }

  /// Process scores for a month.
  ///
  /// This method ends with a write transaction that carries out all the score updates.
  static Future<bool> processMonth(League league, LeagueSeason season, LeagueMonth month) async {
    return true;
  }
}
