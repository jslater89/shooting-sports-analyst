/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
// import 'package:shooting_sports_analyst/data/db/object/rating/rating_event.dart';
// import 'package:shooting_sports_analyst/data/db/object/rating/rating_project.dart';
// import 'package:shooting_sports_analyst/data/db/object/rating/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/data/ranking/shooter_aliases.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("Rater");

class Rater {
  Sport sport;

  List<ShootingMatch> _matches;
  List<ShootingMatch> _ongoingMatches;

  /// Maps processed member numbers to shooter ratings.
  ///
  /// Contains only canonical entries. Other member numbers for shooters are
  /// in _memberNumberMappings.
  Map<String, ShooterRating> knownShooters = {};

  /// Contains all mappings for normal-to-lifetime member number switches.
  ///
  /// All member numbers are processed.
  Map<String, String> _memberNumberMappings = {};

  /// Contains mappings that should not be made automatically.
  ///
  /// Keys in this map will not be mapped to values in this map.
  /// More precisely, if the target number for an N-number mapping
  /// is a value in this map, the key to that value will not be
  /// included in the N-number mapping.
  Map<String, String> _memberNumberMappingBlacklist = {};

  MemberNumberCorrectionContainer _dataCorrections;

  /// Contains member number mappings configured in the project settings.
  ///
  /// These will be used preferentially. Member numbers appearing as keys
  /// in this table will _not_ be automatically mapped.
  Map<String, String> _userMemberNumberMappings = {};

  /// Contains processed names (lowercase, no punctuation) used to assist
  /// the automatic member number mapper in doing its job.
  Map<String, String> _shooterAliases = {};

  /// Contains every member number encountered, who has shot at least one stage.
  Set<String> _memberNumbersEncountered = Set<String>();

  Map<String, String> get memberNumberMappings => {}..addAll(_memberNumberMappings);
  Set<String> get memberNumbersEncountered => <String>{}..addAll(_memberNumbersEncountered);

  RatingSystem ratingSystem;

  DbRatingGroup group;

  FilterSet get filters => group.filters;

  bool byStage;
  List<String> memberNumberWhitelist;
  Future<void> Function(int, int, String? eventName)? progressCallback;
  final int progressCallbackInterval;
  bool verbose;
  bool checkDataEntryErrors;

  Timings timings = Timings();

  Set<ShooterRating> get uniqueShooters => <ShooterRating>{}..addAll(knownShooters.values);

  Map<String, List<Division>> recognizedDivisions = {};

  Rater({
    required List<ShootingMatch> matches,
    required List<ShootingMatch> ongoingMatches,
    required this.ratingSystem,
    required this.group,
    required this.sport,
    this.byStage = false,
    this.progressCallback,
    this.progressCallbackInterval = RatingHistory.progressCallbackInterval,
    this.checkDataEntryErrors = true,
    Map<String, String>? shooterAliases,
    Map<String, String> userMemberNumberMappings = const {},
    Map<String, String> memberNumberMappingBlacklist = const {},
    required MemberNumberCorrectionContainer dataCorrections,
    this.verbose = true,
    this.recognizedDivisions = const {},
    this.memberNumberWhitelist = const []})
      : this._matches = matches,
        this._ongoingMatches = ongoingMatches,
        this._memberNumberMappingBlacklist = memberNumberMappingBlacklist,
        this._userMemberNumberMappings = userMemberNumberMappings,
        this._dataCorrections = dataCorrections
  {
    if(shooterAliases != null) this._shooterAliases = shooterAliases;
    else this._shooterAliases = defaultShooterAliases; 

    _matches.sort((a, b) {
      return a.date.compareTo(b.date);
    });
  }

