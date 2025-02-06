/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_relative_score.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

class PointsRatingEvent extends RatingEvent {
  PointsRatingEvent({
    required double oldRating,
    required double ratingChange,
    required ShootingMatch match,
    MatchStage? stage,
    required RelativeScore score,
    required RelativeScore matchScore,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],
  }) : super(
    wrappedEvent: DbRatingEvent(
      ratingChange: ratingChange,

      oldRating: oldRating,
      matchId: match.sourceIds.first,
      date: match.date,
      stageNumber: stage?.stageId ?? -1,
      entryId: score.shooter.entryId,
      score: DbRelativeScore.fromHydrated(score),
      matchScore: DbRelativeScore.fromHydrated(matchScore),
      intDataElements: 0,
      doubleDataElements: 0,
      infoLines: infoLines,
      infoData: infoData,
  ));


  PointsRatingEvent.copy(PointsRatingEvent other) :
      super.copy(other);

  PointsRatingEvent.wrap(DbRatingEvent event) :
        super(wrappedEvent: event);

  @override
  void apply(RatingChange change) {
    if(change.change.isEmpty) {
      ratingChange = double.nan;
    }
    else {
      ratingChange += change.change[RatingSystem.ratingKey]!;
    }
  }
}