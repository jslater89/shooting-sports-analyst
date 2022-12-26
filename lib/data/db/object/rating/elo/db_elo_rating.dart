import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_event.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_project.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

@Entity(
  tableName: "eloRatings",
  withoutRowid: true,
  primaryKeys: ['project', 'group', 'memberNumber'],
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
    required super.group,
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
      group: group,
    );

    return dbEloRating;
  }

  static Future<DbEloRating> serialize(EloShooterRating rating, DbRatingProject project, RaterGroup group, ProjectStore store) async {
    var dbEloRating = convert(rating, project, group);
    
    await store.eloRatings.saveRating(dbEloRating);
    return dbEloRating;
  }
}

@dao
abstract class EloRatingDao {
  @Query("SELECT * FROM eloRatings WHERE project = :projectId AND group = :groupIndex")
  Future<List<DbEloRating>> ratingsForGroup(int projectId, int groupIndex);

  @Query("SELECT * FROM eloRatings WHERE project = :projectId AND group = :groupIndex AND memberNumber = :memberNumber")
  Future<DbEloRating?> ratingForMember(int projectId, int groupIndex, String memberNumber);

  @Query("SELECT * FROM eloRatingEvents WHERE project = :projectId AND group = :groupIndex AND memberNumber = :memberNumber")
  Future<List<DbEloEvent>> eventsForMember(int projectId, int groupIndex, String memberNumber);

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
  primaryKeys: ['project', 'group', 'memberNumber', 'matchId', 'stageId'],
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
    required super.group,
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
          group: group,
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
}