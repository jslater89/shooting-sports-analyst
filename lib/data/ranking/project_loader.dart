/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzywuzzy;
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/connectivity.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_report.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("ProjectLoader");

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

class CanceledError extends RatingProjectLoadError {
  @override
  String get message => "User canceled loading";
}

class MatchLoadFailureError extends RatingProjectLoadError {
  final ResultErr underlying;
  final MatchLoadFailureCause cause;
  final DbShootingMatch? failedMatch;
  final MatchPointer? failedMatchPointer;

  MatchLoadFailureError({required this.cause, this.failedMatch, this.failedMatchPointer, required this.underlying}) {
    if(failedMatchPointer == null && failedMatch == null) {
      throw ArgumentError("At least one of failedMatch or failedMatchPointer must be provided");
    }
  }

  String get eventName {
    if(failedMatch != null) {
      return failedMatch!.eventName;
    }
    else if(failedMatchPointer != null) {
      return failedMatchPointer!.name;
    }
    else {
      return "(unknown)";
    }
  }

  @override
  String get message => "${cause.message} for $eventName (${underlying.runtimeType}: ${underlying.message})";
}

class DeduplicationError extends RatingProjectLoadError {
  String message;
  DeduplicationError(this.message);

  static Result<T, DeduplicationError> result<T>(String message) {
    return Result.err(DeduplicationError(message));
  }
}

typedef RatingProjectLoaderCallback = Future<void> Function({
  required int progress,
  required int total, 
  required LoadingState state, 
  String? eventName, 
  String? groupName,
  int? subProgress,
  int? subTotal,
});
typedef RatingProjectLoaderDeduplicationCallback = Future<Result<List<DeduplicationAction>, DeduplicationError>> Function(RatingGroup group, List<DeduplicationCollision> deduplicationResult);

typedef RatingProjectLoaderUnableToAppendCallback = Future<bool> Function(List<MatchPointer> lastUsedMatches, List<MatchPointer> newMatches);

typedef RatingProjectLoaderFullRecalculationRequiredCallback = Future<bool> Function();

/// RatingProjectLoaderHost contains a number of callbacks that the RatingProjectLoader
/// will call as it progresses, both to update the UI and to allow for user interaction
/// in cases where it is needed.
class RatingProjectLoaderHost {
  /// A callback for RatingProjectLoader progress. When progress and total are both 0, show no progress.
  /// When progress and total are both negative, show indeterminate progress. When total is positive,
  /// show determinate progress with progress as the counter.
  RatingProjectLoaderCallback progressCallback;

  /// A callback for when shooter deduplication is complete, and there are conflicts for the user to
  /// resolve. [deduplicationResult] is the list of detected, unresolved conflicts. The callback will be
  /// awaited by the project loader, and should return a list of actions to take to resolve the conflicts.
  /// 
  /// Return Result.ok if the conflicts are resolved and/or project loading should continue. Return
  /// Result.err if project loading should stop.
  RatingProjectLoaderDeduplicationCallback deduplicationCallback;

  /// A callback called if the user requested to add new matches without a full recalculation, but they
  /// cannot be appended. The callback should return true if the project should be recalculated anyway,
  /// or false if the loader should return 'complete' without adding any matches.
  RatingProjectLoaderUnableToAppendCallback unableToAppendCallback;

  /// A callback called if this project has not completed a full calculation, and the user requested a
  /// non-full recalculation. The callback should return true if the project should be recalculated
  /// anyway, or false if the loader should cancel the calculation.
  RatingProjectLoaderFullRecalculationRequiredCallback fullRecalculationRequiredCallback;

  RatingProjectLoaderHost({required this.progressCallback, required this.deduplicationCallback, required this.unableToAppendCallback, required this.fullRecalculationRequiredCallback});
}

// TODO (a big one): track ratings and events added during an 'append' calculation
// That way we can roll back on cancellation or error.
class RatingProjectLoader {
  final DbRatingProject project;
  final RatingProjectLoaderHost host;
  final db = AnalystDatabase();
  RatingProjectSettings get settings => project.settings;
  RatingSystem get ratingSystem => settings.algorithm;
  Sport get sport => project.sport;

  bool _canceled = false;

  Timings timings = Timings();

  MemberNumberCorrectionContainer get _dataCorrections => settings.memberNumberCorrections;
  List<String> get memberNumberWhitelist => settings.memberNumberWhitelist;

  RatingProjectLoader(this.project, this.host, {this.parallel = false});
  DateTime wallStart = DateTime.now();

  bool parallel;

  Future<Result<void, RatingProjectLoadError>> calculateRatings({bool fullRecalc = false}) async {
    wallStart = DateTime.now();

    HydratedMatchCache().clear();
    db.clearLoadedShooterRatingCache();
    timings.reset();

    // Convert DB fixed-length list to editable list
    project.automaticNumberMappings = [...project.automaticNumberMappings];

    var start = DateTime.now();
    await host.progressCallback(progress: -1, total: -1, state: LoadingState.readingMatches);

    var matchPointers = project.matchesToUse();

    // We want to add matches in ascending order, from oldest to newest.
    var matchesToAdd = matchPointers.sorted((a, b) => a.date!.compareTo(b.date!));

    // We're interested in the most recent match in addition to the full list,
    // so sort by descending date for convenience.
    var lastUsed = project.lastUsedMatches.sorted((a, b) => b.date!.compareTo(a.date!));
    bool canAppend = false;

    // TODO: check consistency of project settings and reset if needed
    // Things to check:
    // * project sport vs match sports

    if(_canceled) {
      return Result.err(CanceledError());
    }


    // If this project records a list of matches used to calculate ratings, we
    // may be able to append to it rather than running the full calculation.
    // If every match in [matchesToAdd] is after the most recent match in [lastUsed],
    // we can append.
    if(!fullRecalc && lastUsed.isNotEmpty) {
      // a match in matchesToAdd needs to be rated if no matches in lastUsed
      // share a source and any source IDs with it
      var missingMatches = matchesToAdd.where((m) =>
        lastUsed.none((l) =>
          l.sourceCode == m.sourceCode &&
          l.sourceIds.intersects(m.sourceIds)
        )
      ).toList();
      var mostRecentMatch = lastUsed.first;
      _log.i("Checking for append: cutoff date is ${mostRecentMatch.date}");
      canAppend = project.completedFullCalculation && !fullRecalc && missingMatches.every((m) => m.date!.isAfter(mostRecentMatch.date!));
      if(canAppend) {
        matchesToAdd = missingMatches;
      }
    }
    else {
      _log.i("No last used matches (first time calculation), or full recalculation requested");
    }

    // nothing to do
    if(matchesToAdd.isEmpty) {
      _log.i("No new matches");
      host.progressCallback(progress: 0, total: 0, state: LoadingState.done);
      timings.add(TimingType.wallTime, DateTime.now().difference(wallStart).inMicroseconds);
      return Result.ok(null);
    }

    if(!fullRecalc && !project.completedFullCalculation) {
      Timings().add(TimingType.wallTime, DateTime.now().difference(wallStart).inMicroseconds);
      var recalculate = await host.fullRecalculationRequiredCallback();
      wallStart = DateTime.now();
      if(!recalculate) {
        _log.i("User canceled calculation, returning canceled error");
        host.progressCallback(progress: 0, total: 0, state: LoadingState.done);
        return Result.err(CanceledError());
      }
    }
    else if(!canAppend && !fullRecalc) {
      Timings().add(TimingType.wallTime, DateTime.now().difference(wallStart).inMicroseconds);
      var recalculate = await host.unableToAppendCallback(lastUsed, matchesToAdd);
      wallStart = DateTime.now();
      if(!recalculate) {
        _log.i("User asked to advance without calculation, returning OK");
        host.progressCallback(progress: 0, total: 0, state: LoadingState.done);
        return Result.ok(null);
      }
    }

    if(!canAppend) {
      project.eventCount = 0;
      project.reports = [];
      project.completedFullCalculation = false;
      if(fullRecalc) {
        _log.i("Unable to append: full recalculation requested");
      }
      else if(!project.completedFullCalculation) {
        _log.i("Unable to append: project has not completed a full calculation");
      }
      else {
        _log.i("Unable to append: new matches occur before the last existing match");
      }
      await project.resetRatings();
    }
    else {
      // Fixed-length list on DB load
      project.reports = [...project.reports];
      _log.i("Appending ${matchesToAdd.length} matches to ratings");
    }

    var readMatchesSteps = matchesToAdd.length;
    var loadCompetitorsSteps = matchesToAdd.length * project.groups.length;
    // Main rating steps are 10 per group per match, because it's much harder than all the rest
    var mainRatingsSteps = project.groups.length * matchesToAdd.length * 10;
    var deduplicationSteps = project.groups.length;
    _totalMatchSteps = readMatchesSteps + loadCompetitorsSteps + mainRatingsSteps + deduplicationSteps;

    // If we're appending, matchesToAdd will be only the new matches.
    // If we're not appending, this will be all the matches, and
    // clearing the old list happens in the resetRatings call above.
    project.lastUsedMatches.addAll(matchesToAdd);
    await db.saveRatingProject(project, checkName: true);

    await host.progressCallback(
      progress: 0, 
      total: _totalMatchSteps, 
      state: LoadingState.readingMatches,
      subProgress: 0,
      subTotal: readMatchesSteps,
    );
    List<ShootingMatch> hydratedMatches = [];
    for(var matchPointer in matchesToAdd) {
      var dbMatch = await matchPointer.getDbMatch(db, downloadIfMissing: true);
      if(dbMatch.isErr()) {
        return Result.err(MatchLoadFailureError(
          cause: MatchLoadFailureCause.invalidData,
          failedMatchPointer: matchPointer,
          underlying: dbMatch.unwrapErr(),
        ));
      }
      
      var matchRes = dbMatch.unwrap().hydrate(useCache: true);
      if(matchRes.isErr()) {
        var err = matchRes.unwrapErr();
        return Result.err(MatchLoadFailureError(
          cause: MatchLoadFailureCause.invalidData,
          failedMatchPointer: matchPointer,
          underlying: err,
        ));
      }
      else {
        var match = matchRes.unwrap();
        hydratedMatches.add(match);
        _currentMatchStep += 1;
        await host.progressCallback(
          progress: _currentMatchStep, 
          total: _totalMatchSteps, 
          state: LoadingState.readingMatches,
          eventName: match.name,
          subProgress: hydratedMatches.length,
          subTotal: readMatchesSteps,
        );
      }
    }

    if(Timings.enabled) timings.add(TimingType.retrieveMatches, DateTime.now().difference(start).inMicroseconds);

    host.progressCallback(progress: 0, total: matchesToAdd.length, state: LoadingState.processingScores);
    var result = await _addMatches(hydratedMatches);
    if(result.isErr()) return Result.errFrom(result);

    _log.i("Cache hits: ${db.loadedShooterRatingCacheHits}");
    _log.i("Cache misses: ${db.loadedShooterRatingCacheMisses}");

    host.progressCallback(progress: 1, total: 1, state: LoadingState.done);
    timings.add(TimingType.wallTime, DateTime.now().difference(wallStart).inMicroseconds);

    project.completedFullCalculation = true;
    await db.saveRatingProject(project, checkName: true);
    return Result.ok(null);
  }

