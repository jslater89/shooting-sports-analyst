// We store stage scores only. Everything else is calculated at runtime.

import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match/match.dart';
import 'package:uspsa_result_viewer/data/db/object/match/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/match/stage.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/model.dart';

/// A shooter's stage score in a match.
///
/// When deleting a match, sadly, you have to delete scores separately first,
/// then you can delete the match and stage/shooter will cascade.
@Entity(
  tableName: "scores",
  foreignKeys: [
    ForeignKey(childColumns: ["matchId"], parentColumns: ["psId"], entity: DbMatch, onDelete: ForeignKeyAction.restrict),
  ],
  primaryKeys: [
    "matchId",
    "shooterNumber",
    "stageNumber"
  ],
  withoutRowid: true,
)
class DbScore {
  String matchId;
  int shooterNumber;
  int stageNumber;

  double t1, t2, t3, t4, t5;
  double time;

  int a, b, c, d, m, ns, npm;
  int procedural, lateShot, extraShot, extraHit, otherPenalty;

  DbScore({
    required this.matchId,
    required this.shooterNumber,
    required this.stageNumber,
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

  Score deserialize(Shooter shooter, Stage stage) {
    var score = Score(shooter: shooter);
    score.stage = stage;
    score.t1 = t1;
    score.t2 = t2;
    score.t3 = t3;
    score.t4 = t4;
    score.t5 = t5;
    score.time = time;
    score.a = a;
    score.b = b;
    score.c = c;
    score.d = d;
    score.m = m;
    score.ns = ns;
    score.npm = npm;
    score.procedural = procedural;
    score.lateShot = lateShot;
    score.extraShot = extraShot;
    score.extraHit = extraHit;
    score.otherPenalty = otherPenalty;

    return score;
  }

  static DbScore convert(Score score, DbShooter shooter, DbStage stage, DbMatch match) {
    return DbScore(
      shooterNumber: shooter.internalId,
      matchId: match.psId,
      stageNumber: stage.internalId,
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
  }

  static Future<DbScore> serialize(Score score, DbShooter shooter, DbStage stage, DbMatch match, MatchStore store) async {
    var dbScore = convert(score, shooter, stage, match);

    var existing = await store.scores.stageScoreForShooter(stage.internalId, shooter.internalId, match.psId);
    if(existing != null) {
      await store.scores.updateExisting(dbScore);
    }
    else {
      int id = await store.scores.save(dbScore);
    }
    return dbScore;
  }
}

@dao
abstract class ScoreDao {
  @Query("SELECT * FROM scores "
      "WHERE stageId = :stageId "
      "AND shooterId = :shooterId "
      "AND matchId = :matchId")
  Future<DbScore?> stageScoreForShooter(int stageId, int shooterId, String matchId);

  @Query("SELECT scores.* FROM scores JOIN stages "
      "WHERE stages.matchId = :matchId "
      "AND shooterId = :shooterId")
  Future<List<DbScore>> matchScoresForShooter(int matchId, int shooterId);

  @insert
  Future<int> save(DbScore score);

  @insert
  Future<void> saveAll(List<DbScore> score);

  @Update(onConflict: OnConflictStrategy.replace)
  Future<int> updateExisting(DbScore score);
}