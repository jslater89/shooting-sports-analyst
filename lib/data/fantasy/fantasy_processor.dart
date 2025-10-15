/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/fantasy.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("FantasyProcessor");

/// FantasyProcessor contains methods for processing active fantasy leagues.
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
  /// Processing is idempotent. If the operation completes successfully, future calls to [processLeague]
  /// will not duplicate work. If the operation fails, partial work will not be committed to the database.
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

    // TODO: handle processing scores for next month in here?
    // Alternate option: in whatever calls this, track the current date and the last-processed date,
    // and if it crosses a month boundary, call this with both last-day-of-month and current date.
  }

  /// End a season.
  static Future<bool> endSeason(League league, LeagueSeason season) async {

    return true;
  }

  /// Process scores for a month.
  ///
  /// This method ends with a write transaction that carries out all the score updates.
  ///
  /// Returns true for success, false for failure.
  static Future<bool> processMonth(League league, LeagueSeason season, LeagueMonth month, {bool monthEnding = false}) async {
    var db = AnalystDatabase();

    // 1. Get matches from the league's project occurring during the month.

    // If there are new results, we'll process scores. Otherwise, we short circuit.
    bool hasNewResults = false;

    var project = await league.getProject();
    List<MatchPointer> newMatches = [];
    for(var p in project.matchPointers.reversed) {
      if(p.date == null) {
        _log.w("Match pointer ${p.sourceIds} has no date");
        continue;
      }

      if(p.date!.isAfter(month.startDateMinusOne) && p.date!.isBefore(month.endDatePlusOne)) {
        if(!month.matchPointers.contains(p)) {
          hasNewResults = true;
          newMatches.add(p);
        }
      }
    }

    if(!hasNewResults) {
      _log.i("No new results for $month");
      return true;
    }

    // 2. Get the league's active rosters from the monthly matchups.
    Map<Id, MonthlyRoster> rosters = {};
    for(var roster in await month.getAllPlayRosters()) {
      rosters[roster.id] = roster;
    }

    for(var matchup in await month.getMatchups()) {
      var home = await matchup.getHomeRoster();
      var away = await matchup.getAwayRoster();
      rosters[home.id] = home;
      rosters[away.id] = away;
    }

    // 2.1. For each roster, verify that the players have a valid rating link, and if not,
    // attempt to find the correct rating and fix the link.
    for(var roster in rosters.values) {
      var players = await roster.getPlayers();
      for(var player in players) {
        var rating = await player.getRatingOrNull();
        if(rating == null) {
          var success = await player.resolveRating();
          if(!success) {
            _log.e("Failed to resolve rating for $player");
          }
        }
      }
    }

    // 3. For each new match, calculate fantasy points.

    // 4. For each roster, check its players' monthly performances and update the best performance.

    // 5. Update monthly standings.

    // 6. Handle month-end operations, finalizing monthly scores/standings and updating season standings.
    if(monthEnding) {

    }

    return true;
  }
}