  void cancel() {
    _canceled = true;
  }

  Future<Result<void, RatingProjectLoadError>> _addMatch(ShootingMatch match) {
    return _addMatches([match]);
  }

  Future<Result<void, RatingProjectLoadError>> _addMatchCompetitorsToGroup(RatingGroup group, List<ShootingMatch> matches, {required int startingProgress}) async {
    Map<String, bool> memberNumbersSeen = {};
    List<DbShooterRating> newRatings = [];

    var subTotal = matches.length;
    var subProgress = 0;

    for (var match in matches) {
      // 1. For each match, add shooters.
      var (ratings, _) = await _addShootersFromMatch(group, match);

      subProgress += 1;
      _currentMatchStep += 1;
      if(subProgress % 2 == 0) {
        await host.progressCallback(
          progress: _currentMatchStep,
          total: _totalMatchSteps,
          state: LoadingState.addingCompetitors,
          eventName: match.name,
          groupName: group.name,
          subProgress: subProgress,
          subTotal: subTotal,
        );
      }

      if(_canceled) {
        return Result.err(CanceledError());
      }

      for(var r in ratings) {
        if(memberNumbersSeen[r.memberNumber] != true) {
          newRatings.add(r);
        }
        memberNumbersSeen[r.memberNumber] = true;
      }
    }

    // 2. Deduplicate shooters.
    var dedup = sport.shooterDeduplicator;
    if(dedup != null) {
      var start = DateTime.now();
      var dedupResult = await dedup.deduplicateShooters(
        ratingProject: project,
        group: group,
        newRatings: newRatings,
        progressCallback: (progress, total, description) async {
          if(progress == 0 || progress % (max(5, total ~/ 250)) == 0) {
            await host.progressCallback(
              progress: _currentMatchStep,
              total: _totalMatchSteps,
              state: LoadingState.deduplicatingCompetitors,
              eventName: description,
              groupName: group.name,
              subProgress: progress,
              subTotal: total,
            );
          }
        },
      );
      if(Timings.enabled) timings.add(TimingType.dedupShooters, DateTime.now().difference(start).inMicroseconds);

      if(dedupResult.isErr()) {
        return DeduplicationError.result(dedupResult.unwrapErr().message);
      }
      else {
        bool didSomething = false;
        var conflicts = dedupResult.unwrap();
        int resolvedInSettings = 0;
        for(var conflict in conflicts) {
          if(conflict.causes.length == 1 && conflict.causes.first is FixedInSettings) {
            resolvedInSettings += 1;
            for(var action in conflict.proposedActions) {
              didSomething = true;
              await _applyDeduplicationAction(group, action);
            }
          }
        }

        _log.i("Resolved $resolvedInSettings conflicts (of ${conflicts.length}) in settings");
        conflicts.removeWhere((c) => c.causes.length == 1 && c.causes.first is FixedInSettings);

        if(conflicts.length > 0) {
          Timings().add(TimingType.wallTime, DateTime.now().difference(wallStart).inMicroseconds);
          var userDedupResult = await host.deduplicationCallback(group, conflicts);
          wallStart = DateTime.now();
          if(userDedupResult.isErr()) {
            return DeduplicationError.result(userDedupResult.unwrapErr().message);
          }

          var actions = userDedupResult.unwrap();
          for(var action in actions) {
            didSomething = true;
            await _applyDeduplicationAction(group, action);
          }
        }

        if(didSomething) {
          project.changedSettings();
          db.saveRatingProject(project, checkName: true);
        }
      }
    }

    return Result.ok(null);
  }

  int _totalMatchSteps = 0;
  int _currentMatchStep = 0;
  Future<Result<int, RatingProjectLoadError>> _addMatchScoresToGroup(RatingGroup group, List<ShootingMatch> matches) async {
    var subTotal = matches.length;
    var subProgress = 0;

    // At this point we have an accurate count of shooters so far, which we'll need for various maths.
    var shooterCount = await AnalystDatabase().countShooterRatings(project, group);

    int changeCount = 0;

    var start = DateTime.now();
    for (var match in matches) {
      if(_canceled) {
        return Result.err(CanceledError());
      }
      // 3.1.1. Check recognized divisions
      var onlyDivisions = settings.recognizedDivisions[match.sourceIds.first];
      if(onlyDivisions != null) {
        var divisionsOfInterest = group.filters.divisions.entries.where((e) => e.value).map((e) => e.key).toList();

        // Process this iff onlyDivisions contains at least one division of interest
        // e.g. this rater/dOI is prod, oD is open/limited; oD contains 0 of dOI, so
        // skip.
        //
        // e.g. this rater/dOI is lim/CO, oD is open/limited; oD contains 1 of dOI,
        // so don't skip.
        bool skip = true;
        for(var d in divisionsOfInterest) {
          if(onlyDivisions.contains(d)) {
            skip = false;
            break;
          }
        }
        if(skip) {
          continue;
        }
      }

      // 3.1.2. Rank match through code in Rater
      // TODO: may be possible to remove this 'await' once everything is working
      // May allow some processing to proceed in 'parallel', or at least while DB
      // operations are happening
      _currentMatchStep += 10;
      subProgress += 1;
      await host.progressCallback(
        progress: _currentMatchStep,
        total: _totalMatchSteps,
        state: LoadingState.processingScores,
        eventName: match.name,
        groupName: group.name,
        subProgress: subProgress,
        subTotal: subTotal,
      );
      changeCount += await _rankMatch(group, match);
    }

    var count = await db.countShooterRatings(project, group);
    if(Timings.enabled) timings.add(TimingType.rateMatches, DateTime.now().difference(start).inMicroseconds);
    _log.i("Initial ratings complete for $count shooters in ${matches.length} matches in ${group.filters.activeDivisions}");

    // 3.2. DB-delete any shooters we added who recorded no scores in any matches in
    // this group.

    return Result.ok(changeCount);
  }

