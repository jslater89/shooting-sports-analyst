/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/matchups.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/standing.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

part 'league.g.dart';

enum MonthOfYear {
  january,
  february,
  march,
  april,
  may,
  june,
  july,
  august,
  september,
  october,
  november,
  december;

  int get monthNumber => index + 1;
}

@collection
class League with DbSportEntity {
  Id id = Isar.autoIncrement;

  String sportName;

  // #region Settings
  final rosterSlots = IsarLinks<RosterSlot>();

  /// The month of the year in which the season starts.
  @Enumerated(EnumType.ordinal)
  MonthOfYear startMonth = MonthOfYear.march;

  /// The month of the year after which the season ends.
  @Enumerated(EnumType.ordinal)
  MonthOfYear endMonth = MonthOfYear.october;

  /// The number of head-to-head matchups per month.
  int headToHeadPerMonth = 0;

  // TODO: all-play and head-to-head scoring/scheduling rules
  // I want to be able to capture a few things:
  // - a few different ways to distribute points for all play,
  //   like some variations of 'inverse place' or 'F1-style'
  // - a few different ways to schedule head-to-head matchups
  // - point values for head-to-head outcomes

  // #endregion Settings

  Future<List<RosterSlot>> getRosterSlots() async {
    if(!rosterSlots.isLoaded) {
      await rosterSlots.load();
    }
    return rosterSlots.toList();
  }

  /// Timestamp for league creation.
  DateTime creationDate;

  /// The current state of the league.
  @enumerated
  LeagueState state;

  /// The rating project whose matches are used by this league.
  final ratingProject = IsarLink<DbRatingProject>();

  final teams = IsarLinks<Team>();
  final currentSeason = IsarLink<LeagueSeason>();
  final seasons = IsarLinks<LeagueSeason>();

  /// The all-time standings for the league.
  ///
  /// This link will contain one entry for each team in the league.
  ///
  /// Note that this is _not_ backlinked to [LeagueStanding.league],
  /// because _all_ [LeagueStandings] belonging to this league will
  /// have a value for [LeagueStanding.league], and this is only the
  /// all-time standings per team.
  final allTimeStandings = IsarLinks<LeagueStanding>();

  Future<LeagueSeason> getCurrentSeason() async {
    if(!currentSeason.isLoaded) {
      await currentSeason.load();
    }
    return currentSeason.value!;
  }

  Future<List<LeagueSeason>> getSeasons() async {
    if(!seasons.isLoaded) {
      await seasons.load();
    }
    return seasons.toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  League({
    required this.sportName,
    required this.creationDate,
    this.state = LeagueState.offseason,
  });
}

enum LeagueState {
  /// The league is in its offseason, but may play another season
  /// in the future.
  offseason,

  /// The league is in its preseason; there is a current season, but it
  /// has not yet started.
  preseason,

  /// The league is currently in season; matches are being played.
  active,

  /// The league is finished; it is not expected to play another season.
  finished,
}

@collection
class LeagueSeason {
  Id id = Isar.autoIncrement;

  @Backlink(to: 'seasons')
  final league = IsarLink<League>();

  String name;
  DateTime startDate;
  DateTime endDate;

  /// The standings for this season.
  ///
  /// Loaded values will be unordered.
  final standings = IsarLinks<LeagueStanding>();

  /// The months in this season.
  ///
  /// Loaded values will be unordered. Use getMonths() to get a list of months in order.
  final months = IsarLinks<LeagueMonth>();

  Future<List<LeagueMonth>> getMonths() async {
    if(!months.isLoaded) {
      await months.load();
    }
    return months.toList()
      ..sort((a, b) => a.month.compareTo(b.month));
  }

  Future<LeagueMonth?> getMonthByDate(DateTime date) async {
    return months.filter()
      .startDateLessThan(date, include: true)
      .endDateGreaterThan(date, include: true)
      .findFirst();
  }

  Future<League> getLeague() async {
    if(!league.isLoaded) {
      await league.load();
    }
    return league.value!;
  }

  LeagueSeason({
    required this.name,
    required this.startDate,
    required this.endDate,
  });
}

@collection
class LeagueMonth {
  Id id = Isar.autoIncrement;

  @Backlink(to: 'months')
  final season = IsarLink<LeagueSeason>();

  /// The next month in the season.
  final nextMonth = IsarLink<LeagueMonth>();

  /// The previous month in the season.
  final previousMonth = IsarLink<LeagueMonth>();

  /// Whether the month has been processed at least once.
  ///
  /// Started may be false even if DateTime.now() is greater than
  /// [startDate], depending on the processor schedule.
  bool started = false;

  /// Whether the month has been processed at least once after
  /// [endDate]; if true, the [LeagueStanding] objects for this month
  /// should be finalized.
  ///
  /// Completed may be false even if DateTime.now() is greater than
  /// [endDate], depending on the processor schedule.
  bool completed = false;

  /// The calendar month corresponding to this league month. Only the year
  /// and month properties of this date are guaranteed to be valid.
  ///
  /// By convention, this is the midnight UTC on the first day of the month,
  /// but this is not enforced by the database and should not be relied on.
  ///
  /// Use [startDate] and [endDate] for guaranteed second-accurate times.
  DateTime month;

  /// The matchups for this month. Obtain rosters and teams by following
  /// the links in [Matchup].
  final IsarLinks<Matchup> matchups = IsarLinks<Matchup>();

  /// The all-play rosters for this month. Obtain teams by following
  /// the links in [MonthlyRoster].
  final IsarLinks<MonthlyRoster> allPlayRosters = IsarLinks<MonthlyRoster>();

  /// Every roster that is playing this month, in any format.
  final IsarLinks<MonthlyRoster> allRosters = IsarLinks<MonthlyRoster>();

  /// Monthly standings for this month.
  final IsarLinks<LeagueStanding> standings = IsarLinks<LeagueStanding>();

  DateTime get startDate => DateTime.utc(month.year, month.month);

  DateTime get endDate => DateTime.utc(month.year, month.month + 1, 23, 59, 59);

  Future<LeagueSeason> getSeason() async {
    if(!season.isLoaded) {
      await season.load();
    }
    return season.value!;
  }

  Future<League> getLeague() async {
    return getSeason().then((season) => season.getLeague());
  }

  LeagueMonth({
    required DateTime month,
  }) : month = DateTime.utc(month.year, month.month);
}
