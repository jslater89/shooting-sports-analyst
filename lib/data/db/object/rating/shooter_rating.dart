
import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/elo/db_elo_rating.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_project.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_types.dart';
import 'package:uspsa_result_viewer/data/db/object/match/shooter.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

@Entity(tableName: "shooterRatings")
class DbShooterRating extends DbShooter {

  int project;
  RaterGroup group;
  RatingType ratingSystem;

  Classification lastClassification;
  DateTime lastSeen;

  DbShooterRating({
    required this.ratingSystem,
    required this.lastClassification,
    required this.lastSeen,
    required this.project,
    required this.group,

    super.id,
    super.entryNumber = 0, // entry number not needed for shooter ratings
    required super.matchId,
    required super.firstName,
    required super.lastName,
    required super.memberNumber,
    required super.originalMemberNumber,
    required super.reentry,
    required super.dq,
    required super.division,
    required super.classification,
    required super.powerFactor
  });

  // serialize/deserialize: 'is' checks for serializing, use ratingSystem for
  // deserializing, delegate to the classes that know how to handle it.
  static Future<DbShooterRating> serialize(ShooterRating rating, DbRatingProject project, RaterGroup group, Map<PracticalMatch, String> matchesToDbIds, ProjectStore store) async {
    RatingType ratingSystem;
    if(rating is EloShooterRating) ratingSystem = RatingType.elo;
    else if(rating is OpenskillRating) ratingSystem = RatingType.openskill;
    else if(rating is PointsRating) ratingSystem = RatingType.points;
    else throw UnsupportedError("non-supported rating system");

    var dbRating = DbShooterRating(
      ratingSystem: ratingSystem,
      lastClassification: rating.lastClassification,
      lastSeen: rating.lastSeen,
      project: project.id!,
      group: group,
      matchId: matchesToDbIds.values.first, // not used
      firstName: rating.firstName,
      lastName: rating.lastName,
      memberNumber: rating.memberNumber,
      originalMemberNumber: rating.originalMemberNumber,
      reentry: rating.reentry,
      dq: rating.dq,
      division: rating.division!,
      classification: rating.classification!,
      powerFactor: rating.powerFactor!
    );
    var id = await store.ratings.save(dbRating);
    dbRating.id = id;

    switch(dbRating.ratingSystem) {
      case RatingType.elo:
        DbEloRating.serialize(rating as EloShooterRating, dbRating, store);
        break;
      case RatingType.openskill:
        throw UnimplementedError();
      case RatingType.points:
        throw UnimplementedError();
    }

    for(var event in rating.ratingEvents) {

    }

    return dbRating;
  }
}

@dao
abstract class ShooterRatingDao {
  @insert
  Future<int> save(DbShooterRating rating);

  @Query("SELECT * FROM shooterRatings")
  Future<List<DbShooterRating>> all();
}

abstract class RatingExtension {
  int get parentId;
}

class RaterGroupConverter extends TypeConverter<RaterGroup, int> {
  @override
  RaterGroup decode(int databaseValue) {
    return RaterGroup.values[databaseValue];
  }

  @override
  int encode(RaterGroup value) {
    return RaterGroup.values.indexOf(value);
  }
}

class RatingTypeConverter extends TypeConverter<RatingType, int> {
  RatingType decode(int databaseValue) {
    return RatingType.values[databaseValue];
  }

  @override
  int encode(RatingType value) {
    return RatingType.values.indexOf(value);
  }
}