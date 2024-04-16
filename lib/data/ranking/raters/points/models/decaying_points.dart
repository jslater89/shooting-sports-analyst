/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

class DecayingPoints extends PointsModel {
  DecayingPoints(PointsSettings settings) : super(settings);

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

    var sortedEntries = scores.entries.sorted((e1, e2) => e2.value.ratio.compareTo(e1.value.ratio));
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