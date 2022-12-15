// We store stage scores only. Everything else is calculated at runtime.

import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/stage.dart';

@Entity(
    tableName: "scores",
    foreignKeys: [
      ForeignKey(childColumns: ["stageId"], parentColumns: ["id"], entity: DbStage),
      ForeignKey(childColumns: ["shooterId"], parentColumns: ["id"], entity: DbShooter)
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
}