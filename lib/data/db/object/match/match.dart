import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match/score.dart';
import 'package:uspsa_result_viewer/data/db/object/match/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/match/stage.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';

@Entity(
  tableName: "matches",
  withoutRowid: true,
)
class DbMatch {
  @PrimaryKey()
  String psId;

  String? shortPsId;

  String name;
  String rawDate;
  DateTime date;
  MatchLevel level;

  String reportContents = "";

  DbMatch({
    this.shortPsId,
    required this.psId,
    required this.name,
    required this.date,
    required this.rawDate,
    required this.level,
    //required this.reportContents,
  });

  Future<List<DbStage>> stages(MatchStore store) {
    return store.stages.forMatchId(psId);
  }

  Future<List<DbShooter>> shooters(MatchStore store) {
    return store.shooters.forMatchId(psId);
  }

  Future<PracticalMatch> deserialize(MatchStore store) async {
    var match = PracticalMatch();
    match.name = this.name;
    match.practiscoreId = this.psId;
    match.practiscoreIdShort = this.shortPsId;
    match.reportContents = this.reportContents;
    match.date = this.date;
    match.rawDate = this.rawDate;
    match.level = this.level;

    var dbStages = await store.stages.forMatchId(this.psId);
    var stagesByDbId = <int, Stage>{};
    for(var dbStage in dbStages) {
      var stage = dbStage.deserialize();
      stagesByDbId[dbStage.internalId] = stage;
      match.stages.add(stage);
    }

    var dbShooters = await store.shooters.forMatchId(this.psId);
    var shootersById = <int, Shooter>{};
    for(var dbShooter in dbShooters) {
      var shooter = dbShooter.deserialize();
      shootersById[dbShooter.internalId] = shooter;
      match.shooters.add(shooter);

      for(var dbStageId in stagesByDbId.keys) {
        var dbScore = await store.scores.stageScoreForShooter(dbStageId, dbShooter.internalId, this.psId);

        // TODO: remove this if it turns out I save stage scores for DQs too
        if(dbScore == null) {
          print("WARN: missing stage score");
          continue;
        }

        var stage = stagesByDbId[dbStageId]!;
        shooter.stageScores[stagesByDbId[dbStageId]!] = dbScore.deserialize(shooter, stage);
      }
    }

    return match;
  }

  static Future<DbMatch> serialize(PracticalMatch match, MatchStore store) async {
    // Match, shooters, stages, scores
    var dbMatch = DbMatch(
      date: match.date!,
      name: match.name!,
      level: match.level ?? MatchLevel.I,
      rawDate: match.rawDate!,
      psId: match.practiscoreId,
      shortPsId: match.practiscoreIdShort,
      // reportContents: match.reportContents,
    );

    await store.matches.save(dbMatch);

    Map<Stage, DbStage> stageMapping = {};

    for(var stage in match.stages) {
      var dbStage = DbStage.convert(stage, dbMatch);
      stageMapping[stage] = dbStage;
    }

    store.stages.saveAll(stageMapping.values.toList());

    List<DbShooter> shooters = [];
    List<DbScore> scores = [];
    for(var shooter in match.shooters) {
      var dbShooter = DbShooter.convert(shooter, dbMatch);
      shooters.add(dbShooter);

      for(var mapEntry in shooter.stageScores.entries) {
        var stage = mapEntry.key;
        var score = mapEntry.value;

        var dbScore = DbScore.convert(score, dbShooter, stageMapping[stage]!, dbMatch);
        scores.add(dbScore);
      }
    }

    await store.shooters.saveAll(shooters);
    await store.scores.saveAll(scores);

    // print("Serialized ${match.shooters.length} shooters");

    return dbMatch;
  }
}

@dao
abstract class MatchDao {
  @Query('SELECT * from matches')
  Future<List<DbMatch>> all();

  /// Matches are keyed by Practiscore UUID, so this doesn't return anything.
  @Insert(onConflict: OnConflictStrategy.replace)
  Future<void> save(DbMatch match);

  @Query('SELECT * FROM matches WHERE psId = :longId')
  Future<DbMatch?> byPractiscoreId(String longId);

  @Query('''
  SELECT matches.* from matches
  INNER JOIN ratingProjects_matches
  ON matches.psId = ratingProjects_matches.matchId
  AND ratingProjects_matches.projectId = :ratingProjectId
  ''')
  Future<List<DbMatch>> byRatingProject(int ratingProjectId);
}

class MatchLevelConverter extends TypeConverter<MatchLevel, int> {
  @override
  MatchLevel decode(int databaseValue) {
    return MatchLevel.values[databaseValue];
  }

  @override
  int encode(MatchLevel value) {
    return MatchLevel.values.indexOf(value);
  }
}