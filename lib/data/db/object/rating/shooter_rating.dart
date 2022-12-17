
import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_types.dart';
import 'package:uspsa_result_viewer/data/db/object/shooter.dart';
import 'package:uspsa_result_viewer/data/model.dart';
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
}

@dao
abstract class ShooterRatingDao {

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