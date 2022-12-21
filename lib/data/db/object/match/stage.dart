import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match/match.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/match/score.dart';
import 'package:uspsa_result_viewer/data/model.dart';

@Entity(
  tableName: "stages",
  indices: [
    Index(
      value: ["matchId", "internalId"],
      unique: true,
    )
  ],
  primaryKeys: [
    "matchId",
    "internalId",
  ],
  withoutRowid: true,
)
class DbStage {
  @ForeignKey(childColumns: ["matchId"], parentColumns: ["longPsId"], entity: DbMatch, onDelete: ForeignKeyAction.cascade)
  String matchId;

  String name;
  /// The PractiScore file number of the stage, unique per match.
  int internalId;
  int minRounds = 0;
  int maxPoints = 0;
  bool classifier;
  String classifierNumber;

  Scoring scoring;

  DbStage({
    required this.internalId,
    required this.matchId,
    required this.name,
    required this.minRounds,
    required this.maxPoints,
    required this.classifier,
    required this.classifierNumber,
    required this.scoring,
  });

  Stage deserialize() {
    Stage s = Stage(
      internalId: this.internalId,
      type: this.scoring,
      minRounds: this.minRounds,
      maxPoints: this.maxPoints,
      classifierNumber: this.classifierNumber,
      classifier: this.classifier,
      name: this.name,
    );

    return s;
  }

  static DbStage convert(Stage stage, DbMatch parent) {
    return DbStage(
        name: stage.name,
        internalId: stage.internalId,
        classifier: stage.classifier,
        classifierNumber: stage.classifierNumber,
        matchId: parent.psId,
        maxPoints: stage.maxPoints,
        minRounds: stage.minRounds,
        scoring: stage.type
    );
  }

  static Future<DbStage> serialize(Stage stage, DbMatch parent, MatchStore store) async {
    var dbStage = convert(stage, parent);

    var existing = await store.stages.byInternalId(parent.psId, stage.internalId);
    if(existing != null) {
      await store.stages.updateExisting(dbStage);
    }
    else {
      int id = await store.stages.save(dbStage);
    }
    return dbStage;
  }
}

@dao
abstract class StageDao {
  @Query("SELECT * FROM stages")
  Future<List<DbStage>> all();

  @Query("SELECT * FROM stages WHERE matchId = :id")
  Future<List<DbStage>> forMatchId(String id);

  @Query("SELECT * FROM stages WHERE matchId = :matchId AND internalId = :internalId")
  Future<DbStage?> byInternalId(String matchId, int internalId);

  @insert
  Future<int> save(DbStage stage);

  @Update(onConflict: OnConflictStrategy.replace)
  Future<int> updateExisting(DbStage stage);

  @insert
  Future<void> saveAll(List<DbStage> stages);
}