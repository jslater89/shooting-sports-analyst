/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
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
  RatingProjectSettings get settings => project.settings;
  RatingSystem get ratingSystem => settings.algorithm;
  Sport get sport => project.sport;

  Timings timings = Timings();

  MemberNumberCorrectionContainer get _dataCorrections => settings.memberNumberCorrections;
  List<String> get memberNumberWhitelist => settings.memberNumberWhitelist;

  RatingProjectLoader(this.project, this.callback);

  Future<Result<void, RatingProjectLoadError>> calculateRatings({bool fullRecalc = false}) async {
    HydratedMatchCache().clear();
    timings.reset();

    var start = DateTime.now();
    callback(progress: -1, total: -1, state: LoadingState.readingMatches);
    var matchesLink = await project.matchesToUse();

    // We want to add matches in ascending order, from oldest to newest.
    var matchesToAdd = await matchesLink.filter().sortByDate().findAll();

    // We're interested in the most recent match in addition to the full list,
    // so sort by descending date for convenience.
    var lastUsed = await project.lastUsedMatches.filter().sortByDateDesc().findAll();
    bool canAppend = false;

    // TODO: check consistency of project settings and reset if needed
    // Things to check:
    // * project sport vs match sports


    // If this project records a list of matches used to calculate ratings, we
    // may be able to append to it rather than running the full calculation.
    // If every match in [matchesToAdd] is after the most recent match in [lastUsed],
    // we can append.
    if(lastUsed.isNotEmpty) {
      // a match in matchesToAdd needs to be rated if no matches in lastUsed
      // share a source and any source IDs with it
      var missingMatches = matchesToAdd.where((m) =>
        lastUsed.none((l) =>
          l.sourceCode == m.sourceCode &&
          l.sourceIds.any((id) => m.sourceIds.contains(id))
        )
      ).toList();
      var mostRecentMatch = lastUsed.first;
      _log.i("Checking for append: cutoff date is ${mostRecentMatch.date}");
      canAppend = !fullRecalc && missingMatches.every((m) => m.date.isAfter(mostRecentMatch.date));
      if(canAppend) {
        matchesToAdd = missingMatches;
      }
    }
    else {
      _log.i("No last used matches (first time calculation)");
    }

    // nothing to do
    if(matchesToAdd.isEmpty) {
      _log.i("No new matches");
      callback(progress: 0, total: 0, state: LoadingState.done);
      return Result.ok(null);
    }

    if(!canAppend) {
      if(fullRecalc) {
        _log.i("Unable to append: full recalculation requested");
      }
      else {
        _log.i("Unable to append: resetting ratings");
      }
      await project.resetRatings();
    }
    else {
      _log.i("Appending ${matchesToAdd.length} matches to ratings");
    }

    // If we're appending, this will be only the new matches.
    // If we're not appending, this will be all the matches, and
    // clearing the old list happens in the resetRatings call above.
    project.lastUsedMatches.addAll(matchesToAdd);
    await AnalystDatabase().isar.writeTxn(() async {
      await project.lastUsedMatches.save();
    });

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
        callback(progress: hydratedMatches.length, total: matchesToAdd.length, state: LoadingState.readingMatches);
      }
    }

    if(Timings.enabled) timings.add(TimingType.retrieveMatches, DateTime.now().difference(start).inMicroseconds);

    callback(progress: 0, total: matchesToAdd.length, state: LoadingState.processingScores);
    var result = await _addMatches(hydratedMatches);
    if(result.isErr()) return Result.errFrom(result);

    callback(progress: 1, total: 1, state: LoadingState.done);
    return Result.ok(null);
  }

  Future<Result<void, RatingProjectLoadError>> _addMatch(ShootingMatch match) {
    return _addMatches([match]);
  }


  int _totalMatchSteps = 0;
  int _currentMatchStep = 0;
  Future<Result<void, RatingProjectLoadError>> _addMatchesToGroup(RatingGroup group, List<ShootingMatch> matches) async {
    for (var match in matches) {
      // 1. For each match, add shooters.
      await _addShootersFromMatch(group, match);
    }

    // 2. Deduplicate shooters.

    // At this point we have an accurate count of shooters so far, which we'll need for various maths.
    var shooterCount = await AnalystDatabase().countShooterRatings(project, group);

    var start = DateTime.now();
    for (var match in matches) {
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
      await _rankMatch(group, match);
      _currentMatchStep += 1;
      callback(progress: _currentMatchStep, total: _totalMatchSteps, state: LoadingState.processingScores, eventName: match.name, groupName: group.name);
    }

    var count = await db.countShooterRatings(project, group);
    if(Timings.enabled) timings.add(TimingType.rateMatches, DateTime.now().difference(start).inMicroseconds);
    _log.i("Initial ratings complete for $count shooters in ${matches.length} matches in ${group.filters.activeDivisions}");

    // 3.2. DB-delete any shooters we added who recorded no scores in any matches in
    // this group.

    return Result.ok(null);
  }

  Future<Result<void, RatingProjectLoadError>> _addMatches(List<ShootingMatch> matches) async {
    _totalMatchSteps = project.groups.length * matches.length;
    List<Future<Result<void, RatingProjectLoadError>>> futures = [];
    for(var group in project.groups) {
      // futures.add(_addMatchesToGroup(group, matches));
      await _addMatchesToGroup(group, matches);
    }
    // var results = await Future.wait(futures);
    // for(var result in results) {
    //   if(result.isErr()) return result;
    // }

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
  Future<int> _addShootersFromMatch(RatingGroup group, ShootingMatch match) async {
    // TODO: ensure we're using allPossibleMemberNumbers where appropriate.
    // we want to make sure that in any case where we query to ask whether a shooter exists,
    // we query against allPossibleMemberNumbers rather than knownMemberNumbers, so we don't
    // have to worry about deduplicating A/TY/FY forms in USPSA.

    var start = DateTime.now();
    int added = 0;
    int updated = 0;
    var shooters = await _getShooters(group, match);
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
          memberNumber: s.memberNumber,
          usePossibleMemberNumbers: true,
        );
        if(rating == null) {
          var newRating = ratingSystem.newShooterRating(s, sport: project.sport, date: match.date);
          await db.newShooterRatingFromWrapped(
            rating: newRating,
            group: group,
            project: project,
          );
          added += 1;
        }
        else {
          // Update names for existing shooters on add, to eliminate the Mel Rodero -> Mel Rodero II problem in the L2+ set
          rating.firstName = s.firstName;
          rating.lastName = s.lastName;
          updated += 1;
          
          // We asked for allPossibleMemberNumbers, so if this member number isn't
          // in the knownMemberNumbers list, add it.
          if(!rating.knownMemberNumbers.contains(s.memberNumber)) {
            rating.knownMemberNumbers.add(s.memberNumber);
          }

          // If this is an international member number and the member number doesn't
          // start with INTL, add it.
          if(s.memberNumber.startsWith("INTL")) {
            rating.knownMemberNumbers.add("INTL${s.memberNumber}");
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

    return added + updated;
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

    for(var shooter in shooters) {
      shooter.memberNumber = Rater.processMemberNumber(shooter.memberNumber);
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
        finalMemberNumber = Rater.processMemberNumber(emptyCorrection.correctedNumber);
      }

      _verifyCache[s] = false;
      return false;
    }

    // This is already processed, because _verifyShooter is only called from _getShooters
    // after member numbers have been processed.
    String memNum = finalMemberNumber;

    var rating = await db.maybeKnownShooter(project: project, group: g, memberNumber: finalMemberNumber);
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
  Future<void> _rankMatch(RatingGroup group, ShootingMatch match) async {
    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    var shooters = await _getShooters(group, match, verify: true);
    var scores = match.getScores(shooters: shooters, scoreDQ: settings.byStage);

    // Skip when a match has no shooters in a group
    if(shooters.length == 0 && scores.length == 0) {
      return;
    }

    if(Timings.enabled) timings.add(TimingType.getShootersAndScores, DateTime.now().difference(start).inMicroseconds);

    if(Timings.enabled) start = DateTime.now();
    // Based on strength of competition, vary rating gain between 25% and 150%.
    var matchStrength = 0.0;
    for(var shooter in shooters) {
      matchStrength += sport.ratingStrengthProvider?.strengthForClass(shooter.classification) ?? 1.0;

      // Update
      var rating = await AnalystDatabase().maybeKnownShooter(project: project, group: group, memberNumber: shooter.memberNumber);
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
    double strengthMod =  (1.0 + max(-0.75, min(0.5, ((matchStrength) - _centerStrength) * 0.2))) * (levelStrengthBonus);
    if(Timings.enabled) timings.add(TimingType.calcMatchStrength, DateTime.now().difference(start).inMicroseconds);

    if(Timings.enabled) start = DateTime.now();
    // Based on connectedness, vary rating gain between 80% and 120%
    var totalConnectedness = 0.0;
    var totalShooters = 0.0;
    var connectedness = await AnalystDatabase().getConnectedness(project, group);

    totalConnectedness = connectedness.sum;
    totalShooters = connectedness.length.toDouble();

    var globalAverageConnectedness = totalShooters < 1 ? 105.0 : totalConnectedness / totalShooters;
    var globalMedianConnectedness = totalShooters < 1 ? 105.0 : connectedness[connectedness.length ~/ 2];
    var connectednessDenominator = max(105.0, globalMedianConnectedness);

    totalConnectedness = 0.0;
    totalShooters = 0;
    Map<String, DbShooterRating> ratingsAtMatch = {};
    Map<String, ShooterRating> wrappedRatings = {};
    for(var shooter in shooters) {
      var rating = await AnalystDatabase().maybeKnownShooter(
        project: project,
        group: group,
        memberNumber: shooter.memberNumber,
      );

      if(rating != null) {
        totalConnectedness += rating.connectedness;
        totalShooters += 1;
        ratingsAtMatch[shooter.memberNumber] = rating;
        wrappedRatings[shooter.memberNumber] = ratingSystem.wrapDbRating(rating);
      }
    }
    var localAverageConnectedness = totalConnectedness / (totalShooters > 0 ? totalShooters : 1.0);
    var connectednessMod = /*1.0;*/ 1.0 + max(-0.2, min(0.2, (((localAverageConnectedness / connectednessDenominator) - 1.0) * 2))); // * 1: how much to adjust the percentages by
    if(Timings.enabled) timings.add(TimingType.calcConnectedness, DateTime.now().difference(start).inMicroseconds);

    // _log.d("Connectedness for ${match.name}: ${localAverageConnectedness.toStringAsFixed(2)}/${connectednessDenominator.toStringAsFixed(2)} => ${connectednessMod.toStringAsFixed(3)}");

    Map<DbShooterRating, Map<RelativeScore, RatingEvent>> changes = {};
    Set<DbShooterRating> shootersAtMatch = Set();

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

    if(Timings.enabled) start = DateTime.now();
    if(shooters.length > 1) {
      var averageBefore = 0.0;
      var averageAfter = 0.0;

      // We need only consider at most the best [ShooterRating.maxConnections] connections. If a shooter's list is
      // empty, we'll fill their list with these shooters. If a shooter's list is not empty, we can end up with at
      // most maxConnections new entries in the list, by definition.
      var encounteredList = shootersAtMatch
          .sorted((a, b) => b.connectedness.compareTo(a.connectedness))
          .sublist(0, min(ShooterRating.maxConnections, shootersAtMatch.length));

      // _log.d("Updating connectedness at ${match.name} for ${shootersAtMatch.length} of ${knownShooters.length} shooters");
      for (var rating in shootersAtMatch) {
        averageBefore += rating.connectedness;
        // TODO: restore
        // rating.updateConnections(match.date, encounteredList);
        rating.lastSeen = match.date;
      }

      for (var rating in shootersAtMatch) {
        // TODO: restore
        // rating.updateConnectedness();
        averageAfter += rating.connectedness;
      }

      averageBefore /= encounteredList.length;
      averageAfter /= encounteredList.length;
      // _log.d("Averages: ${averageBefore.toStringAsFixed(1)} -> ${averageAfter.toStringAsFixed(1)} vs. ${expectedConnectedness.toStringAsFixed(1)}");
    }
    if(Timings.enabled) timings.add(TimingType.updateConnectedness, DateTime.now().difference(start).inMicroseconds);
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
          _log.w("null stage score for ${s.shooter}");
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
            (await db.maybeKnownShooter(project: project, group: group, memberNumber: num))!
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
          _log.w("Null stage score for $rating on ${stage.name}");
          continue;
        }

        if(matchScore == null) {
          _log.w("Null match score for $rating on ${stage.name}");
          continue;
        }

        if (!changes[rating]!.containsKey(stageScore)) {
          changes[rating]![stageScore] = ratingSystem.newEvent(rating: rating, match: match, stage: stage, score: stageScore, matchScore: matchScore);
          changes[rating]![stageScore]!.apply(update[rating]!);
          changes[rating]![stageScore]!.info = update[rating]!.info;
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
            (await db.maybeKnownShooter(project: project, group: group, memberNumber: num))!
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
            info: update[rating]!.info,
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
          isMatchOngoing: project.matchesInProgress.contains(match),
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
          isMatchOngoing: project.matchesInProgress.contains(match),
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
        changes[rating.wrappedRating]![stageScore]!.info = update[rating]!.info;
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
          info: update[rating]!.info,
        );

        changes[rating]![score.total]!.apply(update[rating]!);
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
}

/// A callback for RatingProjectLoader. When progress and total are both 0, show no progress.
/// When progress and total are both negative, show indeterminate progress. When total is positive,
/// show determinate progress with progress as the counter.
typedef RatingProjectLoaderCallback = void Function({required int progress, required int total, required LoadingState state, String? eventName, String? groupName});

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