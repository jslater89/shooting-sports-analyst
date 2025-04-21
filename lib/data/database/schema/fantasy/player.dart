/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'player.g.dart';

@collection
class FantasyPlayer {
  Id id = Isar.autoIncrement;

  /// The rating that this player is based upon.
  final rating = IsarLink<DbShooterRating>();

  Future<DbShooterRating> getRating() async {
    if(!rating.isLoaded) {
      await rating.load();
    }
    return rating.value!;
  }

  /// The project that hosts this player's rating.
  Future<DbRatingProject> getProject() async {
    var r = await getRating();
    if(!r.project.isLoaded) {
      await r.project.load();
    }
    return r.project.value!;
  }

  /// Get all matches for this player in a given league month.
  Future<List<ShootingMatch>> getMatches(LeagueMonth month) async {
    var r = await getRating();
    var db = AnalystDatabase();
    var events = await db.getRatingEventsFor(
      r,
      after: month.startDate,
      before: month.endDate,
    );
    var matches = await db.getMatchesByAnySourceIds(events.map((e) => e.matchId).toList());
    return matches.map((m) => m.hydrate(useCache: true).unwrap()).toList();
  }

  /// The teams that this player is on, across all leagues.
  final teams = IsarLinks<Team>();

  /// The leagues in which this player is on a team.
  final leagues = IsarLinks<League>();
}

@collection
class PlayerMonthlyPerformance {
  Id get id => combineHashes(playerId.stableHash, monthId.stableHash);

  final player = IsarLink<FantasyPlayer>();
  final month = IsarLink<LeagueMonth>();

  @Index()
  int playerId;
  @Index()
  int monthId;

  // All matches they shot this month
  List<MatchPerformance> matchPerformances = [];

  // Best performance (the one used for scoring), or null
  // if they didn't shoot any matches this month
  MatchPerformance? bestPerformance;

  // Which rosters used this player this month
  final usedInRosters = IsarLinks<MonthlyRoster>();

  PlayerMonthlyPerformance({
    required this.playerId,
    required this.monthId,
  });

  factory PlayerMonthlyPerformance.fromDbEntities({
    required FantasyPlayer player,
    required LeagueMonth month,
  }) {
    var result = PlayerMonthlyPerformance(
      playerId: player.id,
      monthId: month.id,
    );
    result.player.value = player;
    result.month.value = month;
    return result;
  }
}

@embedded
class MatchPerformance {
  String matchId;
  String matchName;
  DateTime matchDate;

  // The division they shot
  String divisionName;

  // Their raw scores by category
  List<DbFantasyScore> dbScores;

  Map<String, List<FantasyScore>> getScores() {
    return Map.fromEntries(dbScores.map((s) => MapEntry(s.calculatorType, s.scores)));
  }

  MatchPerformance({
    this.matchId = "",
    this.matchName = "",
    this.divisionName = "",
    this.dbScores = const [],
  }) : matchDate = DateTime(0, 0, 0);

  MatchPerformance.create({
    required this.matchId,
    required this.matchName,
    required this.matchDate,
    required this.divisionName,
    required this.dbScores,
  });
}

@embedded
class DbFantasyScore {
  String calculatorType;
  List<String> rawScores;

  @ignore
  List<FantasyScore> get scores {
    return rawScores.map((s) => FantasyScore.fromJson(s)).toList();
  }

  DbFantasyScore({
    this.calculatorType = "",
    this.rawScores = const [],
  });

  DbFantasyScore.create({
    required this.calculatorType,
    required this.rawScores,
  });
}
