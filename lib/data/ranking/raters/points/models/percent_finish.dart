
import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';

class PercentFinish extends PointsModel {
  PercentFinish(PointsSettings settings) : super(settings);

  @override
  Map<ShooterRating, RatingChange> apply(Map<ShooterRating, RelativeScore> scores) {
    Map<ShooterRating, RatingChange> changes = {};

    for(var entry in scores.entries) {
      changes[entry.key] = RatingChange(change: {
        RatingSystem.ratingKey: entry.value.percent * 100,
      });
    }

    return changes;
  }

  @override
  double get participationBonus => 100 * settings.participationBonus;

}