
import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_types.dart';
import 'package:uspsa_result_viewer/data/db/object/match/shooter.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

abstract class DbShooterRating extends DbShooterVitals {
  int project;

  RaterGroup group;
  Classification lastClassification;
  DateTime lastSeen;

  DbShooterRating({
    required this.lastClassification,
    required this.lastSeen,
    required this.project,
    required this.group,
    required super.firstName,
    required super.lastName,
    required super.memberNumber,
    required super.originalMemberNumber,
    required super.division,
    required super.classification,
    required super.powerFactor
  });
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