import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match.dart';
import 'package:uspsa_result_viewer/data/match/score.dart';

@Entity(tableName: "stages")
class DbStage {
  @PrimaryKey(autoGenerate: true)
  int? id;

  @ForeignKey(childColumns: ["matchId"], parentColumns: ["id"], entity: DbMatch)
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
}

@dao
abstract class StageDao {
  @Query("SELECT * FROM stages")
  Future<List<DbStage>> all();

  @Query("SELECT * FROM stages WHERE matchId = :id")
  Future<List<DbStage>> forMatchId(int id);
}