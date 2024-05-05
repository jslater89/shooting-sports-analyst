/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
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
    timings.reset();

    callback(progress: -1, total: -1, state: LoadingState.readingMatches);
    var matchesLink = await project.matchesToUse();

    // We want to add matches in ascending order, from oldest to newest.
    var matchesToAdd = await matchesLink.filter().sortByDate().findAll();

    // We're interested in the most recent match in addition to the full list,
    // so sort by descending date for convenience.
    var lastUsed = await project.lastUsedMatches.filter().sortByDateDesc().findAll();
    bool canAppend = false;

    if(lastUsed.isNotEmpty) {
      var missingMatches = matchesToAdd.where((e) => !lastUsed.contains(e)).toList();
      var mostRecentMatch = lastUsed.first;
      canAppend = !fullRecalc && missingMatches.every((m) => m.date.isAfter(mostRecentMatch.date));
      if(canAppend) matchesToAdd = missingMatches;
    }

    // nothing to do
    if(matchesToAdd.isEmpty) {
      return Result.ok(null);
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
      // TODO
      // The only way around having to load every shooter for deduplication is to
      // store some of what we currently calculate in deduplicateShooters ahead of
      // time, when we do _addShootersFromMatch. I think we mostly need a list of numbers
      // per recorded name, although maybe the other way around would be good to have too?

      // At this point we have an accurate count of shooters so far, which we'll need for various maths.
      var shooterCount = await AnalystDatabase().countShooterRatings(project, group);

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
        // TODO: copy _rankMatch.
        // Calculate global connectedness with the connectedness property query.
        // Calculate match connectedness by maybeKnownShooter lookups of everyone.
        // (Keep those around and pass them forward, maybe?)

        // 3.1.3. Update database with rating changes
      }

      // 3.2. DB-delete any shooters we added who recorded no scores in any matches in
      // this group.

      var count = await db.countShooterRatings(project, group);
      _log.i("Initial ratings complete for $count shooters in ${matches.length} in ${group.filters.divisions.keys}");
    }
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
  Future<int> _addShootersFromMatch(DbRatingGroup group, ShootingMatch match) async {
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
          db.upsertDbShooterRating(rating);
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
      shooters.retainWhereAsync((element) async => await _verifyShooter(group, element));
    }

    return shooters;
  }

  Map<Shooter, bool> _verifyCache = {};
  Future<bool> _verifyShooter(DbRatingGroup g, MatchEntry s) async {
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

    var rating = await db.maybeKnownShooter(project: project, group: g, processedMemberNumber: finalMemberNumber);
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
  Future<void> _rankMatch(DbRatingGroup group, ShootingMatch match) async {
    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    var shooters = _getShooters(group, match, verify: true);
    var scores = match.getScores(shooters: shooters, scoreDQ: settings.byStage);
    if(Timings.enabled) timings.getShootersAndScoresMillis += (DateTime.now().difference(start).inMicroseconds);

    if(Timings.enabled) start = DateTime.now();
    // Based on strength of competition, vary rating gain between 25% and 150%.
    var matchStrength = 0.0;
    for(var shooter in shooters) {
      matchStrength += sport.ratingStrengthProvider?.strengthForClass(shooter.classification) ?? 1.0;

      // Update
      var rating = await AnalystDatabase().maybeKnownShooter(project: project, group: group, processedMemberNumber: shooter.memberNumber);
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
    if(Timings.enabled) timings.matchStrengthMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

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
    for(var shooter in shooters) {
      var rating = await AnalystDatabase().maybeKnownShooter(
        project: project,
        group: group,
        processedMemberNumber: shooter.memberNumber,
      );

      if(rating != null) {
        totalConnectedness += rating.connectedness;
        totalShooters += 1;
        ratingsAtMatch[shooter.memberNumber] = rating;
      }
    }
    var localAverageConnectedness = totalConnectedness / (totalShooters > 0 ? totalShooters : 1.0);
    var connectednessMod = /*1.0;*/ 1.0 + max(-0.2, min(0.2, (((localAverageConnectedness / connectednessDenominator) - 1.0) * 2))); // * 1: how much to adjust the percentages by
    if(Timings.enabled) timings.connectednessModMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

    // _log.d("Connectedness for ${match.name}: ${localAverageConnectedness.toStringAsFixed(2)}/${connectednessDenominator.toStringAsFixed(2)} => ${connectednessMod.toStringAsFixed(3)}");

    Map<DbShooterRating, Map<RelativeScore, DbRatingEvent>> changes = {};
    Set<DbShooterRating> shootersAtMatch = Set();

    if(Timings.enabled) start = DateTime.now();
    // Process ratings for each shooter.
    if(settings.byStage) {
      for(MatchStage s in match.stages) {

        var (filteredShooters, filteredScores) = _filterScores(shooters, scores.values.toList(), s);

        var weightMod = 1.0 + max(-0.20, min(0.10, (s.maxPoints - 120) /  400));

        Map<DbShooterRating, RelativeScore> stageScoreMap = {};
        Map<DbShooterRating, RelativeMatchScore> matchScoreMap = {};

        for(var score in filteredScores) {
          String num = score.shooter.memberNumber;
          var stageScore = score.stageScores[s]!;
          var rating = ratingsAtMatch[num]!;
          stageScoreMap[rating] = stageScore;
          matchScoreMap[rating] = score;
        }

        if(ratingSystem.mode == RatingMode.wholeEvent) {
          _processWholeEvent(
              match: match,
              stage: s,
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

        for(var r in changes.keys) {
          r.updateFromEvents(changes[r]!.values.toList());
          r.updateTrends(changes[r]!.values.toList());
          shootersAtMatch.add(r);
        }
        changes.clear();
      }
    }
    else { // by match
      var (filteredShooters, filteredScores) = _filterScores(shooters, scores.values.toList(), null);

      Map<DbShooterRating, RelativeMatchScore> matchScoreMap = {};

      for(var score in filteredScores) {
        String num = score.shooter.memberNumber;
        matchScoreMap[ratingsAtMatch[num]!] = score;
      }

      if(ratingSystem.mode == RatingMode.wholeEvent) {
        _processWholeEvent(
            match: match,
            stage: null,
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
        r.updateFromEvents(changes[r]!.values.toList());
        r.updateTrends(changes[r]!.values.toList());
        shootersAtMatch.add(r);
      }
      changes.clear();
    }
    if(Timings.enabled) timings.rateShootersMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

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
        rating.updateConnections(match.date!, encounteredList);
        rating.lastSeen = match.date;
      }

      for (var rating in shootersAtMatch) {
        rating.updateConnectedness();
        averageAfter += rating.connectedness;
      }

      averageBefore /= encounteredList.length;
      averageAfter /= encounteredList.length;
      // _log.d("Averages: ${averageBefore.toStringAsFixed(1)} -> ${averageAfter.toStringAsFixed(1)} vs. ${expectedConnectedness.toStringAsFixed(1)}");
    }
    if(Timings.enabled) timings.updateConnectednessMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();
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

    // The George Williams Rule
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

extension AsyncRetainWhere<T> on List<T> {
  Future<void> retainWhereAsync(Future<bool> Function(T) test) async {
    List<T> toRemove = [];
    for(var i in this) {
      if(await test(i)) {
        toRemove.add(i);
      }
    }
    this.removeWhere((element) => toRemove.contains(element));
  }
}