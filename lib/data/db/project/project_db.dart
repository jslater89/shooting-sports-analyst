import 'dart:async';
import 'package:floor/floor.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'package:uspsa_result_viewer/data/db/object/match/match.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/elo/db_elo_rating.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_event.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/rating_project.dart';
import 'package:uspsa_result_viewer/data/db/object/rating/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/db/object/match/score.dart';
import 'package:uspsa_result_viewer/data/db/object/match/scoring.dart';
import 'package:uspsa_result_viewer/data/db/object/match/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/match/stage.dart';

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
///     RatingProjectMatch belongs to RatingProject, has Match
///     ShooterRating belongs to RatingProject, has Group (enum)
///       EloRating belongs to ShooterRating (openskill, points...)
///       RatingEvent belongs to ShooterRating
///         EloEvent belongs to RatingEvent (openskill, points...)
@Database(
    version: 1,
    entities: [
      DbMatch,
      DbStage,
      DbShooter,
      DbScore,
      DbRatingProject,
      DbRatingProjectMatch,
      DbShooterRating,
      DbRatingEvent,
      DbEloRating,
      DbEloEvent,
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
  ShooterRatingDao get ratings;
  RatingEventDao get events;
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
  ShooterRatingDao get ratings;
  RatingEventDao get events;
  EloRatingDao get eloRatings;
}

abstract class MatchStore {
  MatchDao get matches;
  StageDao get stages;
  ShooterDao get shooters;
  ScoreDao get scores;
}