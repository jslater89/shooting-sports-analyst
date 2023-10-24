/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';

class PercentFinish extends PointsModel {
  PercentFinish(PointsSettings settings) : super(settings);

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

    Map<ShooterRating, RatingChange> changes = {};

    for(var entry in scores.entries) {
      changes[entry.key] = RatingChange(change: {
        RatingSystem.ratingKey: entry.value.percent * 100,
      });
    }

    return changes;
  }

  @override
  String displayRating(double rating) {
    return rating.toStringAsFixed(2);
  }
}