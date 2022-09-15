
import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';

Map<ShooterRating, RatingChange> applyPercentFinish(Map<ShooterRating, RelativeScore> scores, PointsSettings settings) {
  Map<ShooterRating, RatingChange> changes = {};

  for(var entry in scores.entries) {
    changes[entry.key] = RatingChange(change: {
      RatingSystem.ratingKey: entry.value.percent * 100 + 100 * settings.participationBonus,
    });
  }

  return changes;
}