  /// Applies a deduplication action to the project.
  /// 
  /// UNLIKE the pre-DB code, this function is responsible for handling any competitor
  /// merges required by the action, IN ADDITION TO updating the project settings.
  /// 
  /// (Since we've already added new ratings, we need to delete any redundant ones and make
  /// sure any new ones are updated before we advance to calculating ratings.)
  Future<void> _applyDeduplicationAction(RatingGroup group, DeduplicationAction action) async {
    switch(action.runtimeType) {
      // For mappings, we need to delete any source ratings, make sure the target has all relevant
      // member numbers, and copy any data we're missing to the target.
      case UserMapping || AutoMapping:
        // Update the project settings for this mapping
        var mapping = action as Mapping;
        if(mapping is UserMapping) {
          for(var sourceNumber in mapping.sourceNumbers) {
            var existingMapping = settings.userMemberNumberMappings[sourceNumber];
            settings.userMemberNumberMappings[sourceNumber] = mapping.targetNumber;
            if(existingMapping != null) {
              settings.userMemberNumberMappings[existingMapping] = mapping.targetNumber;
              mapping.sourceNumbers.add(existingMapping);
            }
          }

          // If this overrides any automatic mappings, remove them.
          project.automaticNumberMappings.removeWhere((autoMapping) => autoMapping.sourceNumbers.any((number) => mapping.sourceNumbers.contains(number)));
        }
        else {
          mapping as AutoMapping;
          List<DbMemberNumberMapping> mappings = [];
          for(var sourceNumber in mapping.sourceNumbers) {
            var existingMapping = project.lookupAutomaticNumberMapping(sourceNumber);
            if(existingMapping != null) {
              mappings.add(existingMapping);
            }
          }

          Set<String> sourceNumbers = {};
          for(var m in mappings) {
            sourceNumbers.addAll(m.sourceNumbers);
          }
          sourceNumbers.addAll(mapping.sourceNumbers);

          mapping.sourceNumbers.clear();
          mapping.sourceNumbers.addAll(sourceNumbers);
          var newMapping = DbMemberNumberMapping(
            sourceNumbers: sourceNumbers.toList(),
            targetNumber: mapping.targetNumber,
          );
          var autoMappings = [...project.automaticNumberMappings];
          autoMappings.removeWhere((m) => mappings.contains(m));
          autoMappings.add(newMapping);
          project.automaticNumberMappings = autoMappings;
        }

        // Find any competitors who match sourceNumber and copy their data to the
        // target number.
        List<Future<DbShooterRating?>> futures = [];
        for(var sourceNumber in mapping.sourceNumbers) {
          // maybeKnownShooter here, because we might not have added all of the mapping sources yet.
          futures.add(db.maybeKnownShooter(
            project: project,
            group: group,
            memberNumber: sourceNumber,
            usePossibleMemberNumbers: true,
            useCache: true,
          ));
        }
        var ratings = (await Future.wait(futures)).whereNotNull().toList();

        // knownShooter here, because the target number came from the set of ratings known to the
        // deduplicator.
        var targetRating = await db.knownShooter(
          project: project,
          group: group,
          memberNumber: mapping.targetNumber,
          usePossibleMemberNumbers: true,
          useCache: true,
        );
        
        // Add all of the source numbers to the target's known list
        targetRating.addKnownMemberNumbers(mapping.sourceNumbers);

        // For every source rating we can find, copy its member numbers to the target and
        // delete it.
        // If the rating has history, increment a count so we can warn the user that a full
        // recalculation will be necessary for accuracy. In the meantime, copy from the longest
        // rating to this one.
        // TODO: check what the old code did re: copying rating events
        List<DbShooterRating> ratingsWithHistory = [];
        for(var r in ratings) {
          if(r.length > 0) {
            ratingsWithHistory.add(r);

            if(r.length > targetRating.length) {
              targetRating.copyRatingFrom(r);
            }
          }
          // TODO: copy vitals where sensible to do so
          // based on last seen/first seen

          targetRating.addKnownMemberNumbers(r.knownMemberNumbers);
          await db.deleteShooterRating(r);
        }

        if(ratingsWithHistory.length > 1) {
          var report = RatingReport(
            type: RatingReportType.ratingMergeWithDualHistory,
            severity: RatingReportSeverity.warning,
            data: RatingMergeWithDualHistory(
              ratingIds: ratingsWithHistory.map((r) => r.id).toList(),
              ratingGroupUuid: group.uuid,
            ),
          );
          project.reports.add(report);
        }

        await db.upsertDbShooterRating(targetRating, linksChanged: false);

        break;
      case Blacklist:
        // For blacklists, we might (i.e., will; I'm in the middle of fixing it) run into cases where a
        // prior mapping and data entry fix conflict. Say A123456 enters member number L5432, and we
        // auto-map that. Then we find that the competitor's number is actually L1234, and he enters it
        // that way later. So, we'll present the user with a blacklist L5432 -> L1234. At that point,
        // if there's a rating that has both blacklisted numbers, we need to remove one.
        //
        // Only I'm not actually sure how we pick the right one, or what we show to the user.
        var blacklist = action as Blacklist;

        settings.memberNumberMappingBlacklist.addToListIfMissing(blacklist.sourceNumber, blacklist.targetNumber);
        if(blacklist.bidirectional) {
          settings.memberNumberMappingBlacklist.addToListIfMissing(blacklist.targetNumber, blacklist.sourceNumber);
        }
        break;
      case DataEntryFix:
        // For data entry fixes, we want to delete a source rating if its name matches the deduplicator name.
        // Before we do that, though, we want to copy all of the member numbers except the source of this
        // fix from the old one, in case it has accumulated other member numbers before the first erroneous
        // data entry.
        //
        // There's code here to update mappings pointing to the source number, but I don't think we can
        // include it generally, since fixes specify a name and mappings don't—it's possible we would be
        // 'fixing' a valid mapping for a different competitor.
        // TODO: test for this case
        var fix = action as DataEntryFix;
        settings.memberNumberCorrections.add(fix.intoCorrection());
        
        // If we enter e.g. FY115519, we also want to catch cases where the user enters A155519 or TY115519,
        // but we don't want to make a mapping that maps the same number to itself.
        var alternateForms = sport.shooterDeduplicator?.alternateForms(fix.sourceNumber) ?? [];
        alternateForms.removeWhere((n) => n == fix.sourceNumber);
        for(var number in alternateForms) {
          var corrections = settings.memberNumberCorrections.getByName(fix.deduplicatorName);
          bool found = false;
          for(var correction in corrections) {
            if(correction.invalidNumber == number) {
              found = true;
              break;
            }
          }
          if(!found) {
            settings.memberNumberCorrections.add(MemberNumberCorrection(
              name: fix.deduplicatorName,
              invalidNumber: number,
              correctedNumber: fix.targetNumber,
            ));
          }
        }

        var sourceRating = await db.maybeKnownShooter(
          project: project,
          group: group,
          memberNumber: fix.sourceNumber,
          useCache: true,
        );
        if(sourceRating != null && sourceRating.deduplicatorName == fix.deduplicatorName) {
          var targetRating = await db.maybeKnownShooter(
            project: project,
            group: group,
            memberNumber: fix.targetNumber,
            useCache: true,
          );
          if(targetRating != null) {
            if(sourceRating.knownMemberNumbers.any((n) => !targetRating.knownMemberNumbers.contains(n))) {
              targetRating.addKnownMemberNumbers(sourceRating.knownMemberNumbers);
              await db.upsertDbShooterRating(targetRating);
            }
          }
          await db.deleteShooterRating(sourceRating);
        }

        // var mapping = project.lookupAutomaticNumberMapping(fix.sourceNumber);
        // if(mapping != null) {
        //   mapping.sourceNumbers = [...mapping.sourceNumbers.where((n) => n != fix.sourceNumber), fix.targetNumber];
        // }
        // mapping = project.lookupAutomaticNumberMappingByTarget(fix.sourceNumber);
        // if(mapping != null) {
        //   mapping.targetNumber = fix.targetNumber;
        // }

        // var userMapping = settings.userMemberNumberMappings[fix.sourceNumber];
        // if(userMapping != null) {
        //   settings.userMemberNumberMappings[fix.targetNumber] = userMapping;
        //   settings.userMemberNumberMappings.remove(fix.sourceNumber);
        // }
        // userMapping = settings.userMemberNumberMappings.entries.firstWhereOrNull((e) => e.value == fix.sourceNumber)?.key;
        // if(userMapping != null) {
        //   settings.userMemberNumberMappings[userMapping] = fix.targetNumber;
        // }

        break;
    }
  }

