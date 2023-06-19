
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';

class DecayingPoints extends PointsModel {
  DecayingPoints(PointsSettings settings) : super(settings);

  @override
  Map<ShooterRating, RatingChange> apply(Map<ShooterRating, RelativeScore> scores) {
    var sortedEntries = scores.entries.sorted((e1, e2) => e2.value.percent.compareTo(e1.value.percent));
    Map<ShooterRating, RatingChange> changes = {};
    for(int i = 0; i < sortedEntries.length; i++) {
      var entry = sortedEntries[i];
      var rating = entry.key;

      var points = settings.decayingPointsStart * pow(settings.decayingPointsFactor, i);

      var change = points;

      changes[rating] = RatingChange(change: {
        RatingSystem.ratingKey: change,
      });
    }

    return changes;
  }

  @override
  String displayRating(double rating) {
    return rating.toStringAsFixed(1);
  }
}