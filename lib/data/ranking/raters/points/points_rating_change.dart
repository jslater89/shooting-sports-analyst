/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

class PointsRatingEvent extends RatingEvent {
  PointsRatingEvent({
    required this.oldRating,
    required this.ratingChange,
    required ShootingMatch match,
    required RelativeScore score,
    Map<String, List<dynamic>> info = const {}
  }) : super(match: match, score: score, info: info);

  PointsRatingEvent.copy(PointsRatingEvent other) :
      this.oldRating = other.oldRating,
      this.ratingChange = other.ratingChange,
      super.copy(other);

  @override
  void apply(RatingChange change) {
    if(change.change.isEmpty) {
      ratingChange = double.nan;
    }
    else {
      ratingChange += change.change[RatingSystem.ratingKey]!;
    }
  }

  @override
  final double oldRating;

  @override
  double ratingChange;
}