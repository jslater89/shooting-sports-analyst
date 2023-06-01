import 'dart:async';
import 'package:floor/floor.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'package:uspsa_result_viewer/data/db/object/match/match.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/elo/db_elo_rating.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_project.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/db/object/match/score.dart';
import 'package:uspsa_result_viewer/data/db/object/match/scoring.dart';
import 'package:uspsa_result_viewer/data/db/object/match/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/match/stage.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

part 'project_db.g.dart';

/// ProjectDatabase is the application database, pending renaming.
///
/// Schemas, generally:
///
/// Match side
///   Match
///     Stage belongs to Match
///     Shooter belongs to Match
///       Score belongs to Shooter, has Stage
///
/// Rating side
///   RatingProject
///     MemberNumberMapping belongs to RatingProject, has Group (enum)
///     EncounteredShooter belongs to RatingProject, has Group (enum)
///     RatingProjectMatch belongs to RatingProject, has Match
///     ShooterRating belongs to RatingProject, has Group (enum)
///       ShooterRating is one of three types, based on project algorithm
@Database(
    version: 1,
    entities: [
      DbMatch,
      DbStage,
      DbShooter,
      DbScore,
      DbRatingProject,
      DbRatingProjectMatch,
      DbEloRating,
      DbEloEvent,
      DbMemberNumberMapping,
    ]
)
@TypeConverters([
  ScoringConverter,
  MatchLevelConverter,
  DateTimeConverter,
  PowerFactorConverter,
  ClassificationConverter,
  DivisionConverter,
  RaterGroupConverter,
  RatingTypeConverter,
])
abstract class ProjectDatabase extends FloorDatabase implements ProjectStore {
  MatchDao get matches;
  StageDao get stages;
  ShooterDao get shooters;
  ScoreDao get scores;
  RatingProjectDao get projects;
  EloRatingDao get eloRatings;
}

class DateTimeConverter extends TypeConverter<DateTime, int> {
  @override
  DateTime decode(int databaseValue) {
    return DateTime.fromMicrosecondsSinceEpoch(databaseValue);
  }

  @override
  int encode(DateTime value) {
    return value.millisecondsSinceEpoch;
  }
}

abstract class ProjectStore extends MatchStore {
  RatingProjectDao get projects;
  EloRatingDao get eloRatings;
}

abstract class MatchStore {
  MatchDao get matches;
  StageDao get stages;
  ShooterDao get shooters;
  ScoreDao get scores;
}