  Future<Result<void, RatingProjectLoadError>> _addMatches(List<ShootingMatch> matches) async {
    host.progressCallback(
      progress: _currentMatchStep,
      total: _totalMatchSteps,
      state: LoadingState.addingCompetitors,
    );
    int groupStep = 0;
    for(var group in project.groups) {
      _currentMatchStep += 1;

      var result = await _addMatchCompetitorsToGroup(group, matches, startingProgress: groupStep * matches.length);
      if(result.isErr()) return result;
      groupStep += 1;
    }

    List<Future<Result<int, RatingProjectLoadError>>> futures = [];
    int changeCount = 0;
    if(parallel) {
      for(var group in project.groups) {
        futures.add(_addMatchScoresToGroup(group, matches));
        // var result = await _addMatchScoresToGroup(group, matches);
        // if(result.isErr()) return result;
      }
      var results = await Future.wait(futures);
      for(var result in results) {
        if(result.isErr()) return result;
        changeCount += result.unwrap();
      }
    }
    else {
      for(var group in project.groups) {
        var result = await _addMatchScoresToGroup(group, matches);
        if(result.isErr()) return result;
        changeCount += result.unwrap();
      }
    }

    project.eventCount += changeCount;

    if(Timings.enabled) timings.matchCount += matches.length;

    // 3.3. Calculate match stats
    List<int> matchLengths = [];
    List<int> matchRoundCounts = [];
    List<int> stageRoundCounts = [];
    List<double> dqsPer100 = [];

    for(var m in matches) {
      var totalRounds = 0;
      var stages = 0;
      for(var s in m.stages) {
        if(s.scoring is IgnoredScoring) continue;

        stages += 1;
        totalRounds += s.minRounds;
        stageRoundCounts.add(s.minRounds);

        if(s.minRounds <= 4) _log.d("${m.name} ${s.name} ${s.minRounds}rds");
      }
      matchLengths.add(stages);
      matchRoundCounts.add(totalRounds);

      int dqs = 0;
      for(var s in m.shooters) {
        if(s.dq) dqs += 1;
      }
      dqsPer100.add(dqs * (100 / m.shooters.length));

    }

    matchLengths.sort();
    matchRoundCounts.sort();
    stageRoundCounts.sort();
    dqsPer100.sort();

    var matchLengthMode = mode(matchLengths);
    var stageRoundsMode = mode(stageRoundCounts);
    var matchRoundsMode = mode(matchRoundCounts);

    _log.i("Match length in stages (min/max/average/median/mode): ${matchLengths.min}/${matchLengths.max}/${matchLengths.average.toStringAsFixed(1)}/${matchLengths[matchLengths.length ~/ 2]}/$matchLengthMode");
    _log.i("Match length in rounds (average/median/mode): ${matchRoundCounts.min}/${matchRoundCounts.max}/${matchRoundCounts.average.toStringAsFixed(1)}/${matchRoundCounts[matchRoundCounts.length ~/ 2]}/$matchRoundsMode");
    _log.i("Stage length in rounds (average/median/mode): ${stageRoundCounts.min}/${stageRoundCounts.max}/${stageRoundCounts.average.toStringAsFixed(1)}/${stageRoundCounts[stageRoundCounts.length ~/ 2]}/$stageRoundsMode");
    _log.i("DQs per 100 shooters (average/median): ${dqsPer100.min.toStringAsFixed(3)}/${dqsPer100.max.toStringAsFixed(3)}/${dqsPer100.average.toStringAsFixed(3)}/${dqsPer100[dqsPer100.length ~/ 2].toStringAsFixed(3)}");

    return Result.ok(null);
  }

