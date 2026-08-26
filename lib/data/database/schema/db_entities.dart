/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("DbShooterRatingEntity");

/// Shooter ratings are not necessarily long-lived; they will be
/// deleted and recreated if a rating project is recalculated.
/// As such, we need some functionality on entities that link to
/// shooter ratings to re-resolve them in the event that the underlying
/// shooter rating is deleted and recreated. Specifically, we need
/// to know the project, the group, and the original member number.
mixin DbShooterRatingEntity {
  /// A member number for this competitor.
  String get memberNumber;

  /// The project containing the shooter rating of interest.
  IsarLink<DbRatingProject> get project;

  /// The rating grup containing the shooter rating of interest.
  IsarLink<RatingGroup> get group;

  /// The shooter rating of interest.
  IsarLink<DbShooterRating> get rating;

  /// Gets the shooter rating of interest for the given project and group.
  ///
  /// If [save] is true and the rating link is broken (i.e. a full recalc dropped and recreated the
  /// rating for this identity), the rating link will be updated to the new rating after it is re-resolved.
  ///
  /// If [useCache] is true, rating lookups for broken links will leverage in-memory caches if available.
  DbShooterRating? getShooterRatingSync(
    AnalystDatabase db, {
    bool save = false,
    bool useCache = false,
    void Function(String currentMemberNumber, Set<String> knownMemberNumbers)? repairCallback,
  }) {
    if(rating.value != null) {
      return rating.value!;
    }

    var projectValue = project.value;
    var groupValue = group.value;
    if(projectValue == null || groupValue == null) {
      _log.w("Project or group not set when looking up shooter rating for $memberNumber");
      return null;
    }

    var ratingValue = db.maybeKnownShooterSync(project: projectValue, group: groupValue, memberNumber: memberNumber, useCache: useCache);
    if(ratingValue == null) {
      return null;
    }
    rating.value = ratingValue;
    if(save) {
      db.writeTxnSync(() {
        rating.saveSync();
      });
    }
    if(repairCallback != null) {
      repairCallback(memberNumber, ratingValue.knownMemberNumbers);
    }
    return ratingValue;
  }

  /// Gets the shooter rating of interest for the given project and group, asynchronously.
  ///
  /// If [save] is true and the rating link is broken (i.e. a full recalc dropped and recreated the
  /// rating for this identity), the rating link will be updated to the new rating after it is re-resolved.
  ///
  /// If [useCache] is true, rating lookups for broken links will leverage in-memory caches if available.
  Future<DbShooterRating?> getShooterRating(
    AnalystDatabase db, {
    bool save = false,
    bool useCache = false,
    Future<void> Function(String currentMemberNumber, Set<String> knownMemberNumbers)? repairCallback,
  }) async {
    await rating.load();
    if(rating.value != null) {
      return rating.value!;
    }

    await project.load();
    await group.load();
    var projectValue = project.value;
    var groupValue = group.value;
    if(projectValue == null || groupValue == null) {
      _log.w("Project or group not set when looking up shooter rating for $memberNumber");
      return null;
    }

    var ratingValue = await db.maybeKnownShooter(project: projectValue, group: groupValue, memberNumber: memberNumber, useCache: useCache);
    if(ratingValue == null) {
      return null;
    }
    rating.value = ratingValue;
    if(save) {
      await db.writeTxn(() async {
        rating.save();
      });
    }
    if(repairCallback != null) {
      await repairCallback(memberNumber, ratingValue.knownMemberNumbers);
    }
    return ratingValue;
  }
}

/// A DbShooterRating suitable for embedding in other DB entities. Prefer to use
/// [DbShooterRatingEntity] instead when possible, as it can cache its target as a DB link and doesn't
/// require manual management of the links.
mixin EmbeddedDbShooterRatingEntity {
  /// A member number for this competitor.
  String get memberNumber;

  /// Alternate member numbers for this competitor, to be used when data entry
  /// errors or earlier history starts change [memberNumber].
  List<String> get memberNumbers;

  /// The database ID for the project containing the shooter rating of interest.
  int get projectId;

  /// The UUID for the rating group containing the shooter rating of interest.
  String get groupUuid;

  @ignore
  DbShooterRating? _cachedRating;

  @ignore
  int get key => combineHashList64([projectId.stableHash64, groupUuid.stableHash64, memberNumber.stableHash64]);

  /// Gets the shooter rating of interest for the given project and group.
  DbShooterRating? getShooterRatingSync(
    AnalystDatabase db, {
    void Function(String currentMemberNumber, Set<String> knownMemberNumbers)? repairCallback,
  }) {
    if(_cachedRating != null) {
      return _cachedRating;
    }

    var project = db.getRatingProjectByIdSync(projectId);
    var group = project?.groups.firstWhereOrNull((g) => g.uuid == groupUuid);
    if(project == null || group == null) {
      return null;
    }

    _cachedRating = db.maybeKnownShooterSync(project: project, group: group, memberNumber: memberNumber, usePossibleMemberNumbers: true);

    if(_cachedRating == null && memberNumbers.isNotEmpty) {
      for(var memberNumber in memberNumbers) {
        _cachedRating = db.maybeKnownShooterSync(project: project, group: group, memberNumber: memberNumber, usePossibleMemberNumbers: true);
        if(_cachedRating != null) {
          break;
        }
      }
    }

    if(_cachedRating != null && repairCallback != null) {
      repairCallback(memberNumber, _cachedRating!.knownMemberNumbers);
    }
    return _cachedRating;
  }

  /// Gets the shooter rating of interest for the given project and group.
  Future<DbShooterRating?> getShooterRating(
    AnalystDatabase db, {
    Future<void> Function(String currentMemberNumber, Set<String> knownMemberNumbers)? repairCallback,
  }) async {
    if(_cachedRating != null) {
      return _cachedRating;
    }

    var project = await db.getRatingProjectById(projectId);
    var group = project?.groups.firstWhereOrNull((g) => g.uuid == groupUuid);
    if(project == null || group == null) {
      return null;
    }

    _cachedRating = await db.maybeKnownShooter(project: project, group: group, memberNumber: memberNumber);

    if(_cachedRating == null && memberNumbers.isNotEmpty) {
      for(var memberNumber in memberNumbers) {
        _cachedRating = await db.maybeKnownShooter(project: project, group: group, memberNumber: memberNumber, usePossibleMemberNumbers: true);
        if(_cachedRating != null) {
          break;
        }
      }
    }
    if(_cachedRating != null && repairCallback != null) {
      await repairCallback(memberNumber, _cachedRating!.knownMemberNumbers);
    }
    return _cachedRating;
  }
}