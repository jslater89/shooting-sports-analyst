/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';

class F1Points extends PointsModel {
  F1Points(PointsSettings settings) : super(settings);

  @override
  Map<ShooterRating, RatingChange> apply(Map<ShooterRating, RelativeScore> scores) {
    if(scores.isEmpty) return {};
    else if(scores.length == 1) {
      return {
        scores.keys.first: RatingChange(change: {
          RatingSystem.ratingKey: 0,
        })
      };
    }

    var sortedEntries = scores.entries.sorted((e1, e2) => e2.value.percent.compareTo(e1.value.percent));

    Map<ShooterRating, RatingChange> changes = {};
    for(int i = 0; i < sortedEntries.length; i++) {
      var entry = sortedEntries[i];
      var rating = entry.key;

      var change = 0.0;
      if(i < _points.length) {
        change += _points[i].toDouble();
      }

      changes[rating] = RatingChange(change: {
        RatingSystem.ratingKey: change,
      });

    }

    return changes;
  }

  @override
  String displayRating(double rating) {
    return rating.round().toString();
  }
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