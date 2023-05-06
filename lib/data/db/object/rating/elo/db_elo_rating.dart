import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_event.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_project.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

@Entity(
  tableName: "eloRatings",
  withoutRowid: true,
  primaryKeys: ['project', 'raterGroup', 'memberNumber'],
)
class DbEloRating extends DbShooterRating {
  double rating;
  double variance;

  DbEloRating({
    required this.rating,
    required this.variance,

    required super.lastClassification,
    required super.lastSeen,
    required super.project,

    required super.firstName,
    required super.lastName,
    required super.memberNumber,
    required super.originalMemberNumber,
    required super.division,
    required super.classification,
    required super.powerFactor,
    required super.raterGroup,
  });

  static DbEloRating convert(EloShooterRating rating, DbRatingProject project, RaterGroup group) {
    var dbEloRating = DbEloRating(
      rating: rating.rating,
      variance: rating.variance,
      lastClassification: rating.lastClassification,
      lastSeen: rating.lastSeen,
      project: project.id!,
      firstName: rating.firstName,
      lastName: rating.lastName,
      memberNumber: rating.memberNumber,
      originalMemberNumber: rating.originalMemberNumber,
      division: rating.division!,
      classification: rating.classification!,
      powerFactor: rating.powerFactor!,
      raterGroup: group,
    );

    return dbEloRating;
  }

  static Future<DbEloRating> serialize(EloShooterRating rating, DbRatingProject project, RaterGroup group, ProjectStore store) async {
    var dbEloRating = convert(rating, project, group);
    
    await store.eloRatings.saveRating(dbEloRating);
    return dbEloRating;
  }

  @override
  Future<ShooterRating> deserialize(List<DbRatingEvent> events, List<String> memberNumbers) async {
    var rating = EloShooterRating.fromDb(this);

    var cache = MatchCache();
    var event = events.first;
    var byStage = event.stageId >= 0;

    for(var event in events) {
      late RelativeScore score;

      var match = await cache.getMatchImmediate(event.matchId);
      match!;

      var shooters = match.filterShooters(
        divisions: raterGroup.divisions,
        allowReentries: false,
      );

      var shooter = shooters.firstWhere((s) => memberNumbers.contains(s.memberNumber));

      // if this is a by-stage rating, get the stage score.
      if(byStage) {
        var stage = match.stages[event.stageId - 1];
        var scores = match.getScores(shooters: shooters, stages: [stage]);
        score = scores.firstWhere((e) => e.shooter == shooter).stageScores[stage]!;
      }
      else {
        var scores = match.getScores(shooters: shooters);
        score = scores.firstWhere((e) => e.shooter == shooter).total;
      }

      rating.ratingEvents.addAll(events.map((e) => e.deserialize(match, score)));
    }

    return rating;
  }
}

@dao
abstract class EloRatingDao {
  @Query("SELECT * FROM eloRatings WHERE project = :projectId AND raterGroup = :group")
  Future<List<DbEloRating>> ratingsForGroup(int projectId, RaterGroup group);

  @Query("SELECT * FROM eloRatings WHERE project = :projectId AND raterGroup = :group AND memberNumber = :memberNumber")
  Future<DbEloRating?> ratingForMember(int projectId, RaterGroup group, String memberNumber);

  @Query("SELECT * FROM eloRatingEvents WHERE projectId = :projectId AND raterGroup = :group AND memberNumber = :memberNumber")
  Future<List<DbEloEvent>> eventsForMember(int projectId, RaterGroup group, String memberNumber);

  @insert
  Future<int> saveRating(DbEloRating rating);

  @insert
  Future<void> saveRatings(List<DbEloRating> ratings);

  @insert
  Future<int> saveEvent(DbEloEvent event);

  @insert
  Future<void> saveEvents(List<DbEloEvent> events);
}


@Entity(
  tableName: "eloRatingEvents",
  primaryKeys: ['project', 'raterGroup', 'memberNumber', 'matchId', 'stageId'],
  withoutRowid: true,
)
class DbEloEvent extends DbRatingEvent {
  double ratingChange;
  double oldRating;
  double baseK;
  double effectiveK;
  double error;

  DbEloEvent({
    required this.ratingChange,
    required this.oldRating,
    required this.baseK,
    required this.effectiveK,
    required this.error,

    required super.projectId,
    required super.raterGroup,
    required super.memberNumber,
    required super.matchId,
    super.stageId,
    required super.infoKeys,
    required super.infoValues,
  });

  static List<DbEloEvent> fromRating(EloShooterRating rating, DbRatingProject project, RaterGroup group, Map<PracticalMatch, String> matchesToDbIds) {
    var events = <DbEloEvent>[];
    for(var event in rating.ratingEvents) {
      event as EloRatingEvent;

      events.add(
        DbEloEvent(
          projectId: project.id!,
          raterGroup: group,
          memberNumber: rating.memberNumber,
          matchId: matchesToDbIds[event.match]!,
          stageId: event.stage?.internalId ?? -1,
          infoKeys: event.info.keys.join(DbRatingEvent.separator),
          infoValues: event.info.values.join(DbRatingEvent.separator),

          baseK: event.baseK,
          effectiveK: event.effectiveK,
          oldRating: event.oldRating,
          ratingChange: event.ratingChange,
          error: event.error,
        )
      );
    }

    return events;
  }

  @override
  RatingEvent deserialize(PracticalMatch match, RelativeScore score) {
    var event = EloRatingEvent(
      oldRating: oldRating,
      match: match,
      score: score,
      ratingChange: ratingChange,
      baseK: baseK,
      effectiveK: effectiveK,
      backRatingError: 0,
    );

    return event;
  }
}