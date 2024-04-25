/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
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
  final db = AnalystDatabase();
  RatingSystem get ratingSystem => project.settings.algorithm;

  MemberNumberCorrectionContainer get _dataCorrections => project.settings.memberNumberCorrections;

  RatingProjectLoader(this.project, this.callback);

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

    }

    return Result.ok(null);
  }

  Future<Result<void, RatingProjectLoadError>> _addMatch(ShootingMatch match) {
    return _addMatches([match]);
  }

  Future<Result<void, RatingProjectLoadError>> _addMatches(List<ShootingMatch> matches) async {
    for(var group in project.groups) {
      for (var match in matches) {
        // 1. For each match, add shooters.
        _addShootersFromMatch(group, match);
      }

      // 2. Deduplicate shooters.

      // 3. For each group...

      // 3.1. For each match...

      // 3.1.1. Check recognized divisions

      // 3.1.2. Rank match through code in Rater

      // 3.1.3. Update database with rating changes

      // 3.2. Remove unseen shooters

      // 3.2.1. Update database with unseen shooter removal
    }
    // 3.3. Calculate match stats

    return Result.ok(null);
  }

  /// Returns the number of shooters added or updated.
  ///
  /// Use [encounter] if you want shooters to be added regardless of whether they appear
  /// in scores. (i.e., shooters who DQ on the first stage, or are no-shows but still included in the data)
  Future<int> _addShootersFromMatch(DbRatingGroup group, ShootingMatch match, {bool encounter = false}) async {
    int added = 0;
    int updated = 0;
    var shooters = _getShooters(group, match);
    for(MatchEntry s in shooters) {
      var processed = Rater.processMemberNumber(s.memberNumber);
      var corrections = _dataCorrections.getByInvalidNumber(processed);
      var name = ShooterDeduplicator.processName(s);
      for(var correction in corrections) {
        if (correction.name == name) {
          processed = correction.correctedNumber;
          break;
        }
      }
      if(processed.isEmpty) {
        var emptyCorrection = _dataCorrections.getEmptyCorrectionByName(name);
        if(emptyCorrection != null) {
          processed = emptyCorrection.correctedNumber;
        }
      }
      if(processed.isNotEmpty && !s.reentry) {
        s.memberNumber = processed;
        var rating = await db.maybeKnownShooter(
          project: project,
          group: group,
          processedMemberNumber: s.memberNumber,
        );
        if(rating == null) {
          var newRating = ratingSystem.newShooterRating(s, sport: project.sport, date: match.date);
          await db.addShooterRating(
            rating: newRating,
            group: group,
            project: project,
          );
          added += 1;
          if(encounter) _encounteredMemberNumber(s.memberNumber);
        }
        else {
          // Update names for existing shooters on add, to eliminate the Mel Rodero -> Mel Rodero II problem in the L2+ set
          rating.firstName = s.firstName;
          rating.lastName = s.lastName;
          updated += 1;
        }
      }
    }

    return added + updated;
  }

  List<MatchEntry> _getShooters(DbRatingGroup group, ShootingMatch match, {bool verify = false}) {
    var filters = group.filters;
    var shooters = <MatchEntry>[];
    shooters = match.filterShooters(
      filterMode: filters.mode,
      divisions: filters.activeDivisions.toList(),
      powerFactors: [],
      classes: [],
      allowReentries: false,
    );

    for(var shooter in shooters) {
      shooter.memberNumber = Rater.processMemberNumber(shooter.memberNumber);
    }

    if(verify) {
      shooters.retainWhere((element) => _verifyShooter(element));
    }

    return shooters;
  }

  Map<Shooter, bool> _verifyCache = {};
  bool _verifyShooter(MatchEntry s) {
    if(_verifyCache.containsKey(s)) return _verifyCache[s]!;

    var finalMemberNumber = s.memberNumber;
    if(!byStage && s.dq) {
      _verifyCache[s] = false;
      return false;
    }
    if(s.reentry) {
      _verifyCache[s] = false;
      return false;
    }
    if(s.memberNumber.isEmpty) {
      var processedName = ShooterDeduplicator.processName(s);
      var emptyCorrection = _dataCorrections.getEmptyCorrectionByName(processedName);
      if(emptyCorrection != null) {
        finalMemberNumber = processMemberNumber(emptyCorrection.correctedNumber);
      }

      _verifyCache[s] = false;
      return false;
    }

    // This is already processed, because _verifyShooter is only called from _getShooters
    // after member numbers have been processed.
    String memNum = finalMemberNumber;

    if(maybeKnownShooter(memNum) == null) {
      _verifyCache[s] = false;
      return false;
    }
    if(memberNumberWhitelist.contains(memNum)) {
      _verifyCache[s] = true;
      return true;
    }

    // if(s.memberNumber.length <= 3) {
    //   _verifyCache[s] = false;
    //   return false;
    // }

    if(s.firstName.endsWith("2") || s.lastName.endsWith("2") || s.firstName.endsWith("3") || s.firstName.endsWith("3")) {
      _verifyCache[s] = false;
      return false;
    }

    _verifyCache[s] = true;
    return true;
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