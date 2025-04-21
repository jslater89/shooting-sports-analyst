/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/matchups.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

part 'league.g.dart';

@collection
class League with DbSportEntity {
  Id id = Isar.autoIncrement;

  String sportName;

  final rosterSlots = IsarLinks<RosterSlot>();

  String name;

  final teams = IsarLinks<Team>();

  League({
    required this.name,
    required this.sportName,
  });
}

@collection
class LeagueSeason {
  Id id = Isar.autoIncrement;

  final league = IsarLink<League>();

  String name;
  DateTime startDate;
  DateTime endDate;

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

  LeagueSeason({
    required this.name,
    required this.startDate,
    required this.endDate,
  });
}

@collection
class LeagueMonth {
  Id id = Isar.autoIncrement;

  final season = IsarLink<LeagueSeason>();

  /// The calendar month corresponding to this league month. Only the year
  /// and month properties of this date are guaranteed to be valid.
  ///
  /// By convention, this is the midnight UTC on the first day of the month,
  /// but this is not enforced by the database and should not be relied on.
  DateTime month;

  /// The matchups for this month. Obtain rosters and standings by following
  /// the links in [Matchup].
  final IsarLinks<Matchup> matchups = IsarLinks<Matchup>();

  /// The all-play rosters for this month. Obtain standings by following
  /// the links in [MonthlyRoster].
  final IsarLinks<MonthlyRoster> allPlayRosters = IsarLinks<MonthlyRoster>();

  @ignore
  DateTime get startDate => DateTime.utc(month.year, month.month);

  @ignore
  DateTime get endDate => DateTime.utc(month.year, month.month + 1);

  LeagueMonth({
    required DateTime month,
  }) : month = DateTime.utc(month.year, month.month);
}
