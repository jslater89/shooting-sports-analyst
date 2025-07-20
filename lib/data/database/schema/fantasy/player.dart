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
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'player.g.dart';

final _log = SSALogger("FantasyPlayer");

@collection
class FantasyPlayer with DbSportEntity, DbDivisionEntity {
  String sportName = "";
  String divisionName = "";

  Id id = Isar.autoIncrement;

  /// The member number of the player.
  ///
  /// Used to identify the player in the event
  /// of a recalculation of the league's project
  /// which results in the target rating being
  /// deleted and recreated, or a member number
  /// mapping which does the same.
  String memberNumber = "";

  /// The rating that this player is based upon.
  final rating = IsarLink<DbShooterRating>();

  Future<DbShooterRating?> getRatingOrNull() async {
    if(!rating.isLoaded) {
      await rating.load();
    }
    return rating.value;
  }

  Future<DbShooterRating> getRating() async {
    if(!rating.isLoaded) {
      await rating.load();
    }
    return rating.value!;
  }

  Future<bool> resolveRating() async {
    var rating = await getRatingOrNull();
    if(rating != null) {
      return true;
    }

    var project = await getProject();
    var groupRes = await project.groupForDivision(division);
    if(groupRes.isErr()) {
      _log.e("Failed to get group for $this: ${groupRes.unwrapErr()}");
      return false;
    }
    var group = groupRes.unwrap();
    if(group == null) {
      _log.e("No group found for $this");
      return false;
    }
    rating = await AnalystDatabase().maybeKnownShooter(project: project, group: group, memberNumber: memberNumber);
    if(rating == null) {
      _log.e("No rating found for $this");
      return false;
    }
    this.rating.value = rating;
    await AnalystDatabase().isar.writeTxn(() async {
      await this.rating.save();
    });
    return true;
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
    Set<String> matchIds = events.map((e) => e.matchId).toSet();
    var matches = await db.getMatchesByAnySourceIds(matchIds.toList());
    return matches.map((m) => m.hydrate(useCache: true).unwrap()).toList();
  }

  /// The teams that this player is on, across all leagues.
  final teams = IsarLinks<Team>();

  /// The leagues in which this player is on a team.
  final leagues = IsarLinks<League>();
}

@collection
class PlayerMonthlyPerformance {
  static Id idFromDbEntities({
    required FantasyPlayer player,
    required LeagueMonth month,
  }) {
    return combineHashes(player.id.stableHash, month.id.stableHash);
  }

  static Id idFromEntityIds({
    required int playerId,
    required int monthId,
  }) {
    return combineHashes(playerId.stableHash, monthId.stableHash);
  }

  Id get id => idFromEntityIds(playerId: playerId, monthId: monthId);

  final player = IsarLink<FantasyPlayer>();
  final month = IsarLink<LeagueMonth>();

  @Index()
  int playerId;
  @Index()
  int monthId;

  /// All matches they shot this month.
  List<MatchPerformance> matchPerformances = [];

  /// Best performance (the one used for scoring), or null
  /// if they didn't shoot any matches this month.
  MatchPerformance? bestPerformance;

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

  static Future<PlayerMonthlyPerformance?> getById(Id id) async {
    var db = AnalystDatabase();
    var performance = await db.isar.playerMonthlyPerformances.get(id);
    return performance;
  }

  static Future<PlayerMonthlyPerformance?> getByEntityIds({
    required int playerId,
    required int monthId,
  }) async {
    var id = idFromEntityIds(playerId: playerId, monthId: monthId);
    return getById(id);
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
