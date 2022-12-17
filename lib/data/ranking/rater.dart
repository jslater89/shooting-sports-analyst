import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/shooter_aliases.dart';
import 'package:uspsa_result_viewer/data/ranking/timings.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/filter_dialog.dart';

class Rater {
  List<PracticalMatch> _matches;
  Map<String, ShooterRating> knownShooters = {};
  Map<String, String> _memberNumberMappings = {};
  Set<String> _memberNumbersEncountered = Set<String>();
  RatingSystem ratingSystem;

  FilterSet? _filters;

  /// Do not mutate this property.
  FilterSet? get filters => _filters;

  bool byStage;
  List<String> memberNumberWhitelist;
  Future<void> Function(int, int, String? eventName)? progressCallback;

  Timings timings = Timings();

  Set<ShooterRating> get uniqueShooters => <ShooterRating>{}..addAll(knownShooters.values);

  Rater({required List<PracticalMatch> matches, required this.ratingSystem, FilterSet? filters, this.byStage = false, this.progressCallback, this.memberNumberWhitelist = const []}) : this._matches = matches, this._filters = filters {
    _matches.sort((a, b) {
      if(a.date == null && b.date == null) {
        return 0;
      }
      if(a.date == null) return -1;
      if(b.date == null) return 1;

      return a.date!.compareTo(b.date!);
    });

    late DateTime start;

    if(Timings.enabled) start = DateTime.now();
    for(PracticalMatch m in _matches) {
      _addShootersFromMatch(m);
    }
    if(Timings.enabled) timings.addShootersMillis = (DateTime.now().difference(start).inMicroseconds).toDouble();
    if(Timings.enabled) timings.shooterCount = knownShooters.length;

    if(Timings.enabled) start = DateTime.now();
    _deduplicateShooters();
    if(Timings.enabled) timings.dedupShootersMillis = (DateTime.now().difference(start).inMicroseconds).toDouble();
  }

  Future<void> calculateInitialRatings() async {
    int totalSteps = _matches.length;
    int currentSteps = 0;
    late DateTime start;

    for(PracticalMatch m in _matches) {
      if(Timings.enabled) start = DateTime.now();
      _rankMatch(m);
      if(Timings.enabled) timings.rateMatchesMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();
      if(Timings.enabled) timings.matchCount += 1;

      currentSteps += 1;
      await progressCallback?.call(currentSteps, totalSteps, m.name);
    }

    if(Timings.enabled) start = DateTime.now();
    _removeUnseenShooters();
    if(Timings.enabled) timings.removeUnseenShootersMillis += (DateTime.now().difference(start).inMicroseconds);

    debugPrint("Initial ratings complete for ${knownShooters.length} shooters in ${_matches.length} matches in ${_filters != null ? _filters!.activeDivisions.toList() : "all divisions"}");
  }

