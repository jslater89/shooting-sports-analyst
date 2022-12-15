import 'dart:async';
import 'package:floor/floor.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uspsa_result_viewer/data/db/match_cache/match_db.dart';

import 'package:uspsa_result_viewer/data/db/object/match.dart';
import 'package:uspsa_result_viewer/data/db/object/score.dart';
import 'package:uspsa_result_viewer/data/db/object/scoring.dart';
import 'package:uspsa_result_viewer/data/db/object/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/stage.dart';

part 'project_db.g.dart';

/// ProjectDatabase contains a single rating project: settings, rating
/// history, ratings, matches, and scores. Everything needed to inflate
/// a _single_ rating project lives in this database.
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
abstract class ProjectDatabase extends FloorDatabase implements MatchStore {
  MatchDao get matches;
  StageDao get stages;
  ShooterDao get shooters;
  ScoreDao get scores;
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