  /// Returns the number of shooters added or updated.
  ///
  /// Use [encounter] if you want shooters to be added regardless of whether they appear
  /// in scores. (i.e., shooters who DQ on the first stage, or are no-shows but still included in the data)
  Future<(List<DbShooterRating>, int)> _addShootersFromMatch(RatingGroup group, ShootingMatch match) async {
    var start = DateTime.now();
    int added = 0;
    int updated = 0;
    var shooters = await _getShooters(group, match);
    List<DbShooterRating> newRatings = [];
    for(MatchEntry s in shooters) {
      // Process the member number:
      // First, normalize it according to the sport's rules.
      var processed = sport.shooterDeduplicator?.processNumber(s.memberNumber) ?? ShooterDeduplicator.normalizeNumberBasic(s.memberNumber);

      // Apply data corrections, checking each subsequent target for corrections where
      // it is the source, until we find no more corrections.
      var name = ShooterDeduplicator.processName(s);

      Set<String> invalidMemberNumbers = {};
      Set<String> previouslyVisitedNumbers = {processed};
      bool dataEntryFixLoop = false;
      while(true) {
        // If there are data corrections for this member number, apply them.
        var corrections = _dataCorrections.getByInvalidNumber(processed);
        bool appliedCorrection = false;
        for(var correction in corrections) {
          if(correction.name == name) {
            if(processed == correction.correctedNumber) {
              // This is a no-op fix ("If johndoe enters A123456, use A123456"),
              // which we should prompt the user to remove eventually, but for now,
              // skip it.
              break;
            }
            if(previouslyVisitedNumbers.contains(correction.correctedNumber)) {
              dataEntryFixLoop = true;
              break;
            }
            invalidMemberNumbers.add(correction.invalidNumber);
            s.removeKnownMemberNumbers(_alternateForms(correction.invalidNumber));
            processed = correction.correctedNumber;
            previouslyVisitedNumbers.add(processed);
            appliedCorrection = true;
            break;
          }
        }
        if(!appliedCorrection) break;
      }

      // If the member number is empty, see if this is someone we've special-cased
      // in case they enter an empty one. (IPSC competitors in the US, mainly.)
      if(processed.isEmpty) {
        var emptyCorrection = _dataCorrections.getEmptyCorrectionByName(name);
        if(emptyCorrection != null) {
          processed = emptyCorrection.correctedNumber;
        }
      }

      // Something like "B9" is on the outside edge of plausible member numbers,
      // but there are a lot of competitors in USPSA sets with numbers like "A",
      // or "0", which we want to leave out to avoid cluttering blacklists.
      bool validCompetitor = processed.length > 1 && !s.reentry;
      List<String> mappingSources = [];
      if(validCompetitor) {
        // If we have a member number after processing, we can use this competitor.
        s.memberNumber = processed;

        // Look for valid mappings (user first, then auto), and apply them if found.
        var possibleNumbers = _alternateForms(s.memberNumber);
        String? mappingTarget;
        for(var number in possibleNumbers) {
          mappingTarget = settings.userMemberNumberMappings[number];
          if(mappingTarget != null) {
            break;
          }

          var automaticMapping = project.lookupAutomaticNumberMapping(number);
          if(automaticMapping != null) {
            mappingTarget = automaticMapping.targetNumber;
            break;
          }
        }
        if(mappingTarget != null) {
          s.memberNumber = mappingTarget;
        }

        while(true) {
        // If there are data corrections for the mapped member number, fix that
        // now.
          var corrections = _dataCorrections.getByInvalidNumber(s.memberNumber);
          bool appliedCorrection = false;
          for(var correction in corrections) {
            if(processed == correction.correctedNumber) {
              // This is a no-op fix ("If johndoe enters A123456, use A123456"),
              // which we should prompt the user to remove eventually, but for now,
              // skip it.
              break;
            }
            if(correction.name == name) {
              if(previouslyVisitedNumbers.contains(correction.correctedNumber)) {
                dataEntryFixLoop = true;
                break;
              }
              s.memberNumber = correction.correctedNumber;
              s.removeKnownMemberNumbers(_alternateForms(correction.invalidNumber));
              invalidMemberNumbers.add(correction.invalidNumber);
              previouslyVisitedNumbers.add(correction.correctedNumber);
              appliedCorrection = true;
              break;
            }
          }
          if(!appliedCorrection) break;
        }

        if(dataEntryFixLoop) {
          _log.e("Data entry fix loop detected for ${s.memberNumber}: ${previouslyVisitedNumbers.join(", ")}");
          var report = RatingReport(
            type: RatingReportType.dataEntryFixLoop,
            severity: RatingReportSeverity.severe,
            data: DataEntryFixLoop(numbers: previouslyVisitedNumbers.toList()),
          );
          project.reports.add(report);
        }

        var rating = await db.maybeKnownShooter(
          project: project,
          group: group,
          memberNumber: s.memberNumber,
          usePossibleMemberNumbers: true,
          useCache: true,
        );

        if(rating == null) {
          var newRating = ratingSystem.newShooterRating(s, sport: project.sport, date: match.date);
          newRating.allPossibleMemberNumbers.addAll(possibleNumbers);
          await db.newShooterRatingFromWrapped(
            rating: newRating,
            group: group,
            project: project,
          );
          newRatings.add(newRating.wrappedRating);
          added += 1;
        }
        else {
          rating.removeKnownMemberNumbers(invalidMemberNumbers);

          var sName = ShooterDeduplicator.processName(s);
          if(fuzzywuzzy.weightedRatio(rating.deduplicatorName, sName) < 50) {
            _log.w("$s matches $rating by member number, but names have high string difference");
            var report = RatingReport(
              type: RatingReportType.stringDifferenceNameForSameNumber,
              severity: RatingReportSeverity.info,
              data: StringDifferenceNameForSameNumber(
                names: [rating.deduplicatorName, sName],
                number: s.memberNumber,
                ratingGroupUuid: group.uuid,
              ),
            );
            project.reports.add(report);
          }

          // Update names for existing shooters on add, to eliminate the Mel Rodero -> Mel Rodero II problem in the L2+ set
          rating.firstName = s.firstName;
          rating.lastName = s.lastName;
          // prefer to display newer member numbers
          rating.memberNumber = s.memberNumber;
          rating.addKnownMemberNumbers(s.knownMemberNumbers);

          // TODO: only if better than last classification
          // may require some help from [sport]
          rating.lastClassification = s.classification;
          rating.division = s.division;
          rating.ageCategory = s.ageCategory;

          if(match.date.isAfter(rating.lastSeen)) {
            rating.lastSeen = match.date;
          }
          updated += 1;
          
          // We asked for allPossibleMemberNumbers, so if this member number isn't
          // in the knownMemberNumbers list, add it.
          if(!rating.knownMemberNumbers.contains(s.memberNumber)) {
            rating.knownMemberNumbers.add(s.memberNumber);
          }

          await db.upsertDbShooterRating(rating);
        }
      }
    }

    if(Timings.enabled) {
      timings.add(TimingType.addShooters, DateTime.now().difference(start).inMicroseconds);
      timings.shooterCount += added;
      timings.matchEntryCount += shooters.length;
    }

    return (newRatings, added + updated);
  }

  Future<List<MatchEntry>> _getShooters(RatingGroup group, ShootingMatch match, {bool verify = false}) async {
    var filters = group.filters;
    var shooters = <MatchEntry>[];
    shooters = match.filterShooters(
      filterMode: filters.mode,
      divisions: filters.activeDivisions.toList(),
      powerFactors: [],
      classes: [],
      allowReentries: false,
    );

    var numberProcessor = ShooterDeduplicator.numberProcessor(sport);
    for(var shooter in shooters) {
      shooter.memberNumber = numberProcessor(shooter.memberNumber);
    }

    if(verify) {
      await shooters.retainWhereAsync((element) async => await _verifyShooter(group, element));
    }

    return shooters;
  }

  Map<Shooter, bool> _verifyCache = {};
  Future<bool> _verifyShooter(RatingGroup g, MatchEntry s) async {
    if(_verifyCache.containsKey(s)) return _verifyCache[s]!;

    var finalMemberNumber = s.memberNumber;
    if(!project.settings.byStage && s.dq) {
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
        var numberProcessor = sport.shooterDeduplicator?.processNumber ?? ShooterDeduplicator.normalizeNumberBasic;
        finalMemberNumber = numberProcessor(emptyCorrection.correctedNumber);
      }

      _verifyCache[s] = false;
      return false;
    }

    // This is already processed, because _verifyShooter is only called from _getShooters
    // after member numbers have been processed.
    String memNum = finalMemberNumber;

