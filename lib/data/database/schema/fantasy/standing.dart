/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/matchups.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'standing.g.dart';

/// A LeagueStanding contains a team's standings in a league.
///
/// It may be a monthly standing, a season standing, or an all-time standing;
/// consult [type] to determine which.
///
/// All standings must have a [team] and [league]. They may optionally have a [season]
/// or a [month], but not both. (A season standing must have a null month, and a monthly
/// standing must have a null season.)
///
/// The constructor will throw [ArgumentError] if the arguments are inconsistent with the rules.
@collection
class LeagueStanding {
  /// Create the ID for the league standing for the team with [teamId] in the [league] with [leagueId],
  /// optionally at [season] with [seasonId], or [month] with [monthId].
  ///
  /// Throws [ArgumentError] if the arguments are inconsistent with the rules.
  static Id idForIds({required int teamId, required int leagueId, int? seasonId, int? monthId, required LeagueStandingType type}) {
    if(type == LeagueStandingType.month && monthId == null) {
      throw ArgumentError("monthId is required for monthly standings");
    }
    if(type == LeagueStandingType.season && seasonId == null) {
      throw ArgumentError("seasonId is required for season standings");
    }
    if(type == LeagueStandingType.allTime && (seasonId != null || monthId != null)) {
      throw ArgumentError("allTime standings cannot have a season or month");
    }
    if(type == LeagueStandingType.month && seasonId != null) {
      throw ArgumentError("month standings cannot have a season");
    }
    if(type == LeagueStandingType.season && monthId != null) {
      throw ArgumentError("season standings cannot have a month");
    }

    List<int> ids = [teamId.stableHash, leagueId.stableHash];
    if(seasonId != null) {
      ids.add(seasonId.stableHash);
    }
    if(monthId != null) {
      ids.add(monthId.stableHash);
    }
    return combineHashList(ids);
  }

  /// Create the ID for the league standing for [team] in [league], optionally at [season] or [month].
  static Id idFor({required Team team, required League league, LeagueSeason? season, LeagueMonth? month, required LeagueStandingType type}) {
    if(type == LeagueStandingType.month && month == null) {
      throw ArgumentError("month is required for monthly standings");
    }
    if(type == LeagueStandingType.season && season == null) {
      throw ArgumentError("season is required for season standings");
    }
    if(type == LeagueStandingType.allTime && (season != null || month != null)) {
      throw ArgumentError("allTime standings cannot have a season or month");
    }
    if(type == LeagueStandingType.month && season != null) {
      throw ArgumentError("month standings cannot have a season");
    }
    if(type == LeagueStandingType.season && month != null) {
      throw ArgumentError("season standings cannot have a month");
    }

    List<int> ids = [team.id.stableHash, league.id.stableHash];
    if(season != null && type == LeagueStandingType.season) {
      ids.add(season.id.stableHash);
    }
    if(month != null && type == LeagueStandingType.month) {
      ids.add(month.id.stableHash);
    }
    return combineHashList(ids);
  }

  Id get id => idForIds(teamId: teamId, leagueId: leagueId, seasonId: seasonId, monthId: monthId, type: type);

  int teamId;
  int leagueId;
  int? seasonId;
  int? monthId;

  /// Whether the standings are final.
  ///
  /// If false, the month, season, or league may still be in play.
  bool finalized;

  /// The team that this standing belongs to.
  final team = IsarLink<Team>();

  /// The league that this standing belongs to.
  final league = IsarLink<League>();

  /// The season that this standing belongs to, which will be null unless
  /// [type] is [LeagueStandingType.season].
  @Backlink(to: 'standings')
  final season = IsarLink<LeagueSeason>();

  /// The month that this standing belongs to, which will be null unless
  /// [type] is [LeagueStandingType.month].
  @Backlink(to: 'standings')
  final month = IsarLink<LeagueMonth>();

