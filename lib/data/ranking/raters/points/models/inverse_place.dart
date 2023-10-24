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

class InversePlace extends PointsModel {
  InversePlace(PointsSettings settings) : super(settings);

  int count = 0;

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

    count = sortedEntries.length;

    Map<ShooterRating, RatingChange> changes = {};
    for(int i = 0; i < sortedEntries.length; i++) {
      var entry = sortedEntries[i];
      var rating = entry.key;

      // 1st place beats everyone except for himself
      var shootersBeat = (count - (i + 1));
      var change = shootersBeat.toDouble();

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