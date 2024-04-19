/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

sealed class RatingProjectLoadError implements ResultErr {
  String get message;
}

enum MatchLoadFailureCause {
  wrongSport,
  invalidData;

  String get message {
    return switch(this) {
      wrongSport => "Incorrect sport",
      invalidData => "Data loading failed"
    };
  }
}

class MatchLoadFailureError extends RatingProjectLoadError {
  final ResultErr underlying;
  final MatchLoadFailureCause cause;
  final DbShootingMatch failedMatch;

  MatchLoadFailureError({required this.cause, required this.failedMatch, required this.underlying});

  @override
  String get message => "${cause.message} for ${failedMatch.eventName} (${underlying.runtimeType}: ${underlying.message})";
}

class RatingProjectLoader {
  final DbRatingProject project;
  final RatingProjectLoaderCallback callback;

  RatingProjectLoader(this.project, this.callback);

  // TODO: return errors
  // this needs to, at minimum, be able to say:
  //    * "match X is invalid"
  //    * "shooter dedup error with details for fixing it"
  Future<Result<void, RatingProjectLoadError>> calculateRatings({bool fullRecalc = false}) async {
    callback(progress: -1, total: -1, state: LoadingState.readingMatches);
    var matchesLink = await project.matchesToUse();

    // We want to add matches in ascending order, from oldest to newest.
    var matchesToAdd = await matchesLink.filter().sortByDate().findAll();

    // We're interested in the most recent match, so sort by date descending for
    // convenience.
    var lastUsed = await project.lastUsedMatches.filter().sortByDateDesc().findAll();
    bool canAppend = false;

    if(lastUsed.isNotEmpty) {
      var missingMatches = matchesToAdd.where((e) => !lastUsed.contains(e)).toList();
      var mostRecentMatch = lastUsed.first;
      canAppend = !fullRecalc && missingMatches.every((m) => m.date.isAfter(mostRecentMatch.date));
      if(canAppend) matchesToAdd = missingMatches;
    }

    if(!canAppend) {
      await project.resetRatings();
    }

    callback(progress: 0, total: matchesToAdd.length, state: LoadingState.readingMatches);
    List<ShootingMatch> hydratedMatches = [];
    for(var dbMatch in matchesToAdd) {
      var matchRes = dbMatch.hydrate();
      if(matchRes.isErr()) {
        var err = matchRes.unwrapErr();
        return Result.err(MatchLoadFailureError(
          cause: MatchLoadFailureCause.invalidData,
          failedMatch: dbMatch,
          underlying: err,
        ));
      }
      else {
        var match = matchRes.unwrap();
        hydratedMatches.add(match);
      }

      // 1. For each match, add shooters.

      // 2. Deduplicate shooters.

      // 3. For each group...

      // 3.1. For each match...

      // 3.1.1. Check recognized divisions

      // 3.1.2. Rank match through code in Rater

      // 3.1.3. Update database with rating changes

      // 3.2. Remove unseen shooters

      // 3.2.1. Update database with unseen shooter removal

      // 3.3. Calculate match stats
    }

    return Result.ok(null);
  }
}

/// A callback for RatingProjectLoader. When progress and total are both 0, show no progress.
/// When progress and total are both negative, show indeterminate progress. When total is positive,
/// show determinate progress with progress as the counter.
typedef RatingProjectLoaderCallback = void Function({required int progress, required int total, required LoadingState state});

enum LoadingState {
  /// Processing has not yet begun
  notStarted,
  /// New matches are downloading from remote sources
  downloadingMatches,
  /// Matches are being read from the database
  readingMatches,
  /// Scores are being processed
  processingScores,
  /// Loading is complete
  done;

  String get label {
    switch(this) {
      case LoadingState.notStarted:
        return "not started";
      case LoadingState.downloadingMatches:
        return "downloading matches";
      case LoadingState.readingMatches:
        return "loading matches from database";
      case LoadingState.processingScores:
        return "processing scores";
      case LoadingState.done:
        return "finished";
    }
  }
}