  Rater.copy(Rater other) :
        this.sport = other.sport,
        this.knownShooters = {},
        this._matches = other._matches.map((m) => m.copy()).toList(),
        this._ongoingMatches = [], // updated in constructor body
        this.byStage = other.byStage,
        this._memberNumbersEncountered = Set()..addAll(other._memberNumbersEncountered),
        this._memberNumberMappings = {}..addAll(other._memberNumberMappings),
        this._memberNumberMappingBlacklist = {}..addAll(other._memberNumberMappingBlacklist),
        this._userMemberNumberMappings = {}..addAll(other._userMemberNumberMappings),
        this._dataCorrections = other._dataCorrections,
        this._shooterAliases = {}..addAll(other._shooterAliases),
        this.group = other.group,
        this.verbose = other.verbose,
        this.checkDataEntryErrors = other.checkDataEntryErrors,
        this.memberNumberWhitelist = other.memberNumberWhitelist,
        this.progressCallbackInterval = other.progressCallbackInterval,
        this.ratingSystem = other.ratingSystem {
    this._ongoingMatches = _matches.where((match) => other._ongoingMatches.any((otherMatch) => match.databaseId == otherMatch.databaseId)).toList();
    for(var entry in _memberNumberMappings.entries) {
      if (entry.key == entry.value) {
        // If, per the member number mappings, this is the canonical mapping, copy it immediately.
        // (The canonical mapping is the one where mappings[num] = num—i.e., no mapping)
        knownShooters[entry.value] = ratingSystem.copyShooterRating(other.knownShooter(entry.value));
      }
      // Otherwise, it's an non-canonical number, so we can skip it
    }
  }

  /// Add shooters from a set of matches without adding the matches, since we do the best job of shooter
  /// mapping when we operate with as much data as possible.
  ///
  /// Used by keep-history mode. (Or maybe not.)
  RatingResult addAndDeduplicateShooters(List<ShootingMatch> matches) {
    DateTime start = DateTime.now();
    if(Timings.enabled) start = DateTime.now();
    for(ShootingMatch m in matches) {
      _addShootersFromMatch(m, encounter: true);
    }
    if(Timings.enabled) timings.addShootersMillis = (DateTime.now().difference(start).inMicroseconds).toDouble();
    if(Timings.enabled) timings.shooterCount = knownShooters.length;

    if(Timings.enabled) start = DateTime.now();
    var result = _deduplicateShooters();
    if(Timings.enabled) timings.dedupShootersMillis = (DateTime.now().difference(start).inMicroseconds).toDouble();

    return result;
  }

  // Future<void> deserializeFrom(List<DbMemberNumberMapping> mappings, List<DbShooterRating> ratings, Map<DbShooterRating, List<DbRatingEvent>> eventsByRating) async {
  //   // Mappings contains only the interesting ones, i.e. number != mapping
  //   // The rest get added later.
  //
  //   // Track the reverse mappings for now, so that we can tell the rating
  //   // deserializer a mapped shooter's first number.
  //   // TODO: triple mappings will break this; needs to be a list!
  //   var reverseMappings = <String, String>{};
  //   for(var m in mappings) {
  //     _memberNumberMappings[m.number] = m.mapping;
  //     reverseMappings[m.mapping] = m.number;
  //   }
  //
  //   for(var r in ratings) {
  //     var numbers = [r.memberNumber];
  //
  //     // If we have a reverse mapping (i.e., new member number to old),
  //     // add that to the list
  //     if(reverseMappings.containsKey(r.memberNumber)) {
  //       numbers.add(reverseMappings[r.memberNumber]!);
  //     }
  //
  //     ShooterRating rating = await r.deserialize(eventsByRating[r]!, numbers);
  //     _memberNumbersEncountered.add(rating.memberNumber);
  //     _memberNumbersEncountered.add(processMemberNumber(rating.originalMemberNumber));
  //     knownShooters[rating.memberNumber] = rating;
  //   }
  // }

