import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/match_cache/match_db.dart';
import 'package:uspsa_result_viewer/data/db/object/score.dart';
import 'package:uspsa_result_viewer/data/db/object/shooter.dart';
import 'package:uspsa_result_viewer/data/db/object/stage.dart';
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

  PracticalMatch deserialize(MatchStore store) {
    throw UnimplementedError();
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