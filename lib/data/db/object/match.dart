import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/match_cache/match_db.dart';
import 'package:uspsa_result_viewer/data/db/object/stage.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';

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

  PracticalMatch deserialize(MatchStore store) {
    throw UnimplementedError();
  }

  static DbMatch serialize(PracticalMatch match, MatchStore store) {
    throw UnimplementedError();
  }
}

@dao
abstract class MatchDao {
  @Query('SELECT * from matches')
  Future<List<DbMatch>> all();

  @insert
  Future<void> save(DbMatch match);
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