  Future<RatingResult> calculateInitialRatings() async {
    late DateTime start;

    if(Timings.enabled) start = DateTime.now();
    for(ShootingMatch m in _matches) {
      _addShootersFromMatch(m);
    }
    if(Timings.enabled) timings.addShootersMillis = (DateTime.now().difference(start).inMicroseconds).toDouble();
    if(Timings.enabled) timings.shooterCount = knownShooters.length;

    if(Timings.enabled) start = DateTime.now();

    var dedupResult = _deduplicateShooters();
    if(dedupResult.isErr()) return dedupResult;

    if(Timings.enabled) timings.dedupShootersMillis = (DateTime.now().difference(start).inMicroseconds).toDouble();

    int totalSteps = _matches.length;
    int currentSteps = 0;

    for(ShootingMatch m in _matches) {
      var onlyDivisions = recognizedDivisions[m.sourceIds.first];
      if(onlyDivisions != null) {
        var divisionsOfInterest = filters.divisions.entries.where((e) => e.value).map((e) => e.key).toList();

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

      if(Timings.enabled) start = DateTime.now();
      _rankMatch(m);
      if(Timings.enabled) timings.rateMatchesMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();
      if(Timings.enabled) timings.matchCount += 1;

      currentSteps += 1;
      if(currentSteps % progressCallbackInterval == 0) await progressCallback?.call(currentSteps, totalSteps, m.name);
    }

    if(Timings.enabled) start = DateTime.now();
    _removeUnseenShooters();
    if(Timings.enabled) timings.removeUnseenShootersMillis += (DateTime.now().difference(start).inMicroseconds);

    List<int> matchLengths = [];
    List<int> matchRoundCounts = [];
    List<int> stageRoundCounts = [];
    List<double> dqsPer100 = [];

    for(var m in _matches) {
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

    _log.i("Initial ratings complete for ${knownShooters.length} shooters in ${_matches.length} matches in ${filters.activeDivisions.toList()}");
    _log.i("Match length in stages (min/max/average/median/mode): ${matchLengths.min}/${matchLengths.max}/${matchLengths.average.toStringAsFixed(1)}/${matchLengths[matchLengths.length ~/ 2]}/$matchLengthMode");
    _log.i("Match length in rounds (average/median/mode): ${matchRoundCounts.min}/${matchRoundCounts.max}/${matchRoundCounts.average.toStringAsFixed(1)}/${matchRoundCounts[matchRoundCounts.length ~/ 2]}/$matchRoundsMode");
    _log.i("Stage length in rounds (average/median/mode): ${stageRoundCounts.min}/${stageRoundCounts.max}/${stageRoundCounts.average.toStringAsFixed(1)}/${stageRoundCounts[stageRoundCounts.length ~/ 2]}/$stageRoundsMode");
    _log.i("DQs per 100 shooters (average/median): ${dqsPer100.min.toStringAsFixed(3)}/${dqsPer100.max.toStringAsFixed(3)}/${dqsPer100.average.toStringAsFixed(3)}/${dqsPer100[dqsPer100.length ~/ 2].toStringAsFixed(3)}");
    // _log.i("Stage round counts: $stageRoundCounts");
    return RatingResult.ok();
  }

  RatingResult addMatch(ShootingMatch match) {
    _cachedStats = null;
    _matches.add(match);

    int changed = _addShootersFromMatch(match);
    var result = _deduplicateShooters();
    if(result.isErr()) return result;

    _rankMatch(match);

    _removeUnseenShooters();

    _log.i("Ratings update complete for $changed shooters (${knownShooters.length} total) in ${_matches.length} matches in ${filters.activeDivisions.toList()}");
    return RatingResult.ok();
  }

  /// Returns the number of shooters added or updated.
  ///
  /// Use [encounter] if you want shooters to be added regardless of whether they appear
  /// in scores. (i.e., shooters who DQ on the first stage, or are no-shows but still included in the data)
  int _addShootersFromMatch(ShootingMatch match, {bool encounter = false}) {
    int added = 0;
    int updated = 0;
    var shooters = _getShooters(match);
    for(MatchEntry s in shooters) {
      var processed = processMemberNumber(s.memberNumber);
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
        var rating = maybeKnownShooter(s.memberNumber);
        if(rating == null) {
          knownShooters[s.memberNumber] = ratingSystem.newShooterRating(s, sport: sport, date: match.date);
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

  ShooterRating? maybeKnownShooter(String processedMemberNumber) {
    var shooter = knownShooters[processedMemberNumber];
    if(shooter == null) {
      var number = _memberNumberMappings[processedMemberNumber];
      if(number != processedMemberNumber) shooter = knownShooters[number];
    }

    return shooter;
  }

  ShooterRating knownShooter(String processedMemberNumber) {
    return maybeKnownShooter(processedMemberNumber)!;
  }

  ShooterRating? ratingFor(Shooter s) {
    var processed = processMemberNumber(s.memberNumber);
    return maybeKnownShooter(processed);
  }

  String _processName(Shooter shooter) {
    String name = "${shooter.firstName.toLowerCase().replaceAll(RegExp(r"\s+"), "")}"
        + "${shooter.lastName.toLowerCase().replaceAll(RegExp(r"\s+"), "")}";
    name = name.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "");

    return name;
  }

  RatingResult _deduplicateShooters() {
    if(sport.shooterDeduplicator != null) {
      return sport.shooterDeduplicator!.deduplicateShooters(
        knownShooters: knownShooters,
        shooterAliases: _shooterAliases,
        currentMappings: _memberNumberMappings,
        userMappings: _userMemberNumberMappings,
        mappingBlacklist: _memberNumberMappingBlacklist,
      );
    }
    else {
      return RatingResult.ok();
    }
  }

  void _removeUnseenShooters() {
    List<String> shooterNumbers = knownShooters.keys.toList();
    for(String num in shooterNumbers) {
      if(!_memberNumbersEncountered.contains(num)) {
        knownShooters.remove(num);
        _memberNumberMappings.remove(num);
        _memberNumberMappings.removeWhere((key, value) => value == num);
      }
    }
  }

  List<MatchEntry> _getShooters(ShootingMatch match, {bool verify = false}) {
    var shooters = <MatchEntry>[];
    shooters = match.filterShooters(
      filterMode: filters.mode,
      divisions: filters.activeDivisions.toList(),
      powerFactors: [],
      classes: [],
      allowReentries: false,
    );

    for(var shooter in shooters) {
      shooter.memberNumber = processMemberNumber(shooter.memberNumber);
    }

    if(verify) {
      shooters.retainWhere((element) => _verifyShooter(element));
    }

    return shooters;
  }

  void _rankMatch(ShootingMatch match) {
    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    var shooters = _getShooters(match, verify: true);
    var scores = match.getScores(shooters: shooters, scoreDQ: byStage);
    if(Timings.enabled) timings.getShootersAndScoresMillis += (DateTime.now().difference(start).inMicroseconds);

    if(Timings.enabled) start = DateTime.now();
    // Based on strength of competition, vary rating gain between 25% and 150%.
    var matchStrength = 0.0;
    for(var shooter in shooters) {
      matchStrength += _strengthForClass(shooter.classification);

      // Update
      var rating = maybeKnownShooter(shooter.memberNumber);
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
        // rating.shooter.memberNumber = shooter.memberNumber;
      }
    }
    matchStrength = matchStrength / shooters.length;
    double strengthMod =  (1.0 + max(-0.75, min(0.5, ((matchStrength) - _centerStrength) * 0.2))) * (match.level?.strengthBonus ?? 1.0);
    if(Timings.enabled) timings.matchStrengthMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

    if(Timings.enabled) start = DateTime.now();
    // Based on connectedness, vary rating gain between 80% and 120%
    var totalConnectedness = 0.0;
    var totalShooters = 0.0;
    var connectednesses = <double>[];

    for(var shooter in knownShooters.values) {
      var mod = ShooterRating.baseTrendWindow / (byStage ? 1 : 1 * ShooterRating.trendStagesPerMatch);
      if (shooter.ratingEvents.length > mod) {
        totalConnectedness += shooter.connectedness;
        connectednesses.add(shooter.connectedness);
        totalShooters += 1;
      }
    }
    var globalAverageConnectedness = totalShooters < 1 ? 105.0 : totalConnectedness / totalShooters;
    var globalMedianConnectedness = totalShooters < 1 ? 105.0 : connectednesses[connectednesses.length ~/ 2];
    var connectednessDenominator = max(105.0, globalMedianConnectedness);

    totalConnectedness = 0.0;
    totalShooters = 0;
    for(var shooter in shooters) {
      var rating = maybeKnownShooter(shooter.memberNumber);

      if(rating != null) {
        totalConnectedness += rating.connectedness;
        totalShooters += 1;
      }
    }
    var localAverageConnectedness = totalConnectedness / (totalShooters > 0 ? totalShooters : 1.0);
    var connectednessMod = /*1.0;*/ 1.0 + max(-0.2, min(0.2, (((localAverageConnectedness / connectednessDenominator) - 1.0) * 2))); // * 1: how much to adjust the percentages by
    if(Timings.enabled) timings.connectednessModMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

    // _log.d("Connectedness for ${match.name}: ${localAverageConnectedness.toStringAsFixed(2)}/${connectednessDenominator.toStringAsFixed(2)} => ${connectednessMod.toStringAsFixed(3)}");

    Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes = {};
    Set<ShooterRating> shootersAtMatch = Set();

    if(Timings.enabled) start = DateTime.now();
    // Process ratings for each shooter.
    if(byStage) {
      for(MatchStage s in match.stages) {

        var (filteredShooters, filteredScores) = filterScores(shooters, scores.values.toList(), s);

        var weightMod = 1.0 + max(-0.20, min(0.10, (s.maxPoints - 120) /  400));

        Map<ShooterRating, RelativeScore> stageScoreMap = {};
        Map<ShooterRating, RelativeMatchScore> matchScoreMap = {};

        for(var score in filteredScores) {
          String num = score.shooter.memberNumber;
          var stageScore = score.stageScores[s]!;
          var rating = knownShooter(num);
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
      var (filteredShooters, filteredScores) = filterScores(shooters, scores.values.toList(), null);

      Map<ShooterRating, RelativeMatchScore> matchScoreMap = {};

      for(var score in filteredScores) {
        String num = score.shooter.memberNumber;
        matchScoreMap[knownShooter(num)] = score;
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
    if(match.date != null && shooters.length > 1) {
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
        rating.lastSeen = match.date!;
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

  (List<MatchEntry>, List<RelativeMatchScore>) filterScores(List<MatchEntry> shooters, List<RelativeMatchScore> scores, MatchStage? stage) {
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

  void _processRoundRobin({
    required ShootingMatch match,
    MatchStage? stage,
    required List<MatchEntry> shooters,
    required List<RelativeMatchScore> scores,
    required int startIndex,
    required Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod,
  }) {
    Shooter a = shooters[startIndex];
    var score = scores.firstWhere((element) => element.shooter == a);

    // Check for pubstomp
    var pubstompMod = 1.0;
    if(score.ratio >= 1.0) {
      if(_pubstomp(scores)) {
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

      ShooterRating aRating = knownShooter(memNumA);
      ShooterRating bRating = knownShooter(memNumB);

      changes[aRating] ??= {};
      changes[bRating] ??= {};

      RelativeMatchScore aScore = scores.firstWhere((score) => score.shooter == a);
      RelativeMatchScore bScore = scores.firstWhere((score) => score.shooter == b);

      if(stage != null) {
        RelativeScore aStageScore = aScore.stageScores[stage]!;
        RelativeScore bStageScore = bScore.stageScores[stage]!;

        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          match: match,
          isMatchOngoing: _ongoingMatches.contains(match),
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

        changes[aRating]![aStageScore] ??= ratingSystem.newEvent(rating: aRating, match: match, stage: stage, score: aStageScore, matchScore: aScore);
        changes[bRating]![bStageScore] ??= ratingSystem.newEvent(rating: bRating, match: match, stage: stage, score: bStageScore, matchScore: bScore);

        changes[aRating]![aStageScore]!.apply(update[aRating]!);
        changes[bRating]![bStageScore]!.apply(update[bRating]!);
      }
      else {
        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          match: match,
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
    required Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required Map<ShooterRating, RelativeScore> stageScores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod
  }) {
    String memNum = shooter.memberNumber;

    ShooterRating rating = knownShooter(memNum);

    changes[rating] ??= {};
    RelativeMatchScore score = scores.firstWhere((score) => score.shooter == shooter);

    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    // Check for pubstomp
    var pubstompMod = 1.0;
    if(score.ratio >= 1.0) {
      if(_pubstomp(scores)) {
        pubstompMod = 0.33;
      }
    }
    matchStrength *= pubstompMod;
    if(Timings.enabled) timings.pubstompMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

    if(stage != null) {
      RelativeStageScore stageScore = score.stageScores[stage]!;

      // If the shooter has already had a rating change for this stage, don't recalc.
      for(var existingScore in changes[rating]!.keys) {
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
      if(Timings.enabled) timings.updateMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

      if(!changes[rating]!.containsKey(stageScore)) {
        changes[rating]![stageScore] = ratingSystem.newEvent(rating: rating, match: match, stage: stage, score: stageScore, matchScore: score);
        changes[rating]![stageScore]!.apply(update[rating]!);
        changes[rating]![stageScore]!.info = update[rating]!.info;
      }
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

  void _processWholeEvent({
    required ShootingMatch match,
    MatchStage? stage,
    required List<RelativeMatchScore> scores,
    required Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod
  }) {
    // Check for pubstomp
    var pubstompMod = 1.0;
    if(_pubstomp(scores)) {
      pubstompMod = 0.33;
    }
    matchStrength *= pubstompMod;

    if(stage != null) {
      var scoreMap = <ShooterRating, RelativeScore>{};
      var matchScoreMap = <ShooterRating, RelativeMatchScore>{};
      for(var s in scores) {
        String num = s.shooter.memberNumber;

        var otherScore = s.stageScores[stage]!;
        _encounteredMemberNumber(num);
        scoreMap[knownShooter(num)] = otherScore;
        matchScoreMap[knownShooter(num)] = s;
        changes[knownShooter(num)] ??= {};
      }

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
    else {
      var scoreMap = <ShooterRating, RelativeScore>{};
      var matchScoreMap = <ShooterRating, RelativeMatchScore>{};
      for(var s in scores) {
        String num = s.shooter.memberNumber;

        scoreMap[knownShooter(num)] ??= s;
        matchScoreMap[knownShooter(num)] ??= s;
        changes[knownShooter(num)] ??= {};
        _encounteredMemberNumber(num);
      }

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

  bool _pubstomp(List<RelativeMatchScore> scores) {
    if(scores.length < 2) return false;

    var sorted = scores.sorted((a, b) => b.ratio.compareTo(a.ratio));

    var first = sorted[0];
    var second = sorted[1];

    var firstClass = first.shooter.classification;
    var secondClass = second.shooter.classification;

    var firstRating = maybeKnownShooter(first.shooter.memberNumber);
    var secondRating = maybeKnownShooter(second.shooter.memberNumber);

    // People entered with empty or invalid member numbers
    if(firstRating == null || secondRating == null) {
      // _log.d("Unexpected null in pubstomp detection");
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

  String toCSV({List<ShooterRating>? ratings}) {
    var sortedShooters = ratings ?? uniqueShooters.sorted((a, b) => b.rating.compareTo(a.rating));
    return ratingSystem.ratingsToCsv(sortedShooters);
  }

  void _encounteredMemberNumber(String num) {
    _memberNumbersEncountered.add(num);
    var mappedNum = _memberNumberMappings[num];
    if(mappedNum != null && mappedNum != num) {
      _memberNumbersEncountered.add(num);
    }
  }

  double get _centerStrength => sport.ratingStrengthProvider?.centerStrength ?? 1.0;

  double _strengthForClass(Classification? c) {
    return sport.ratingStrengthProvider?.strengthForClass(c) ?? 1.0;
  }

  RaterStatistics? _cachedStats;
  RaterStatistics getStatistics({List<ShooterRating>? ratings}) {
    if(ratings != null) return _calculateStats(ratings);

    if(_cachedStats == null) _cachedStats = _calculateStats(null);

    return _cachedStats!;
  }

  RaterStatistics _calculateStats(List<ShooterRating>? ratings) {
    if(ratings == null) {
      ratings = knownShooters.values.toList();
    }

    var bucketSize = ratingSystem.histogramBucketSize(ratings.length, _matches.length);

    var count = ratings.length;
    var allRatings = ratings.map((r) => r.rating);
    var allHistoryLengths = ratings.map((r) => r.ratingEvents.length);

    var histogram = <int, int>{};
    var yearOfEntryHistogram = <int, int>{};

    for(var rating in ratings) {
      // Buckets 100 wide
      var bucket = (0 + (rating.rating / bucketSize).floor());

      var value = histogram.increment(bucket);

      var events = <RatingEvent>[];
      if(rating.emptyRatingEvents.isNotEmpty) events.add(rating.emptyRatingEvents.first);
      if(rating.ratingEvents.isNotEmpty) events.add(rating.ratingEvents.first);

      if(events.isEmpty) continue;

      var firstEvent = events.sorted((a, b) => a.match.date!.compareTo(b.match.date!)).first;
      yearOfEntryHistogram.increment(firstEvent.match.date!.year);
    }

    var averagesByClass = <Classification, double>{};
    var minsByClass = <Classification, double>{};
    var maxesByClass = <Classification, double>{};
    var countsByClass = <Classification, int>{};
    Map<Classification, Map<int, int>> histogramsByClass = {};
    Map<Classification, List<double>> ratingsByClass = {};

    for(var classification in sport.classifications.values) {
      var shootersInClass = ratings.where((r) => r.lastClassification == classification);
      var ratingsInClass = shootersInClass.map((r) => r.rating);

      ratingsByClass[classification] = ratingsInClass.sorted((a, b) => a.compareTo(b));
      averagesByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.average : 0;
      minsByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.min : 0;
      maxesByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.max : 0;
      countsByClass[classification] = ratingsInClass.length;

      histogramsByClass[classification] = {};
      for(var rating in ratingsInClass) {
        // Buckets 100 wide
        var bucket = (0 + (rating / bucketSize).floor());

        histogramsByClass[classification]!.increment(bucket);
      }
    }

    return RaterStatistics(
      shooters: count,
      averageRating: allRatings.average,
      minRating: allRatings.min,
      maxRating: allRatings.max,
      averageHistory: allHistoryLengths.average,
      histogram: histogram,
      countByClass: countsByClass,
      averageByClass: averagesByClass,
      minByClass: minsByClass,
      maxByClass: maxesByClass,
      histogramsByClass: histogramsByClass,
      histogramBucketSize: bucketSize,
      ratingsByClass: ratingsByClass,
      yearOfEntryHistogram: yearOfEntryHistogram,
    );
  }

  @override
  String toString() {
    return "Rater for ${_matches.last.name} with ${filters.divisions}";
  }

  static Map<String, String> _processMemNumCache = {};
  static String processMemberNumber(String no) {
    if(_processMemNumCache.containsKey(no)) return _processMemNumCache[no]!;
    var no2 = no.toUpperCase().replaceAll(RegExp(r"[^FYTABLRD0-9]"), "").replaceAll(RegExp(r"[ATYF]{1,2}"), "");

    // If a member number contains no numbers, ignore it.
    if(!no2.contains(RegExp(r"[0-9]+"))) return "";

    // If a member number is all zeroes, ignore it.
    if(no2.contains(RegExp(r"^0+$"))) return "";

    _processMemNumCache[no] = no2;
    return no2;
  }
}

extension _StrengthBonus on MatchLevel {
  double get strengthBonus {
    switch(this.eventLevel) {
      case EventLevel.local:
        return 1.0;
      case EventLevel.regional:
        return 1.15;
      case EventLevel.area:
        return 1.3;
      case EventLevel.national:
        return 1.45;
      case EventLevel.international:
        return 1.6;
    }
  }
}

class RaterStatistics {
  int shooters;
  double averageRating;
  double minRating;
  double maxRating;
  double averageHistory;

  int histogramBucketSize;
  Map<int, int> histogram;

  Map<Classification, int> countByClass;
  Map<Classification, double> averageByClass;
  Map<Classification, double> minByClass;
  Map<Classification, double> maxByClass;

  Map<Classification, Map<int, int>> histogramsByClass;
  Map<Classification, List<double>> ratingsByClass;

  Map<int, int> yearOfEntryHistogram;

  RaterStatistics({
    required this.shooters,
    required this.averageRating,
    required this.minRating,
    required this.maxRating,
    required this.averageHistory,
    required this.countByClass,
    required this.averageByClass,
    required this.minByClass,
    required this.maxByClass,
    required this.histogramBucketSize,
    required this.histogram,
    required this.histogramsByClass,
    required this.ratingsByClass,
    required this.yearOfEntryHistogram,
  });
}