  Rater.copy(Rater other) :
      this.knownShooters = {},
      this._matches = other._matches.map((m) => m.copy()).toList(),
      this.byStage = other.byStage,
      this._memberNumbersEncountered = Set()..addAll(other._memberNumbersEncountered),
      this._memberNumberMappings = {}..addAll(other._memberNumberMappings),
      this._filters = other._filters,
      this.memberNumberWhitelist = other.memberNumberWhitelist,
      this.ratingSystem = other.ratingSystem {
    List<String> secondPass = [];
    for(var entry in _memberNumberMappings.entries) {
      if(entry.key == entry.value) {
        // If, per the member number mappings, this is the canonical mapping, copy it immediately.
        // (The canonical mapping is the one where mappings[num] = num—i.e., no mapping)
        knownShooters[entry.value] = ratingSystem.copyShooterRating(other.knownShooters[entry.value]!);
      }
      else {
        if(other.knownShooters[entry.key] != null && other.knownShooters[entry.key] == other.knownShooters[entry.value]) {
          // If, in the source rater, the mapped and actual member numbers point to the same person, add to the
          // second-pass list to assign the mapping later.
          secondPass.add(entry.key);
        }
        else {
          debugPrint("This encountered mapped/actual member number? ${_memberNumbersEncountered.contains(entry.key)}/${_memberNumbersEncountered.contains(entry.value)}");
          debugPrint("Other encountered mapped/actual member number? ${other._memberNumbersEncountered.contains(entry.key)}/${other._memberNumbersEncountered.contains(entry.value)}");
          debugPrint("This mapped/actual, other mapped/actual: ${knownShooters[entry.key]} ${knownShooters[entry.value]} ${other.knownShooters[entry.key]} ${other.knownShooters[entry.value]}");
          debugPrint("Member number mapping ${entry.key} -> ${entry.value} appears invalid");

          _memberNumbersEncountered.remove(entry.key);
          _memberNumberMappings.remove(entry.key);
          _memberNumbersEncountered.remove(entry.value);

          if(other.knownShooters[entry.key] != null) {
            debugPrint("Copied shooter ${other.knownShooters[entry.key]!} for ${entry.key}");
            knownShooters[entry.key] = other.knownShooters[entry.key]!;
          }
          else {
            _memberNumbersEncountered.remove(entry.key);
          }

          if(other.knownShooters[entry.value] != null) {
            debugPrint("Copied shooter ${other.knownShooters[entry.value]!} for ${entry.value}");
            knownShooters[entry.value] = other.knownShooters[entry.value]!;
          }
          else {
            _memberNumbersEncountered.remove(entry.value);
          }
        }
      }
    }

    for(var mappedNumber in secondPass) {
      var actualNumber = _memberNumberMappings[mappedNumber]!;
      // debugPrint("Mapped $mappedNumber to $actualNumber with ${knownShooters[actualNumber]?.ratingEvents.length} ratings during copy");

      if(knownShooters[actualNumber] == null) {
        // break
      }

      knownShooters[mappedNumber] = knownShooters[actualNumber]!;
    }
  }
  
  void addMatch(PracticalMatch match) {
    _cachedStats = null;
    _matches.add(match);

    int changed = _addShootersFromMatch(match);
    _deduplicateShooters();

    _rankMatch(match);

    _removeUnseenShooters();

    debugPrint("Ratings update complete for $changed shooters (${knownShooters.length} total) in ${_matches.length} matches in ${_filters != null ? _filters!.activeDivisions.toList() : "all divisions"}");
  }

  /// Returns the number of shooters added or updated.
  int _addShootersFromMatch(PracticalMatch match) {
    int added = 0;
    int updated = 0;
    var shooters = _getShooters(match);
    for(Shooter s in shooters) {
      var processed = processMemberNumber(s.memberNumber);
      if(processed.isNotEmpty && !s.reentry) {
        s.memberNumber = processed;
        if(knownShooters[s.memberNumber] == null) {
          knownShooters[s.memberNumber] = ratingSystem.newShooterRating(s, date: match.date); // ratingSystem.defaultRating
          added += 1;
        }
        else {
          // Update names for existing shooters, to eliminate the Mel Rodero -> Mel Rodero II problem
          var rating = knownShooters[s.memberNumber]!;
          rating.firstName = s.firstName;
          rating.lastName = s.lastName;
          updated += 1;
        }
      }
    }

    return added + updated;
  }

  ShooterRating? ratingFor(Shooter s) {
    var processed = processMemberNumber(s.memberNumber);
    return knownShooters[processed];
  }

