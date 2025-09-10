/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/fantasy_user.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// FantasyManager contains static methods for managing the creation and
/// editing of fantasy leagues.
class FantasyManager {
  static Future<League> createLeague({
    required Sport sport,
    required String name,
    required FantasyUser commissioner,
    MonthOfYear startMonth = MonthOfYear.march,
    MonthOfYear endMonth = MonthOfYear.october,
    bool startImmediately = false,
    int headToHeadPerMonth = 0,
    LeagueScoringSettings? scoringSettings,
    int maximumTeams = 8,
  }) async {
    var league = League(
      sportName: sport.name,
      name: name,
      creationDate: DateTime.now(),
      maximumTeams: maximumTeams,
      scoringSettings: scoringSettings ?? LeagueScoringSettings.createLinear(
        teamCount: 8,
        headToHeadType: HeadToHeadMatchupType.roundRobin,
        headToHeadFraction: 0.5,
      )
    );
    var db = AnalystDatabase();
    var startDate = DateTime(DateTime.now().year, startMonth.monthNumber, 1);
    var endDate = DateTime(DateTime.now().year, endMonth.monthNumber + 1, 0, 23, 59, 59);

    if(!startImmediately && startDate.isAfter(DateTime.now())) {
      startDate = DateTime(DateTime.now().year + 1, startMonth.monthNumber, 1);
      endDate = DateTime(DateTime.now().year + 1, endMonth.monthNumber + 1, 0, 23, 59, 59);
    }
    else if(startImmediately && startDate.isAfter(DateTime.now())) {
      startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
    }

    var season = LeagueSeason(
      startDate: startDate,
      endDate: endDate,
    );

    var months = <LeagueMonth>[];
    for(int monthNumber = startMonth.monthNumber; monthNumber <= endMonth.monthNumber; monthNumber++) {
      months.add(LeagueMonth(
        month: DateTime(startDate.year, monthNumber, 1),
      ));
    }
    await db.isar.writeTxn(() async {
      await db.isar.leagues.put(league);
    });
    return league;
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
