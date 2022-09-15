
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';

Map<ShooterRating, RatingChange> applyDecayingPoints(Map<ShooterRating, RelativeScore> scores, PointsSettings settings) {
  var sortedEntries = scores.entries.sorted((e1, e2) => e2.value.percent.compareTo(e1.value.percent));

  var bonus = settings.decayingPointsStart * settings.participationBonus;
  Map<ShooterRating, RatingChange> changes = {};
  for(int i = 0; i < sortedEntries.length; i++) {
    var entry = sortedEntries[i];
    var rating = entry.key;

    var points = settings.decayingPointsStart * pow(settings.decayingPointsFactor, i);

    var change = points + bonus;

    changes[rating] = RatingChange(change: {
      RatingSystem.ratingKey: change,
    });

  }

  return changes;
}