  Future<MonthlyRoster?> getRoster() async {
    if(type == LeagueStandingType.month) {
      if(!month.isLoaded) {
        await month.load();
      }
      return month.value?.allPlayRosters.firstWhereOrNull((roster) => roster.teamId == teamId);
    }
    return null;
  }

  final allPlayWins = IsarLinks<MonthlyRoster>();
  final allPlayLosses = IsarLinks<MonthlyRoster>();
  final allPlayTies = IsarLinks<MonthlyRoster>();

  @enumerated
  LeagueStandingType type;

  /// The total points scored by the team in the league, according to the league
  /// scoring rules, over the time period covered by this standing. Note that this
  /// is not the same as fantasy points—league points are assigned based on all-play
  /// rank and head-to-head results at the end of a month, whereas fantasy points
  /// are what determine all-play rank and head-to-head results within a month.
  double get leaguePointsFor => allPlayLeaguePoints + headToHeadLeaguePoints;

  /// The points the team scored for its all-play rank.
  double allPlayLeaguePoints;

  /// The points the team scored for its head-to-head result(s).
  double headToHeadLeaguePoints;

  /// How many teams the team has beaten in all-play, over the time period covered by this standing.
  int allPlayWinCount;

  /// How many teams the team has lost to in all-play, over the time period covered by this standing.
  int allPlayLossCount;

  /// How many teams the team has tied in all-play, over the time period covered by this standing.
  int allPlayTieCount;

  /// The team's rank in the monthly all-play standings (i.e. 1 for 1st, 2 for 2nd, etc.).
  ///
  /// If this is not a monthly standing, this will be zero.
  int allPlayRank;

  /// The team's head-to-head wins.
  final headToHeadWins = IsarLinks<Matchup>();

  /// The team's head-to-head losses.
  final headToHeadLosses = IsarLinks<Matchup>();

  /// The team's head-to-head ties.
  final headToHeadTies = IsarLinks<Matchup>();

  /// How many teams the team has beaten in head-to-head, over the time period covered by this standing.
  int headToHeadWinCount;

  /// How many teams the team has lost to in head-to-head, over the time period covered by this standing.
  int headToHeadLossCount;

  /// How many teams the team has tied in head-to-head, over the time period covered by this standing.
  int headToHeadTieCount;

  /// The team's fantasy points scored in the league, over the time period covered by this standing.
  double fantasyPointsFor;

  /// The team's fantasy points scored against in head-to-head, over the time period covered by this standing.
  double headToHeadFantasyPointsAgainst;

  LeagueStanding({
    required this.teamId,
    required this.leagueId,
    required this.type,
    this.seasonId,
    this.monthId,
    this.allPlayWinCount = 0,
    this.allPlayLossCount = 0,
    this.allPlayTieCount = 0,
    this.headToHeadWinCount = 0,
    this.headToHeadLossCount = 0,
    this.headToHeadTieCount = 0,
    this.fantasyPointsFor = 0,
    this.headToHeadFantasyPointsAgainst = 0,
    this.allPlayLeaguePoints = 0,
    this.headToHeadLeaguePoints = 0,
    this.allPlayRank = 0,
    this.finalized = false,
  }) {
    if(type == LeagueStandingType.month && monthId == null) {
      throw ArgumentError("monthId is required for monthly standings");
    }
    if(type == LeagueStandingType.season && seasonId == null) {
      throw ArgumentError("seasonId is required for season standings");
    }
    if(type == LeagueStandingType.allTime && (seasonId != null || monthId != null)) {
      throw ArgumentError("allTime standings cannot have a season or month");
    }
    if(type == LeagueStandingType.month && seasonId != null) {
      throw ArgumentError("month standings cannot have a season");
    }
    if(type == LeagueStandingType.season && monthId != null) {
      throw ArgumentError("season standings cannot have a month");
    }
  }
}

enum LeagueStandingType {
  month,
  season,
  allTime,
}
