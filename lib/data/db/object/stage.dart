import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/match/score.dart';
import 'package:uspsa_result_viewer/data/model.dart';

@Entity(tableName: "stages")
class DbStage {
  @PrimaryKey(autoGenerate: true)
  int? id;

  @ForeignKey(childColumns: ["matchId"], parentColumns: ["id"], entity: DbMatch, onDelete: ForeignKeyAction.cascade)
  int matchId;

  String name;
  int minRounds = 0;
  int maxPoints = 0;
  bool classifier;
  String classifierNumber;

  Scoring type;

  DbStage({
    required this.matchId,
    required this.name,
    required this.minRounds,
    required this.maxPoints,
    required this.classifier,
    required this.classifierNumber,
    required this.type,
  });

  static Future<DbStage> serialize(Stage stage, DbMatch parent, MatchStore store) async {
    var dbStage = DbStage(
      name: stage.name,
      classifier: stage.classifier,
      classifierNumber: stage.classifierNumber,
      matchId: parent.id!,
      maxPoints: stage.maxPoints,
      minRounds: stage.minRounds,
      type: stage.type
    );

    int id = await store.stages.save(dbStage);
    dbStage.id = id;

    return dbStage;
  }
}

@dao
abstract class StageDao {
  @Query("SELECT * FROM stages")
  Future<List<DbStage>> all();

  @Query("SELECT * FROM stages WHERE matchId = :id")
  Future<List<DbStage>> forMatchId(int id);

  @Insert(onConflict: OnConflictStrategy.replace)
  Future<int> save(DbStage stage);
}