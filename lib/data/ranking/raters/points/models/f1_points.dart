
import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';

Map<ShooterRating, RatingChange> applyF1Points(Map<ShooterRating, RelativeScore> scores, PointsSettings settings) {
  var sortedEntries = scores.entries.sorted((e1, e2) => e2.value.percent.compareTo(e1.value.percent));

  Map<ShooterRating, RatingChange> changes = {};
  for(int i = 0; i < sortedEntries.length; i++) {
    var entry = sortedEntries[i];
    var rating = entry.key;

    var change = 0.0;
    if(i < _points.length) {
      change += _points[i].toDouble();
    }

    if(settings.participationBonus > 0) {
      change += _points[0] * settings.participationBonus;
    }

    changes[rating] = RatingChange(change: {
      RatingSystem.ratingKey: change,
    });

  }

  return changes;
}

const _points = [
  25,
  18,
  15,
  12,
  10,
  8,
  6,
  4,
  2,
  1
];