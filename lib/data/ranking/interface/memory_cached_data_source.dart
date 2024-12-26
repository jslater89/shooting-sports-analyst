// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

class InMemoryCachedRatingSource implements PreloadedRatingDataSource {
  late RatingProjectSettings settings;
  late List<RatingGroup> groups;
  late Map<RatingGroup, Map<String, DbShooterRating>> ratings;

  @override
  RatingProjectSettings getSettingsSync() {
    return settings;
  }

  @override
  ShooterRating? wrapDbRatingSync(DbShooterRating rating) {
    return settings.algorithm.wrapDbRating(rating);
  }

  @override
  RatingGroup? groupForDivisionSync(Division? division) {
    var fewestDivisions = 65536;
    RatingGroup? outGroup = null;
    if(division == null) {
      // TODO: this might not be the right result for a null division
      return groups.firstOrNull;
    }

    for(var group in groups) {
      if(group.divisions.length < fewestDivisions && group.divisions.contains(division)) {
        fewestDivisions = group.divisions.length;
        outGroup = group;
      }
    }

    return outGroup;
  }

  @override
  DbShooterRating? lookupRatingSync(RatingGroup group, String memberNumber) {
    return ratings[group]?[memberNumber];
  }

  Future<void> initFrom(RatingDataSource source, {List<Shooter>? ratingsToCache}) async {
    settings = await source.getSettings().unwrap();
    groups = await source.getGroups().unwrap();
  }

}