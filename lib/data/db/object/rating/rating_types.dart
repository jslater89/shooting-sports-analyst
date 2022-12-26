import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

enum RatingType {
  elo,
  openskill,
  points;

  static RatingType fromSettings(RatingHistorySettings settings) {
    if(settings.algorithm is MultiplayerPercentEloRater) {
      return RatingType.elo;
    }
    throw UnimplementedError("Not yet implemented for Openskill/Points");
  }
}

class RatingTypeConverter extends TypeConverter<RatingType, int> {
  @override
  RatingType decode(int databaseValue) {
    return RatingType.values[databaseValue];
  }

  @override
  int encode(RatingType value) {
    return RatingType.values.indexOf(value);
  }

}