
import 'dart:async';
import 'package:floor/floor.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'package:uspsa_result_viewer/data/db/object/match.dart';
import 'package:uspsa_result_viewer/data/db/object/score.dart';
import 'package:uspsa_result_viewer/data/db/object/scoring.dart';
import 'package:uspsa_result_viewer/data/db/object/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/stage.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';

part 'match_db.g.dart';

/// MatchDatabase contains the match cache.
@Database(
  version: 1,
  entities: [
    DbMatch,
    DbStage,
    DbShooter,
    DbScore,
  ]
)
@TypeConverters([
  ScoringConverter,
  MatchLevelConverter,
  DateTimeConverter,
  PowerFactorConverter,
  ClassificationConverter,
  DivisionConverter,
])
abstract class MatchDatabase extends FloorDatabase implements MatchStore {
  MatchDao get matches;
  StageDao get stages;
  ShooterDao get shooters;
  ScoreDao get scores;
}

abstract class MatchStore {
  MatchDao get matches;
  StageDao get stages;
  ShooterDao get shooters;
  ScoreDao get scores;
}