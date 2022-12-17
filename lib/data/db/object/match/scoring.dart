import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/match/score.dart';

class ScoringConverter extends TypeConverter<Scoring, int> {
  @override
  Scoring decode(int databaseValue) {
    return Scoring.values[databaseValue];
  }

  @override
  int encode(Scoring value) {
    return Scoring.values.indexOf(value);
  }

}