/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/connectivity.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("RatingProjetRollback");

sealed class RatingProjectRollbackError implements ResultErr {
  String get message;
}

class UncaughtRollbackException implements RatingProjectRollbackError {
  Exception e;
  UncaughtRollbackException(this.e);

  @override
  String get message => e.toString();
}

class StringRollbackError implements RatingProjectRollbackError {
  String message;
  StringRollbackError(this.message);
}

enum RollbackState {
  notStarted,
  updatingMatches,
  loadingRatings,
  processingRatings,
  complete;

  String get label {
    switch(this) {
      case RollbackState.notStarted:
        return "not started";
      case RollbackState.updatingMatches:
        return "updating matches";
      case RollbackState.loadingRatings:
        return "loading ratings";
      case RollbackState.processingRatings:
        return "processing ratings";
      case RollbackState.complete:
        return "complete";
    }
  }
}

typedef RatingProjectRollbackCallback = Future<void> Function({
  required int progress,
  required int total,
  required RollbackState state,
  String? eventName,
  int? subProgress,
  int? subTotal,
});

/// Rolls back a rating project to the state at a particular point in time.
class RatingProjectRollback {
  /// The project to roll back.
  final DbRatingProject project;

  /// The callback to call with progress updates.
  final RatingProjectRollbackCallback callback;

  /// Creates a new project rollback-er.
  ///
  /// [project] is the project to roll back.
  ///
  /// [callback] is the callback to call with progress updates.
  RatingProjectRollback({required this.project, required this.callback});

  /// Roll back the project to the date specified in the constructor.
  ///
  /// Rolling back is a destructive operation: it will remove match links
  /// from the project that occur after the rollback date, delete all rating
  /// events that occur in those matches, and delete any competitor ratings
  /// that have zero events after such events are deleted.
  ///
  /// Note that shooter deduplication data entered during previous project loads
  /// that relates to the deleted ratings _will not_ be removed.
  ///
  /// [rollbackDate] is the date to roll back to. Matches whose dates are after
  /// this date will be removed. (Note that this is strictly after/greater than,
  /// not greater than or equal to.)
  ///
  /// The returned result will be Ok() if the rollback completed successfully, or
  /// or Err(err) if there was an error.
  Future<Result<void, RatingProjectRollbackError>> rollback(DateTime rollbackDate) async {
    var db = AnalystDatabase();
    var rater = project.settings.algorithm;

    await callback(progress: 0, total: 1, state: RollbackState.updatingMatches);
    // Find matches after the rollback date.
    var matches = project.matchPointers.where((match) => match.date!.isAfter(rollbackDate)).toList();
    var matchIds = matches.map((match) => match.sourceIds.first).whereNotNull().toList();
    if(matchIds.length != matches.length) {
      // Shouldn't happen, but log it just in case.
      _log.w("${matches.length - matchIds.length} matches had no local ID and were not rolled back");
    }

    // Remove the matches from the project.
    var pointers = [...project.matchPointers];
    var filteredPointers = [...project.filteredMatchPointers];
    var lastUsedPointers = [...project.lastUsedMatches];
    for (var match in matches) {
      pointers.remove(match);
      filteredPointers.remove(match);
      lastUsedPointers.remove(match);
    }
    project.matchPointers = pointers;
    project.filteredMatchPointers = filteredPointers;
    project.lastUsedMatches = lastUsedPointers;

    await callback(progress: 0, total: 1, state: RollbackState.loadingRatings);

    // TODO: add query for ratings last seen after date
    await project.ratings.load();
    var length = project.ratings.length;

    // process a minimum of 10 ratings between steps, or a maximum of about 300 steps
    var stepSize = length ~/ 300;
    if(stepSize < 10) {
      stepSize = 10;
    }
    var steps = length ~/ stepSize;
    int currentStep = 0;

    await callback(progress: 0, total: steps, state: RollbackState.processingRatings);
    for(var (i, rating) in project.ratings.indexed) {
      if(i % stepSize == 0) {
        var formattedRating = project.settings.algorithm.formatNumericRating(rating.rating);
        await callback(progress: currentStep, total: steps, state: RollbackState.processingRatings, eventName: "${rating.name} (${formattedRating})");
        currentStep++;
      }

      if(rating.lastSeen.isBefore(rollbackDate) || rating.lastSeen == rollbackDate) {
        // Skip anyone who last competed before the rollback date without further DB hits.
        continue;
      }

      await rating.events.load();

      // Find events that belong to matches we removed.
      var events = await db.getRatingEventsFor(rating, after: rollbackDate);
      List<DbRatingEvent> eventsToRemove = [];
      for(var event in events) {
        // We have to re-check this because the query returns after-or-equal, and
        // we want to remove only strictly-after.
        if(event.date.isAfter(rollbackDate)) {
          eventsToRemove.add(event);
        }
      }

      int remainingEvents = rating.events.length - eventsToRemove.length;
      if(remainingEvents == 0) {
        // Deletes all events and the rating
        await db.deleteShooterRating(rating);
      }
      else if(eventsToRemove.isNotEmpty) {
        var wrapped = rater.wrapDbRating(rating);
        var supportsConnectivity = project.sport.connectivityCalculator != null;
        await wrapped.rollbackEvents(eventsToRemove, updateConnectivity: supportsConnectivity, byStage: project.settings.byStage);
      }
    }

    // Calculate new connectivity baselines for all groups in the project
    if(project.sport.connectivityCalculator != null) {
      var calc = project.sport.connectivityCalculator!;
      for(var group in project.groups) {
        List<double>? connectivityScores;
        double? connectivitySum;
        int? matchCount;
        int? competitorCount;

        if(calc.requiredBaselineData.contains(ConnectivityRequiredData.connectivityScores)) {
          connectivityScores = await db.getConnectivity(project, group);
          competitorCount = connectivityScores.length;
        }
        if(calc.requiredBaselineData.contains(ConnectivityRequiredData.connectivitySum)) {
          if(connectivityScores != null) {
            connectivitySum = connectivityScores.sum;
          }
          else {
            connectivitySum = await db.getConnectivitySum(project, group);
          }
        }
        if(calc.requiredBaselineData.contains(ConnectivityRequiredData.competitorCount) && competitorCount == null) {
          competitorCount = await db.countShooterRatings(project, group);
        }
        if(calc.requiredBaselineData.contains(ConnectivityRequiredData.matchCount)) {
          matchCount = project.matchPointers.length;
        }

        var baseline = calc.calculateConnectivityBaseline(
          matchCount: matchCount,
          competitorCount: competitorCount,
          connectivitySum: connectivitySum,
          connectivityScores: connectivityScores,
        );
        project.connectivityContainer.add(BaselineConnectivity(
          groupUuid: group.uuid,
          connectivity: baseline,
        ));
      }
    }

    await db.saveRatingProject(project);
    await callback(progress: 0, total: 1, state: RollbackState.complete);

    return Result.ok(null);
  }
}