    var rating = await db.maybeKnownShooter(
      project: project,
      group: g,
      memberNumber: finalMemberNumber,
      useCache: true,
    );
    if(rating == null) {
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

  double get _centerStrength => sport.ratingStrengthProvider?.centerStrength ?? 1.0;

  /// Returns the number of rating changes.
  Future<int> _rankMatch(RatingGroup group, ShootingMatch match) async {
    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    var shooters = await _getShooters(group, match, verify: true);
    var scores = match.getScores(shooters: shooters, scoreDQ: settings.byStage);

    // Skip when a match has no shooters in a group
    if(shooters.length == 0 && scores.length == 0) {
      return 0;
    }

    if(Timings.enabled) timings.add(TimingType.getShootersAndScores, DateTime.now().difference(start).inMicroseconds);

    if(Timings.enabled) start = DateTime.now();
    // Based on strength of competition, vary rating gain between 25% and 150%.
    double strengthMod = 1.0;
    if(sport.ratingStrengthProvider != null) {
      var matchStrength = 0.0;
      for(var shooter in shooters) {
        matchStrength += sport.ratingStrengthProvider?.strengthForClass(shooter.classification) ?? 1.0;

        // Update
        var rating = await AnalystDatabase().maybeKnownShooter(
          project: project,
          group: group,
          memberNumber: shooter.memberNumber,
          useCache: true,
        );
        if(rating != null) {
          if(shooter.classification != null) {
            if(rating.lastClassification == null || shooter.classification!.index < rating.lastClassification!.index) {
              rating.lastClassification = shooter.classification!;
            }
          }

          // Update the shooter's name: the most recent one is probably the most interesting/useful
          rating.firstName = shooter.firstName;
          rating.lastName = shooter.lastName;

          // Update age categories
          rating.ageCategory = shooter.ageCategory;

          // Update the shooter's member number: the CSV exports are more useful if it's the most
          // recent one. // TODO: this would be handy, but it changes the math somehow (not removing unseen?)
          // TODO: DB column for
          // rating.shooter.memberNumber = shooter.memberNumber;
        }
      }
      matchStrength = matchStrength / shooters.length;
      double levelStrengthBonus = sport.ratingStrengthProvider?.strengthBonusForMatchLevel(match.level) ?? 1.0;
      strengthMod =  (1.0 + max(-0.75, min(0.5, ((matchStrength) - _centerStrength) * 0.2))) * (levelStrengthBonus);
    }
    if(Timings.enabled) timings.add(TimingType.calcMatchStrength, DateTime.now().difference(start).inMicroseconds);

    Map<String, ShooterRating> wrappedRatings = {};
    if(Timings.enabled) start = DateTime.now();
    // Based on connectedness, vary rating gain between 80% and 120%
    double connectednessMod = 1.0;
    if(sport.connectivityCalculator != null) {
      List<double> connectivityScores = [];
      for(var shooter in shooters) {
        var rating = await AnalystDatabase().maybeKnownShooter(
          project: project,
          group: group,
          memberNumber: shooter.memberNumber,
          useCache: true,
        );
        if(rating != null) {
          connectivityScores.add(rating.connectivity);
          wrappedRatings[shooter.memberNumber] = ratingSystem.wrapDbRating(rating);
        }
      }
      
      if(connectivityScores.isNotEmpty) {
        var baseline = project.connectivityContainer.getConnectivity(group, defaultValue: sport.connectivityCalculator!.defaultBaselineConnectivity);
        var matchConnectivity = sport.connectivityCalculator!.calculateMatchConnectivity(connectivityScores);
        connectednessMod = sport.connectivityCalculator!.getScaleFactor(connectivity: matchConnectivity, baseline: baseline);
        // _log.vv("Connectivity/baseline/mod before match: ${matchConnectivity.toStringAsFixed(1)}/${baseline.toStringAsFixed(1)}/${connectednessMod.toStringAsFixed(3)}");
      }
    }
    else {
      // We need to wrap ratings even if we don't have a connectivity calculator.
      // Done separately (rather than once, before the loop) to save a match's
      // worth of map accesses in the loop.
      for(var shooter in shooters) {
        var rating = await AnalystDatabase().maybeKnownShooter(
          project: project,
          group: group,
          memberNumber: shooter.memberNumber,
          useCache: true,
        );
        if(rating != null) {
          wrappedRatings[shooter.memberNumber] = ratingSystem.wrapDbRating(rating);
        }
      }
    }
    
    if(Timings.enabled) timings.add(TimingType.calcConnectedness, DateTime.now().difference(start).inMicroseconds);

    Map<DbShooterRating, Map<RelativeScore, RatingEvent>> changes = {};
    Set<DbShooterRating> shootersAtMatch = Set();
    int changeCount = 0;

    if(Timings.enabled) start = DateTime.now();
    // Process ratings for each shooter.
    if(settings.byStage) {
      for(MatchStage s in match.stages) {

        var innerStart = DateTime.now();
        var (filteredShooters, filteredScores) = _filterScores(shooters, scores.values.toList(), s);

        var weightMod = 1.0 + max(-0.20, min(0.10, (s.maxPoints - 120) /  400));

        Map<ShooterRating, RelativeScore> stageScoreMap = {};
        Map<ShooterRating, RelativeMatchScore> matchScoreMap = {};

        for(var score in filteredScores) {
          String num = score.shooter.memberNumber;
          var stageScore = score.stageScores[s]!;
          var rating = wrappedRatings[num]!;
          stageScoreMap[rating] = stageScore;
          matchScoreMap[rating] = score;
        }
        if(Timings.enabled) timings.add(TimingType.scoreMap, DateTime.now().difference(innerStart).inMicroseconds);

        if(ratingSystem.mode == RatingMode.wholeEvent) {
          await _processWholeEvent(
              match: match,
              group: group,
              stage: s,
              wrappedRatings: wrappedRatings,
              scores: filteredScores,
              changes: changes,
              matchStrength: strengthMod,
              connectednessMod: connectednessMod,
              weightMod: weightMod
          );
        }
        else {
          for(int i = 0; i < filteredShooters.length; i++) {
            if(ratingSystem.mode == RatingMode.roundRobin) {
              _processRoundRobin(
                match: match,
                stage: s,
                wrappedRatings: wrappedRatings,
                shooters: filteredShooters,
                scores: filteredScores,
                startIndex: i,
                changes: changes,
                matchStrength: strengthMod,
                connectednessMod: connectednessMod,
                weightMod: weightMod,
              );
            }
            else {
              _processOneshot(
                  match: match,
                  stage: s,
                  wrappedRatings: wrappedRatings,
                  shooter: filteredShooters[i],
                  scores: filteredScores,
                  stageScores: stageScoreMap,
                  matchScores: matchScoreMap,
                  changes: changes,
                  matchStrength: strengthMod,
                  connectednessMod: connectednessMod,
                  weightMod: weightMod
              );
            }
          }
        }

        var persistStart = DateTime.now();
        changeCount += changes.length;
        for(var r in changes.keys) {
          var changeStart = DateTime.now();
          if(!r.events.isLoaded) await r.events.load();
          if(Timings.enabled) timings.add(TimingType.loadEvents, DateTime.now().difference(changeStart).inMicroseconds);

          changeStart = DateTime.now();
          var wrapped = ratingSystem.wrapDbRating(r);
          wrapped.updateFromEvents(changes[r]!.values.toList());
          wrapped.updateTrends(changes[r]!.values.toList());
          shootersAtMatch.add(r);
          if(Timings.enabled) timings.add(TimingType.applyChanges, DateTime.now().difference(changeStart).inMicroseconds);
        }

        var updateStart = DateTime.now();
        await AnalystDatabase().updateChangedRatings(changes.keys);
        if(Timings.enabled) timings.add(TimingType.updateDbRatings, DateTime.now().difference(updateStart).inMicroseconds);
        if(Timings.enabled) timings.add(TimingType.persistRatingChanges, DateTime.now().difference(persistStart).inMicroseconds);

        changes.clear();
      }
    }
    else { // by match
      var (filteredShooters, filteredScores) = _filterScores(shooters, scores.values.toList(), null);

      Map<ShooterRating, RelativeMatchScore> matchScoreMap = {};

      for(var score in filteredScores) {
        String num = score.shooter.memberNumber;
        matchScoreMap[wrappedRatings[num]!] = score;
      }

      if(ratingSystem.mode == RatingMode.wholeEvent) {
        await _processWholeEvent(
            match: match,
            group: group,
            stage: null,
            wrappedRatings: wrappedRatings,
            scores: filteredScores,
            changes: changes,
            matchStrength: strengthMod,
            connectednessMod: connectednessMod,
            weightMod: 1.0
        );
      }
      else {
        for(int i = 0; i < filteredShooters.length; i++) {
          if(ratingSystem.mode == RatingMode.roundRobin) {
            _processRoundRobin(
              match: match,
              stage: null,
              wrappedRatings: wrappedRatings,
              shooters: filteredShooters,
              scores: filteredScores,
              startIndex: i,
              changes: changes,
              matchStrength: strengthMod,
              connectednessMod: connectednessMod,
              weightMod: 1.0,
            );
          }
          else {
            _processOneshot(
                match: match,
                stage: null,
                wrappedRatings: wrappedRatings,
                shooter: filteredShooters[i],
                scores: filteredScores,
                stageScores: matchScoreMap,
                matchScores: matchScoreMap,
                changes: changes,
                matchStrength: strengthMod,
                connectednessMod: connectednessMod,
                weightMod: 1.0
            );
          }
        }
      }

      changeCount += changes.length;
      for(var r in changes.keys) {
        var wrapped = ratingSystem.wrapDbRating(r);
        wrapped.updateFromEvents(changes[r]!.values.toList());
        wrapped.updateTrends(changes[r]!.values.toList());
        shootersAtMatch.add(r);
      }

      AnalystDatabase().updateChangedRatings(changes.keys);
      changes.clear();
    }
    if(Timings.enabled) timings.add(TimingType.rateShooters, DateTime.now().difference(start).inMicroseconds);

    // Update connectivity
    if(Timings.enabled) start = DateTime.now();
    List<Future<void>> futures = [];
    if(shooters.length > 1 && sport.connectivityCalculator != null) {
      var calc = sport.connectivityCalculator!;
      Set<int> uniqueIds = {...shootersAtMatch.map((e) => e.id)};
      for(var rating in shootersAtMatch) {
        var ids = uniqueIds.where((id) => id != rating.id).toList();
        var window = MatchWindow.createFromHydratedMatch(
          match: match,
          uniqueOpponentIds: ids,
          totalOpponents: ids.length,
        );

        MatchWindow? oldestWindow;
        // While we have more than 4 match windows, remove the oldest one.
        var editableList = rating.matchWindows.toList();
        while(editableList.length > (calc.matchWindowCount - 1)) {
          for(var window in editableList) {
            if(oldestWindow == null || window.date.isBefore(oldestWindow.date)) {
              oldestWindow = window;
            }
          }
          if(oldestWindow != null) {
            editableList.remove(oldestWindow);
            oldestWindow = null;
          }
        }
        editableList.add(window);
        rating.matchWindows = editableList;

        var newConnectivity = calc.calculateRatingConnectivity(rating);
        rating.connectivity = newConnectivity.connectivity;
        rating.rawConnectivity = newConnectivity.rawConnectivity;

        futures.add(AnalystDatabase().upsertDbShooterRating(rating));
      }

      // Wait for shooter updates to finish
      if(futures.isNotEmpty) { 
        await Future.wait(futures);
      }

      // Calculate new baseline
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
      // _log.vv("New baseline for ${group.name} after ${match.name}: ${baseline.toStringAsFixed(1)}");
    }
    if(Timings.enabled) timings.add(TimingType.updateConnectedness, DateTime.now().difference(start).inMicroseconds);

    return changeCount;
  }

  (List<MatchEntry>, List<RelativeMatchScore>) _filterScores(List<MatchEntry> shooters, List<RelativeMatchScore> scores, MatchStage? stage) {
    List<MatchEntry> filteredShooters = []..addAll(shooters);
    List<RelativeMatchScore> filteredScores = []..addAll(scores);
    for(var s in scores) {
      if(stage != null) {
        var stageScore = s.stageScores[stage];

        if(stageScore == null) {
          filteredScores.remove(s);
          filteredShooters.remove(s.shooter);
          // _log.w("null stage score for ${s.shooter}");
          continue;
        }

        if(!_isValid(stageScore)) {
          filteredScores.remove(s);
          filteredShooters.remove(s.shooter);
        }
      }
      else {
        if(_dnf(s)) {
          filteredScores.remove(s);
          filteredShooters.remove(s.shooter);
        }
      }
    }

    return (filteredShooters, filteredScores);
  }

  bool _isValid(RelativeStageScore score) {
    // Filter out badly marked classifier reshoots
    if(score.score.targetEventCount == 0 && score.score.rawTime <= 0.1) return false;

    // The George Williams Rule: filter out suspiciously high hit factors
    if(sport.defaultStageScoring is HitFactorScoring) {
      if(score.score.hitFactor > 30) return false;
    }

    // Filter out extremely short times that are probably DNFs or partial scores entered for DQs
    if(score.score.rawTime <= 0.5) return false;

    // The Jalise Williams rule: filter out subminor/unknown PFs
    if(score.shooter.powerFactor.doesNotScore) return false;

    return true;
  }

  bool _dnf(RelativeMatchScore score) {
    if(score.shooter.powerFactor.doesNotScore) {
      return true;
    }

    for(var stageScore in score.stageScores.values) {
      if(!(stageScore.stage.scoring is IgnoredScoring) && stageScore.score.rawTime <= 0.01 && stageScore.score.targetEventCount == 0) {
        return true;
      }
    }

    return false;
  }

  Future<void> _processWholeEvent({
    required RatingGroup group,
    required ShootingMatch match,
    MatchStage? stage,
    required Map<String, ShooterRating> wrappedRatings,
    required List<RelativeMatchScore> scores,
    required Map<DbShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod
  }) async {
    // A cache of wrapped shooter ratings, so we don't have to hit the DB every time.
    Map<String, ShooterRating> wrappedRatings = {};

    if(stage != null) {
      var scoreMap = <ShooterRating, RelativeScore>{};
      var matchScoreMap = <ShooterRating, RelativeMatchScore>{};
      for(var s in scores) {
        String num = s.shooter.memberNumber;

        var otherScore = s.stageScores[stage]!;
        _encounteredMemberNumber(num);

        ShooterRating rating = wrappedRatings[num] ?? ratingSystem.wrapDbRating(
            (await db.maybeKnownShooter(project: project, group: group, memberNumber: num, useCache: true))!
        );

        scoreMap[rating] = otherScore;
        matchScoreMap[rating] = s;
        changes[rating.wrappedRating] ??= {};
        wrappedRatings[num] = rating;
      }

      // Check for pubstomp
      var pubstompMod = 1.0;
      if (_pubstomp(wrappedRatings, scores)) {
        pubstompMod = 0.33;
      }
      matchStrength *= pubstompMod;

      var update = ratingSystem.updateShooterRatings(
        match: match,
        shooters: scoreMap.keys.toList(),
        scores: scoreMap,
        matchScores: matchScoreMap,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
        eventWeightMultiplier: weightMod,
      );

      for(var rating in scoreMap.keys) {
        var stageScore = scoreMap[rating];
        var matchScore = matchScoreMap[rating];

        if(stageScore == null) {
          // _log.w("Null stage score for $rating on ${stage.name}");
          continue;
        }

        if(matchScore == null) {
          _log.w("Null match score for $rating on ${stage.name}");
          continue;
        }

        if (!changes[rating]!.containsKey(stageScore)) {
          changes[rating]![stageScore] = ratingSystem.newEvent(rating: rating, match: match, stage: stage, score: stageScore, matchScore: matchScore);
          changes[rating]![stageScore]!.apply(update[rating]!);
        }
      }
    }
    else { // by match
      var scoreMap = <ShooterRating, RelativeScore>{};
      var matchScoreMap = <ShooterRating, RelativeMatchScore>{};
      for(var s in scores) {
        String num = s.shooter.memberNumber;
        _encounteredMemberNumber(num);

        ShooterRating rating = wrappedRatings[num] ?? ratingSystem.wrapDbRating(
            (await db.maybeKnownShooter(project: project, group: group, memberNumber: num, useCache: true))!
        );

        scoreMap[rating] = s;
        matchScoreMap[rating] = s;
        changes[rating.wrappedRating] ??= {};
        wrappedRatings[num] = rating;
      }

      // Check for pubstomp
      var pubstompMod = 1.0;
      if(_pubstomp(wrappedRatings, scores)) {
        pubstompMod = 0.33;
      }
      matchStrength *= pubstompMod;

      var update = ratingSystem.updateShooterRatings(
        match: match,
        shooters: scoreMap.keys.toList(),
        scores: scoreMap,
        matchScores: matchScoreMap,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
      );

      for(var rating in scoreMap.keys) {
        var score = scoreMap[rating]!;
        // You only get one rating change per match.
        if (changes[rating]!.isEmpty) {
          changes[rating]![score] ??= ratingSystem.newEvent(
            rating: rating,
            match: match,
            score: score,
            matchScore: score as RelativeMatchScore,
            infoLines: update[rating]!.infoLines,
            infoData: update[rating]!.infoData,
          );

          changes[rating]![score]!.apply(update[rating]!);
        }
      }
    }
  }

  void _processRoundRobin({
    required ShootingMatch match,
    MatchStage? stage,
    required Map<String, ShooterRating> wrappedRatings,
    required List<MatchEntry> shooters,
    required List<RelativeMatchScore> scores,
    required int startIndex,
    required Map<DbShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod,
  }) {

    MatchEntry a = shooters[startIndex];
    var score = scores.firstWhere((element) => element.shooter == a);

    // Check for pubstomp
    var pubstompMod = 1.0;
    if(score.ratio >= 1.0) {
      if(_pubstomp(wrappedRatings, scores)) {
        pubstompMod = 0.33;
      }
    }
    matchStrength *= pubstompMod;

    for(int j = startIndex + 1; j < shooters.length; j++) {
      Shooter b = shooters[j];

      String memNumA = a.memberNumber;
      String memNumB = b.memberNumber;

      // unmarked reentries
      if(memNumA == memNumB) continue;

      ShooterRating aRating = wrappedRatings[memNumA]!;
      ShooterRating bRating = wrappedRatings[memNumB]!;

      changes[aRating.wrappedRating] ??= {};
      changes[bRating.wrappedRating] ??= {};

      RelativeMatchScore aScore = scores.firstWhere((score) => score.shooter == a);
      RelativeMatchScore bScore = scores.firstWhere((score) => score.shooter == b);

      if(stage != null) {
        RelativeScore aStageScore = aScore.stageScores[stage]!;
        RelativeScore bStageScore = bScore.stageScores[stage]!;

        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          match: match,
          isMatchOngoing: project.matchInProgressPointers.contains(match),
          shooters: [aRating, bRating],
          scores: {
            aRating: aStageScore,
            bRating: bStageScore,
          },
          matchScores: {
            aRating: aScore,
            bRating: bScore,
          },
          matchStrengthMultiplier: matchStrength,
          connectednessMultiplier: connectednessMod,
          eventWeightMultiplier: weightMod,
        );

        changes[aRating]![aStageScore] ??=
            ratingSystem.newEvent(rating: aRating, match: match, stage: stage, score: aStageScore, matchScore: aScore);
        changes[bRating]![bStageScore] ??=
            ratingSystem.newEvent(rating: bRating, match: match, stage: stage, score: bStageScore, matchScore: bScore);

        changes[aRating]![aStageScore]!.apply(update[aRating]!);
        changes[bRating]![bStageScore]!.apply(update[bRating]!);
      }
      else {
        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          match: match,
          isMatchOngoing: project.matchInProgressPointers.contains(match),
          shooters: [aRating, bRating],
          scores: {
            aRating: aScore,
            bRating: bScore,
          },
          matchScores: {
            aRating: aScore,
            bRating: bScore,
          },
          matchStrengthMultiplier: matchStrength,
          connectednessMultiplier: connectednessMod,
          eventWeightMultiplier: weightMod,
        );

        changes[aRating]![aScore] ??= ratingSystem.newEvent(rating: aRating, match: match, score: aScore, matchScore: aScore);
        changes[bRating]![bScore] ??= ratingSystem.newEvent(rating: bRating, match: match, score: bScore, matchScore: aScore);

        changes[aRating]![aScore.total]!.apply(update[aRating]!);
        changes[bRating]![bScore.total]!.apply(update[bRating]!);
      }
    }
  }

  void _processOneshot({
    required ShootingMatch match,
    MatchStage? stage,
    required MatchEntry shooter,
    required List<RelativeMatchScore> scores,
    required Map<String, ShooterRating> wrappedRatings,
    required Map<DbShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required Map<ShooterRating, RelativeScore> stageScores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod
  }) {
    String memNum = shooter.memberNumber;

    ShooterRating rating = wrappedRatings[memNum]!;

    changes[rating.wrappedRating] ??= {};
    RelativeMatchScore score = scores.firstWhere((score) => score.shooter == shooter);

    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    // Check for pubstomp
    var pubstompMod = 1.0;
    if(score.ratio >= 1.0) {
      if(_pubstomp(wrappedRatings, scores)) {
        pubstompMod = 0.33;
      }
    }
    matchStrength *= pubstompMod;
    if(Timings.enabled) timings.add(TimingType.pubstomp, DateTime.now().difference(start).inMicroseconds);

    if(stage != null) {
      RelativeStageScore stageScore = score.stageScores[stage]!;

      // If the shooter has already had a rating change for this stage, don't recalc.
      for(var existingScore in changes[rating.wrappedRating]!.keys) {
        existingScore as RelativeStageScore;
        if(existingScore.stage == stage) return;
      }

      _encounteredMemberNumber(memNum);

      if(Timings.enabled) start = DateTime.now();
      var update = ratingSystem.updateShooterRatings(
        match: match,
        shooters: [rating],
        scores: stageScores,
        matchScores: matchScores,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
        eventWeightMultiplier: weightMod,
      );
      if(Timings.enabled) timings.add(TimingType.update, DateTime.now().difference(start).inMicroseconds);

      if(Timings.enabled) start = DateTime.now();
      if(!changes[rating.wrappedRating]!.containsKey(stageScore)) {
        changes[rating.wrappedRating]![stageScore] =
            ratingSystem.newEvent(rating: rating, match: match, stage: stage, score: stageScore, matchScore: score);
        changes[rating.wrappedRating]![stageScore]!.apply(update[rating]!);
      }
      if(Timings.enabled) timings.add(TimingType.changeMap, DateTime.now().difference(start).inMicroseconds);
    }
    else {
      _encounteredMemberNumber(memNum);

      var update = ratingSystem.updateShooterRatings(
        match: match,
        shooters: [rating],
        scores: matchScores,
        matchScores: matchScores,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
      );

      // You only get one rating change per match.
      if(changes[rating]!.isEmpty) {
        changes[rating]![score] = ratingSystem.newEvent(
          rating: rating,
          match: match,
          score: score,
          matchScore: score,
          infoLines: update[rating]!.infoLines,
          infoData: update[rating]!.infoData,
        );

        changes[rating]![score]!.apply(update[rating]!);
      }
    }
  }

  bool _pubstomp(Map<String, ShooterRating> wrappedRatings, List<RelativeMatchScore> scores) {
    if(scores.length < 2) return false;

    var sorted = scores.sorted((a, b) => b.ratio.compareTo(a.ratio));

    var first = sorted[0];
    var second = sorted[1];

    var firstClass = first.shooter.classification;
    var secondClass = second.shooter.classification;

    var firstRating = wrappedRatings[first.shooter.memberNumber];
    var secondRating = wrappedRatings[second.shooter.memberNumber];

    // People entered with empty or invalid member numbers
    if(firstRating == null || secondRating == null) {
      _log.w("Unexpected null in pubstomp detection");
      return false;
    }

    return sport.pubstompProvider?.isPubstomp(
      firstScore: first,
      secondScore: second,
      firstRating: firstRating,
      secondRating: secondRating,
      firstClass: firstClass,
      secondClass: secondClass,
    ) ?? false;
  }

  void _encounteredMemberNumber(String num) {
    // TODO: decide how to track this, or if we need to given DB stuff

    // _memberNumbersEncountered.add(num);
    // var mappedNum = _memberNumberMappings[num];
    // if(mappedNum != null && mappedNum != num) {
    //   _memberNumbersEncountered.add(num);
    // }
  }

  List<String> _alternateForms(String num) {
    if(sport.shooterDeduplicator != null) {
      return sport.shooterDeduplicator!.alternateForms(num);
    }
    return [num];
  }
}

enum LoadingState {
  /// Processing has not yet begun
  notStarted,
  /// New matches are downloading from remote sources
  downloadingMatches,
  /// Matches are being read from the database
  readingMatches,
  /// Competitors are being added to the database
  addingCompetitors,
  /// Competitors are being deduplicated
  deduplicatingCompetitors,
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
      case LoadingState.addingCompetitors:
        return "adding competitors";
      case LoadingState.deduplicatingCompetitors:
        return "deduplicating competitors";
      case LoadingState.processingScores:
        return "processing scores";
      case LoadingState.done:
        return "finished";
    }
  }
}

extension AsyncRetainWhere<T> on List<T> {
  Future<void> retainWhereAsync(Future<bool> Function(T) test) async {
    List<T> toRemove = [];
    for(var i in this) {
      if(!(await test(i))) {
        toRemove.add(i);
      }
    }
    this.removeWhere((element) => toRemove.contains(element));
  }
}