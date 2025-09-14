/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'player.g.dart';

final _log = SSALogger("FantasyPlayer");

@collection
class FantasyPlayer with DbSportEntity {
  FantasyPlayer();

  FantasyPlayer.fromRating(DbShooterRating rating, {String? groupUuidOverride}) :
    sportName = rating.sportName,
    name = rating.name,
    groupUuid = groupUuidOverride ?? rating.group.value?.uuid ?? "",
    memberNumber = rating.originalMemberNumber,
    projectId = rating.project.value!.id {
    this.rating.value = rating;
  }

  String sportName = "";
  int projectId = -1;
  String groupUuid = "";

  /// A synthetic ID for the player, combining sport name, division name, member number, and project.
  ///
  /// By convention, it is best to use originalMemberNumber instead of memberNumber for this ID;
  /// memberNumber is likely to change over the course of a player's career (A/TY/FY forms, lifetime, etc.),
  /// whereas the first number they appear with is likely to remain the same.
  Id get id => combineHashList([
    sportName.stableHash,
    groupUuid.stableHash,
    memberNumber.stableHash,
    projectId.stableHash,
  ]);

  static Id idFromEntities({
    required Sport sport,
    required RatingGroup group,
    required Shooter shooter,
    required DbRatingProject project,
  }) {
    return combineHashList([
      sport.name.stableHash,
      group.uuid.stableHash,
      shooter.originalMemberNumber.stableHash,
      project.id.stableHash,
    ]);
  }

  static Id idFromEntityIdentifiers({
    required String sportName,
    required String groupUuid,
    required String memberNumber,
    required int projectId,
  }) {
    return combineHashList([
      sportName.stableHash,
      groupUuid.stableHash,
      memberNumber.stableHash,
      projectId.stableHash,
    ]);
  }

  /// A display name for the player.
  String name = "";

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

  /// Match performances for this player.
  final matchPerformances = IsarLinks<PlayerMatchPerformance>();

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
    var group = await project.sport.builtinRatingGroupsProvider?.getGroup(groupUuid);
    if(group == null) {
      _log.e("No group found for $this");
      return false;
    }
    rating = await AnalystDatabase().maybeKnownShooter(project: project, group: group, memberNumber: memberNumber, useCache: true);
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
  final matchPerformances = IsarLinks<PlayerMatchPerformance>();

  /// Best performance (the one used for scoring), or null
  /// if they didn't shoot any matches this month.
  final bestPerformance = IsarLink<PlayerMatchPerformance>();

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

/// A match performance for a player. It contains their fantasy-relevant stats
/// by scoring category, and can be used to calculate final fantasy scores
/// based on those stats and provided weights.
@collection
class PlayerMatchPerformance {

  Id get id => combineHashList([playerId.stableHash, projectId.stableHash, groupUuid.stableHash, matchId.stableHash]);

  @Backlink(to: 'matchPerformances')
  final player = IsarLink<FantasyPlayer>();

  @Index()
  int get playerId => player.value?.id ?? -1;

  @Index(composite: [CompositeIndex('groupUuid')])
  int get projectId => player.value?.projectId ?? -1;

  @Index()
  String matchId = "";
  String matchName = "";

  @Index()
  DateTime matchDate = DateTime(0, 0, 0);
  int stageCount = 0;

  // The rating group against which these stats were calculated.
  @Index()
  String get groupUuid => player.value?.groupUuid ?? "";

  // Their fantasy stats by scoring category, in DB-friendly format.
  DbFantasyStats dbScores = DbFantasyStats();

  /// A convenience container for calculated points for this performance.
  /// Not persisted, because it will vary from league to league; use it for
  /// intermediate storage when operating on a list of performances.
  @ignore
  double points = 0;

  FantasyScore getScore({required FantasyScoringCalculator calculator, FantasyPointsAvailable? weights}) {
    return calculator.calculateFantasyScore(stats: dbScores, pointsAvailable: weights ?? FantasyScoringCategory.defaultCategoryPoints);
  }

  PlayerMatchPerformance({
    this.matchId = "",
    this.matchName = "",
    this.stageCount = 0,
    required this.dbScores,
  }) : matchDate = DateTime(0, 0, 0);

  PlayerMatchPerformance.create({
    required this.matchId,
    required this.matchName,
    required this.matchDate,
    required this.stageCount,
    required this.dbScores,
  });

  PlayerMatchPerformance.fromEntities({
    required FantasyPlayer player,
    required MatchPointer match,
    required DbFantasyStats stats,
  }) {
    this.player.value = player;
    this.matchId = match.sourceIds.first;
    this.matchName = match.name;
    this.matchDate = match.date!;
    this.stageCount = stats.stageCount;
    this.dbScores = stats;
  }
}

/// A fantasy stat for a player, in DB-friendly format.
///
/// [rawScore] is the raw score for the stat.
@embedded
class DbFantasyStats {
  double finishPercentage = 0;
  int stageWins = 0;
  int stageTop10Percents = 0;
  int stageTop25Percents = 0;
  int rawTimeWins = 0;
  int rawTimeTop10Percents = 0;
  int rawTimeTop25Percents = 0;
  int accuracyWins = 0;
  int accuracyTop10Percents = 0;
  int accuracyTop25Percents = 0;
  int penalties = 0;
  double divisionParticipationPenalty = 0;

  int stageCount = 0;

  DbFantasyStats();

  DbFantasyStats.create({
    required this.finishPercentage,
    required this.stageWins,
    required this.stageTop10Percents,
    required this.stageTop25Percents,
    required this.rawTimeWins,
    required this.rawTimeTop10Percents,
    required this.rawTimeTop25Percents,
    required this.accuracyWins,
    required this.accuracyTop10Percents,
    required this.accuracyTop25Percents,
    required this.penalties,
    required this.divisionParticipationPenalty,
    required this.stageCount,
  });
}
