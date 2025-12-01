/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("DbShooterRatingEntity");

/// Shooter ratings are not necessarily long-lived; they will be
/// deleted and recreated if a rating project is recalculated.
/// As such, we need some functionality on entities that link to
/// shooter ratings to re-resolve them in the event that the underlying
/// shooter rating is deleted and recreated. Specifically, we need
/// to know the project, the group, and the original member number.
mixin DbShooterRatingEntity {
  /// The original/oldest member number for this competitor, or as
  /// old as possible.
  String get originalMemberNumber;

  /// The project containing the shooter rating of interest.
  IsarLink<DbRatingProject> get project;

  /// The rating grup containing the shooter rating of interest.
  IsarLink<RatingGroup> get group;

  /// The shooter rating of interest.
  IsarLink<DbShooterRating> get rating;

  DbShooterRating? getShooterRatingSync(AnalystDatabase db, {bool save = false}) {
    if(rating.value != null) {
      return rating.value!;
    }

    var projectValue = project.value;
    var groupValue = group.value;
    if(projectValue == null || groupValue == null) {
      _log.w("Project or group not set when looking up shooter rating for $originalMemberNumber");
      return null;
    }

    var ratingValue = db.maybeKnownShooterSync(project: projectValue, group: groupValue, memberNumber: originalMemberNumber);
    if(ratingValue == null) {
      return null;
    }
    rating.value = ratingValue;
    if(save) {
      db.writeTxnSync(() {
        rating.saveSync();
      });
    }
    return ratingValue;
  }
}
