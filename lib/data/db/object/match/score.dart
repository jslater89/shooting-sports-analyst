// We store stage scores only. Everything else is calculated at runtime.

import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/match/stage.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/match/score.dart';

/// A shooter's stage score in a match.
///
/// When deleting a match, sadly, you have to delete scores separately first,
/// then you can delete the match and stage/shooter will cascade.
@Entity(
    tableName: "scores",
    foreignKeys: [
      ForeignKey(childColumns: ["stageId"], parentColumns: ["id"], entity: DbStage, onDelete: ForeignKeyAction.restrict),
      ForeignKey(childColumns: ["shooterId"], parentColumns: ["id"], entity: DbShooter, onDelete: ForeignKeyAction.restrict)
    ]
)
class DbScore {
  @PrimaryKey(autoGenerate: true)
  int? id;

  int shooterId;
  int stageId;

  double t1, t2, t3, t4, t5;
  double time;

  int a, b, c, d, m, ns, npm;
  int procedural, lateShot, extraShot, extraHit, otherPenalty;

  DbScore({
    this.id,
    required this.shooterId,
    required this.stageId,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.t4,
    required this.t5,
    required this.time,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.m,
    required this.ns,
    required this.npm,
    required this.procedural,
    required this.lateShot,
    required this.extraShot,
    required this.extraHit,
    required this.otherPenalty,
  });

  static Future<DbScore> serialize(Score score, DbShooter shooter, DbStage stage, MatchStore store) async {
    var dbScore = DbScore(
      shooterId: shooter.id!,
      stageId: stage.id!,
      t1: score.t1,
      t2: score.t2,
      t3: score.t3,
      t4: score.t4,
      t5: score.t5,
      time: score.time,
      a: score.a,
      b: score.b,
      c: score.c,
      d: score.d,
      m: score.m,
      ns: score.ns,
      npm: score.npm,
      procedural: score.procedural,
      lateShot: score.lateShot,
      extraShot: score.extraShot,
      extraHit: score.extraHit,
      otherPenalty: score.otherPenalty,
    );

    int id = await store.scores.save(dbScore);
    dbScore.id = id;

    return dbScore;
  }
}

@dao
abstract class ScoreDao {
  @Query("SELECT * FROM scores "
      "WHERE stageId = :stageId "
      "AND shooterId = :shooterId")
  Future<List<DbScore>> stageScoresForShooter(int stageId, int shooterId);

  @Query("SELECT scores.* FROM scores JOIN stages "
      "WHERE stages.matchId = :matchId "
      "AND shooterId = :shooterId")
  Future<List<DbScore>> matchScoresForShooter(int matchId, int shooterId);

  @insert
  Future<int> save(DbScore score);
}