  void _deduplicateShooters() {
    Map<String, List<String>> namesToNumbers = {};

    for(var num in knownShooters.keys) {
      var shooter = knownShooters[num]!;
      var name = "${shooter.firstName.toLowerCase().replaceAll(RegExp(r"\s+"), "")}"
          + "${shooter.lastName.toLowerCase().replaceAll(RegExp(r"\s+"), "")}";

      var finalName = defaultShooterAliases[name] ?? name;

      namesToNumbers[finalName] ??= [];
      namesToNumbers[finalName]!.add(num);

      _memberNumberMappings[num] ??= num;
    }

    for(var name in namesToNumbers.keys) {
      var list = namesToNumbers[name]!;

      if(list.length == 2) {
        // If the shooter is already mapped, or if both numbers are 5-digit non-lifetime numbers, continue
        if((knownShooters[list[0]] == knownShooters[list[1]]) || (list[0].length > 4 && list[1].length > 4)) continue;

        debugPrint("Shooter $name has two member numbers, mapping: $list (${knownShooters[list[0]]}, ${knownShooters[list[1]]})");

        var rating0 = knownShooters[list[0]]!;
        var rating1 = knownShooters[list[1]]!;

        if (rating0.ratingEvents.length > 0 && rating1.ratingEvents.length > 0) {
          throw StateError("Both ratings have events");
        }

        if (rating0.ratingEvents.length == 0) {
          rating0.copyRatingFrom(rating1);
          knownShooters[list[1]] = rating0;
          _memberNumberMappings[list[1]] = list[0];

          // debugPrint("Mapped r1-r0 ${list[1]} to ${list[0]} with ${rating0.ratingEvents.length} ratings during deduplication");
        }
        else {
          rating1.copyRatingFrom(rating0);
          knownShooters[list[0]] = rating1;
          _memberNumberMappings[list[0]] = list[1];

          // debugPrint("Mapped r0-r1 ${list[0]} to ${list[1]} with ${rating1.ratingEvents.length} ratings during deduplication");
        }
      }
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

  List<Shooter> _getShooters(PracticalMatch match, {bool verify = false}) {
    var shooters = <Shooter>[];
    if(_filters != null) {
      shooters = match.filterShooters(
        filterMode: _filters!.mode,
        divisions: _filters!.activeDivisions.toList(),
        powerFactors: [],
        classes: [],
        allowReentries: false,
      );
    }
    else {
      shooters = match.filterShooters(allowReentries: false);
    }

    for(var shooter in shooters) {
      shooter.memberNumber = processMemberNumber(shooter.memberNumber);
    }

    if(verify) {
      shooters.retainWhere((element) => _verifyShooter(element));
    }

    return shooters;
  }

  void _rankMatch(PracticalMatch match) {
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

      var rating = knownShooters[shooter.memberNumber];
      if(rating != null) {
        rating.lastClassification = shooter.classification ?? rating.lastClassification;

        // Update the shooter's name: the most recent one is probably the most interesting/useful
        rating.firstName = shooter.firstName;
        rating.lastName = shooter.lastName;

        // Update the shooter's member number: the CSV exports are more useful if it's the most
        // recent one. // TODO: this would be handy, but it changes the math somehow (not removing unseen?)
        // rating.shooter.memberNumber = shooter.memberNumber;
      }
    }
    matchStrength = matchStrength / shooters.length;
    double strengthMod =  (1.0 + max(-0.75, min(0.5, ((matchStrength) - _strengthForClass(Classification.A)) * 0.2))) * (match.level?.strengthBonus ?? 1.0);
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
      var rating = knownShooters[shooter.memberNumber];

      if(rating != null) {
        totalConnectedness += rating.connectedness;
        totalShooters += 1;
      }
    }
    var localAverageConnectedness = totalConnectedness / (totalShooters > 0 ? totalShooters : 1.0);
    var connectednessMod = /*1.0;*/ 1.0 + max(-0.2, min(0.2, (((localAverageConnectedness / connectednessDenominator) - 1.0) * 2))); // * 1: how much to adjust the percentages by
    if(Timings.enabled) timings.connectednessModMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

    // debugPrint("Connectedness for ${match.name}: ${localAverageConnectedness.toStringAsFixed(2)}/${connectednessDenominator.toStringAsFixed(2)} => ${connectednessMod.toStringAsFixed(3)}");

    Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes = {};
    Set<ShooterRating> shootersAtMatch = Set();

    if(Timings.enabled) start = DateTime.now();
    // Process ratings for each shooter.
    if(byStage) {
      for(Stage s in match.stages) {

        var res = _filterScores(shooters, scores, s);
        var filteredShooters = res.a;
        var filteredScores = res.b;

        var weightMod = 1.0 + max(-0.20, min(0.10, (s.maxPoints - 120) /  400));

        Map<ShooterRating, RelativeScore> stageScoreMap = {};
        Map<ShooterRating, RelativeScore> matchScoreMap = {};

        for(var score in filteredScores) {
          String num = score.shooter.memberNumber;
          var otherScore = score.stageScores[s]!;
          stageScoreMap[knownShooters[num]!] = otherScore;
          matchScoreMap[knownShooters[num]!] = score.total;
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
      var res = _filterScores(shooters, scores, null);
      var filteredShooters = res.a;
      var filteredScores = res.b;

      Map<ShooterRating, RelativeScore> matchScoreMap = {};

      for(var score in filteredScores) {
        String num = score.shooter.memberNumber;
        matchScoreMap[knownShooters[num]!] = score.total;
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
      }
      changes.clear();
    }
    if(Timings.enabled) timings.rateShootersMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

    if(Timings.enabled) start = DateTime.now();
    if(match.date != null && shooters.length > 1) {
      var averageBefore = 0.0;
      var averageAfter = 0.0;

      var encounteredList = shootersAtMatch.toList();

      // debugPrint("Updating connectedness at ${match.name} for ${shootersAtMatch.length} of ${knownShooters.length} shooters");
      for (var rating in encounteredList) {
        averageBefore += rating.connectedness;
        rating.updateConnections(match.date!, encounteredList);
        rating.lastSeen = match.date!;
      }

      for (var rating in encounteredList) {
        rating.updateConnectedness();
        averageAfter += rating.connectedness;
      }

      averageBefore /= encounteredList.length;
      averageAfter /= encounteredList.length;
      // debugPrint("Averages: ${averageBefore.toStringAsFixed(1)} -> ${averageAfter.toStringAsFixed(1)} vs. ${expectedConnectedness.toStringAsFixed(1)}");
    }
    if(Timings.enabled) timings.updateConnectednessMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();
  }

  Map<Shooter, bool> _verifyCache = {};
  bool _verifyShooter(Shooter s) {
    if(_verifyCache.containsKey(s)) return _verifyCache[s]!;

    if(!byStage && s.dq) {
      _verifyCache[s] = false;
      return false;
    }
    if(s.reentry) {
      _verifyCache[s] = false;
      return false;
    }
    if(s.memberNumber.isEmpty) {
      _verifyCache[s] = false;
      return false;
    }

    // This is already processed, because _verifyShooter is only called from _getShooters
    // after member numbers have been processed.
    String memNum = s.memberNumber;

    if(knownShooters[memNum] == null) {
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

  _Tuple<List<Shooter>, List<RelativeMatchScore>> _filterScores(List<Shooter> shooters, List<RelativeMatchScore> scores, Stage? stage) {
    List<Shooter> filteredShooters = []..addAll(shooters);
    List<RelativeMatchScore> filteredScores = []..addAll(scores);
    for(var s in scores) {
      if(stage != null) {
        var stageScore = s.stageScores[stage];

        if(stageScore == null) {
          filteredScores.remove(s);
          filteredShooters.remove(s.shooter);
          print("WARN: null stage score");
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

    return _Tuple(filteredShooters, filteredScores);
  }

  void _processRoundRobin({
    required PracticalMatch match,
    Stage? stage,
    required List<Shooter> shooters,
    required List<RelativeMatchScore> scores,
    required int startIndex,
    required Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod,
  }) {
    Shooter a = shooters[startIndex];
    var score = scores.firstWhere((element) => element.shooter == a);

    if(scores.length < 2) return;

    // Check for pubstomp
    var pubstompMod = 1.0;
    if(score.total.percent >= 1.0) {
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

      ShooterRating aRating = knownShooters[memNumA]!;
      ShooterRating bRating = knownShooters[memNumB]!;

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
          shooters: [aRating, bRating],
          scores: {
            aRating: aStageScore,
            bRating: bStageScore,
          },
          matchScores: {
            aRating: aScore.total,
            bRating: bScore.total,
          },
          matchStrengthMultiplier: matchStrength,
          connectednessMultiplier: connectednessMod,
          eventWeightMultiplier: weightMod,
        );

        changes[aRating]![aStageScore] ??= ratingSystem.newEvent(rating: aRating, match: match, stage: stage, score: aStageScore);
        changes[bRating]![bStageScore] ??= ratingSystem.newEvent(rating: bRating, match: match, stage: stage, score: bStageScore);

        changes[aRating]![aStageScore]!.apply(update[aRating]!);
        changes[bRating]![bStageScore]!.apply(update[bRating]!);
      }
      else {
        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          shooters: [aRating, bRating],
          scores: {
            aRating: aScore.total,
            bRating: bScore.total,
          },
          matchScores: {
            aRating: aScore.total,
            bRating: bScore.total,
          },
          matchStrengthMultiplier: matchStrength,
          connectednessMultiplier: connectednessMod,
        );

        changes[aRating]![aScore.total] ??= ratingSystem.newEvent(rating: aRating, match: match, score: aScore.total);
        changes[bRating]![bScore.total] ??= ratingSystem.newEvent(rating: bRating, match: match, score: bScore.total);

        changes[aRating]![aScore.total]!.apply(update[aRating]!);
        changes[bRating]![bScore.total]!.apply(update[bRating]!);
      }
    }
  }

  void _processOneshot({
    required PracticalMatch match,
    Stage? stage,
    required Shooter shooter,
    required List<RelativeMatchScore> scores,
    required Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required Map<ShooterRating, RelativeScore> stageScores,
    required Map<ShooterRating, RelativeScore> matchScores,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod
  }) {
    if(scores.length < 2) return;

    String memNum = shooter.memberNumber;

    ShooterRating rating = knownShooters[memNum]!;

    changes[rating] ??= {};
    RelativeMatchScore score = scores.firstWhere((score) => score.shooter == shooter);

    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    // Check for pubstomp
    var pubstompMod = 1.0;
    if(score.total.percent >= 1.0) {
      if(_pubstomp(scores)) {
        pubstompMod = 0.33;
      }
    }
    matchStrength *= pubstompMod;
    if(Timings.enabled) timings.pubstompMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

    if(stage != null) {
      RelativeScore stageScore = score.stageScores[stage]!;

      // If the shooter has already had a rating change for this stage, don't recalc.
      for(var existingScore in changes[rating]!.keys) {
        if(existingScore.stage == stage) return;
      }

      _encounteredMemberNumber(memNum);

      if(Timings.enabled) start = DateTime.now();
      var update = ratingSystem.updateShooterRatings(
        shooters: [rating],
        scores: stageScores,
        matchScores: matchScores,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
        eventWeightMultiplier: weightMod,
      );
      if(Timings.enabled) timings.updateMillis += (DateTime.now().difference(start).inMicroseconds).toDouble();

      if(!changes[rating]!.containsKey(stageScore)) {
        changes[rating]![stageScore] = ratingSystem.newEvent(rating: rating, match: match, stage: stage, score: stageScore);
        changes[rating]![stageScore]!.apply(update[rating]!);
        changes[rating]![stageScore]!.info = update[rating]!.info;
      }
    }
    else {
      _encounteredMemberNumber(memNum);

      var update = ratingSystem.updateShooterRatings(
        shooters: [rating],
        scores: matchScores,
        matchScores: matchScores,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
      );

      // You only get one rating change per match.
      if(changes[rating]!.isEmpty) {
        changes[rating]![score.total] = ratingSystem.newEvent(
          rating: rating,
          match: match,
          score: score.total,
          info: update[rating]!.info,
        );

        changes[rating]![score.total]!.apply(update[rating]!);
      }
    }
  }

  void _processWholeEvent({
    required PracticalMatch match,
    Stage? stage,
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
      var matchScoreMap = <ShooterRating, RelativeScore>{};
      for(var s in scores) {
        String num = s.shooter.memberNumber;

        var otherScore = s.stageScores[stage]!;
        _encounteredMemberNumber(num);
        scoreMap[knownShooters[num]!] = otherScore;
        matchScoreMap[knownShooters[num]!] = s.total;
        changes[knownShooters[num]!] ??= {};
      }

      var update = ratingSystem.updateShooterRatings(
        shooters: scoreMap.keys.toList(),
        scores: scoreMap,
        matchScores: matchScoreMap,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
        eventWeightMultiplier: weightMod,
      );

      for(var rating in scoreMap.keys) {
        var stageScore = scoreMap[rating];

        if(stageScore == null) {
          print("Null stage score for $rating on ${stage.name}");
          continue;
        }

        if (!changes[rating]!.containsKey(stageScore)) {
          changes[rating]![stageScore] = ratingSystem.newEvent(rating: rating, match: match, stage: stage, score: stageScore);
          changes[rating]![stageScore]!.apply(update[rating]!);
          changes[rating]![stageScore]!.info = update[rating]!.info;
        }
      }
    }
    else {
      var scoreMap = <ShooterRating, RelativeScore>{};
      var matchScoreMap = <ShooterRating, RelativeScore>{};
      for(var s in scores) {
        String num = s.shooter.memberNumber;

        scoreMap[knownShooters[num]!] ??= s.total;
        matchScoreMap[knownShooters[num]!] ??= s.total;
        changes[knownShooters[num]!] ??= {};
        _encounteredMemberNumber(num);
      }

      var update = ratingSystem.updateShooterRatings(
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
            info: update[rating]!.info,
          );

          changes[rating]![score]!.apply(update[rating]!);
        }
      }
    }
  }

  bool _isValid(RelativeScore score) {
    // Filter out badly marked classifier reshoots
    if(score.score.hits == 0 && score.score.time <= 0.1) return false;

    // The George Williams Rule
    if(score.stage != null && score.stage!.type != Scoring.fixedTime && score.score.getHitFactor() > 30) return false;

    // Filter out extremely short times that are probably DNFs or partial scores entered for DQs
    if(score.stage!.type != Scoring.fixedTime && score.score.time <= 0.5) return false;

    return true;
  }

  bool _pubstomp(List<RelativeMatchScore> scores) {
    if(scores.length < 2) return false;

    var sorted = scores.sorted((a, b) => b.total.percent.compareTo(a.total.percent));

    var first = sorted[0];
    var second = sorted[1];

    var firstScore = first.total;
    var secondScore = second.total;

    var firstClass = first.shooter.classification ?? Classification.U;
    var secondClass = second.shooter.classification ?? Classification.U;

    var firstRating = knownShooters[first.shooter.memberNumber];
    var secondRating = knownShooters[second.shooter.memberNumber];

    // People entered with empty or invalid member numbers
    if(firstRating == null || secondRating == null) {
      // print("Unexpected null in pubstomp detection");
      return false;
    }

    // if(processMemberNumber(first.shooter.memberNumber) == "68934" || processMemberNumber(first.shooter.memberNumber) == "5172") {
    //   debugPrint("${firstScore.percent.toStringAsFixed(2)} ${(firstScore.relativePoints/secondScore.relativePoints).toStringAsFixed(3)}");
    //   debugPrint("${firstRating.rating.round()} > ${secondRating.rating.round()}");
    // }

    // It's only a pubstomp if:
    // 1. The winner wins by more than 25%.
    // 2. The winner is M shooting against no better than B or GM shooting against no better than A.
    // 3. The winner's rating is at least 200 higher than the next shooter's.
    if(firstScore.percent >= 1.0
        && (firstScore.relativePoints / secondScore.relativePoints > 1.20)
        && firstClass.index <= Classification.M.index
        && secondClass.index - firstClass.index >= 2
        && firstRating.rating - secondRating.rating > 200) {
      // print("Pubstomp multiplier for $firstRating over $secondRating");
      return true;

    }
    return false;
  }

  bool _dnf(RelativeMatchScore score) {
    for(var stageScore in score.stageScores.values) {
      if(stageScore.stage!.type != Scoring.chrono && stageScore.score.time <= 0.01 && stageScore.score.hits == 0) {
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

  double _strengthForClass(Classification? c) {
    switch(c) {
      case Classification.GM:
        return 10;
      case Classification.M:
        return 6;
      case Classification.A:
        return 4;
      case Classification.B:
        return 3;
      case Classification.C:
        return 2;
      case Classification.D:
        return 1;
      case Classification.U:
        return _strengthForClass(Classification.C);
      default:
        return 2.5;
    }
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

    var histogram = <int, int>{};
    for(var rating in allRatings) {
      // Buckets 100 wide
      var bucket = (0 + (rating / bucketSize).floor());

      var value = histogram[bucket] ?? 0;
      value += 1;
      histogram[bucket] = value;
    }

    var averagesByClass = <Classification, double>{};
    var minsByClass = <Classification, double>{};
    var maxesByClass = <Classification, double>{};
    var countsByClass = <Classification, int>{};
    Map<Classification, Map<int, int>> histogramsByClass = {};
    Map<Classification, List<double>> ratingsByClass = {};

    for(var classification in Classification.values) {
      if(classification == Classification.unknown) continue;

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

        var value = histogramsByClass[classification]![bucket] ?? 0;
        value += 1;
        histogramsByClass[classification]![bucket] = value;
      }
    }

    return RaterStatistics(
      shooters: count,
      averageRating: allRatings.average,
      minRating: allRatings.min,
      maxRating: allRatings.max,
      histogram: histogram,
      countByClass: countsByClass,
      averageByClass: averagesByClass,
      minByClass: minsByClass,
      maxByClass: maxesByClass,
      histogramsByClass: histogramsByClass,
      histogramBucketSize: bucketSize,
      ratingsByClass: ratingsByClass,
    );
  }

  @override
  String toString() {
    return "Rater for ${_matches.last.name} with ${_filters?.divisions}";
  }

  static Map<String, String> _processMemNumCache = {};
  static String processMemberNumber(String no) {
    if(_processMemNumCache.containsKey(no)) return _processMemNumCache[no]!;
    var no2 = no.replaceAll(RegExp(r"[^0-9]"), "");
    _processMemNumCache[no] = no2;
    return no2;
  }
}

extension _StrengthBonus on MatchLevel {
  double get strengthBonus {
    switch(this) {
      case MatchLevel.I:
        return 1.0;
      case MatchLevel.II:
        return 1.15;
      case MatchLevel.III:
        return 1.3;
      case MatchLevel.IV:
        return 1.45;
    }
  }
}

class RaterStatistics {
  int shooters;
  double averageRating;
  double minRating;
  double maxRating;

  int histogramBucketSize;
  Map<int, int> histogram;

  Map<Classification, int> countByClass;
  Map<Classification, double> averageByClass;
  Map<Classification, double> minByClass;
  Map<Classification, double> maxByClass;

  Map<Classification, Map<int, int>> histogramsByClass;
  Map<Classification, List<double>> ratingsByClass;

  RaterStatistics({
    required this.shooters,
    required this.averageRating,
    required this.minRating,
    required this.maxRating,
    required this.countByClass,
    required this.averageByClass,
    required this.minByClass,
    required this.maxByClass,
    required this.histogramBucketSize,
    required this.histogram,
    required this.histogramsByClass,
    required this.ratingsByClass,
  });
}

class _Tuple<T, U> {
  T a;
  U b;

  _Tuple(this.a, this.b);
}