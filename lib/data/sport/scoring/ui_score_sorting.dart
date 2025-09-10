/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/synchronous_rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_display_mode.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

extension UiSorting on List<RelativeMatchScore> {
  void sortByLocalRating({required DbRatingProject ratings, ChangeNotifierRatingDataSource? ratingCache, required RatingDisplayMode displayMode, required ShootingMatch match, MatchStage? stage}) {
    var db = AnalystDatabase();
    this.sort((a, b) {
      DbShooterRating? aRating, bRating;
      if(ratingCache != null) {
        aRating = ratingCache.lookupRatingByMatchEntry(a.shooter);
        bRating = ratingCache.lookupRatingByMatchEntry(b.shooter);
      }

      if(aRating == null || bRating == null) {
        var aGroupRes = ratings.groupForDivisionSync(a.shooter.division);
        var bGroupRes = ratings.groupForDivisionSync(b.shooter.division);
        if(aGroupRes.isErr() || bGroupRes.isErr()) return b.ratio.compareTo(a.ratio);

        var aGroup = aGroupRes.unwrap();
        var bGroup = bGroupRes.unwrap();

        aRating = db.maybeKnownShooterSync(project: ratings, group: aGroup!, memberNumber: a.shooter.memberNumber);
        bRating = db.maybeKnownShooterSync(project: ratings, group: bGroup!, memberNumber: b.shooter.memberNumber);

        if(ratingCache != null) {
          if(aRating != null) {
            ratingCache.cacheRating(a.shooter, aRating);
          }
          if(bRating != null) {
            ratingCache.cacheRating(b.shooter, bRating);
          }
        }
      }

      if(aRating == null || bRating == null) return b.ratio.compareTo(a.ratio);

      var settings = ratings.getSettingsSync();
      var aRatingWrapped = settings.algorithm.wrapDbRating(aRating);
      var bRatingWrapped = settings.algorithm.wrapDbRating(bRating);

      var aRatingValue = aRatingWrapped.ratingForEvent(match, stage, beforeMatch: displayMode == RatingDisplayMode.preMatch);
      var bRatingValue = bRatingWrapped.ratingForEvent(match, stage, beforeMatch: displayMode == RatingDisplayMode.preMatch);

      if(displayMode == RatingDisplayMode.change) {
        aRatingValue = aRatingValue - aRatingWrapped.ratingForEvent(match, stage, beforeMatch: true);
        bRatingValue = bRatingValue - bRatingWrapped.ratingForEvent(match, stage, beforeMatch: true);
      }

      return bRatingValue.compareTo(aRatingValue);
    });
  }
}
