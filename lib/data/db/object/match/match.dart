import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match/score.dart';
import 'package:uspsa_result_viewer/data/db/object/match/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/match/stage.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';

@Entity(tableName: "matches")
class DbMatch {
  @PrimaryKey(autoGenerate: true)
  int? id;

  String? shortPsId;
  String longPsId;

  String name;
  String rawDate;
  DateTime date;
  MatchLevel level;

  String reportContents;

  DbMatch({
    this.id,
    this.shortPsId,
    required this.longPsId,
    required this.name,
    required this.date,
    required this.rawDate,
    required this.level,
    required this.reportContents,
  });

  Future<List<DbStage>> stages(MatchStore store) {
    return store.stages.forMatchId(id!);
  }

  Future<List<DbShooter>> shooters(MatchStore store) {
    return store.shooters.forMatchId(id!);
  }

  Future<PracticalMatch> deserialize(MatchStore store) async {
    var match = PracticalMatch();
    match.name = this.name;
    match.practiscoreId = this.longPsId;
    match.practiscoreIdShort = this.shortPsId;
    match.reportContents = this.reportContents;
    match.date = this.date;
    match.rawDate = this.rawDate;
    match.level = this.level;

    var dbStages = await store.stages.forMatchId(this.id!);
    var stagesByDbId = <int, Stage>{};
    for(var dbStage in dbStages) {
      var stage = dbStage.deserialize();
      stagesByDbId[dbStage.id!] = stage;
      match.stages.add(stage);
    }

    var dbShooters = await store.shooters.forMatchId(this.id!);
    var shootersById = <int, Shooter>{};
    for(var dbShooter in dbShooters) {
      var shooter = dbShooter.deserialize();
      shootersById[dbShooter.id!] = shooter;
      match.shooters.add(shooter);

      for(var dbStageId in stagesByDbId.keys) {
        var dbScore = await store.scores.stageScoreForShooter(dbStageId, dbShooter.id!);

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
      longPsId: match.practiscoreId,
      shortPsId: match.practiscoreIdShort,
      reportContents: match.reportContents,
    );

    int id = await store.matches.save(dbMatch);
    dbMatch.id = id;

    Map<Stage, DbStage> stageMapping = {};

    for(var stage in match.stages) {
      var dbStage = await DbStage.serialize(stage, dbMatch, store);
      stageMapping[stage] = dbStage;
    }

    List<Future> scoreFutures = [];
    for(var shooter in match.shooters) {
      var dbShooter = await DbShooter.serialize(shooter, dbMatch, store);

      for(var mapEntry in shooter.stageScores.entries) {
        var stage = mapEntry.key;
        var score = mapEntry.value;

        scoreFutures.add(DbScore.serialize(score, dbShooter, stageMapping[stage]!, store));
      }
    }

    await Future.wait(scoreFutures);

    return dbMatch;
  }
}

@dao
abstract class MatchDao {
  @Query('SELECT * from matches')
  Future<List<DbMatch>> all();

  @Insert(onConflict: OnConflictStrategy.replace)
  Future<int> save(DbMatch match);
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