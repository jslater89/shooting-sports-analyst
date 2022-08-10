import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/sorted_list.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';

class Rater {
  List<PracticalMatch> _matches;
  Map<String, ShooterRating> knownShooters = {};
  Map<String, String> _memberNumberMappings = {};
  Set<String> _memberNumbersEncountered = Set<String>();
  RatingSystem ratingSystem;
  FilterSet? _filters;
  bool byStage;
  Future<void> Function(int, int)? progressCallback;

  Set<ShooterRating> get uniqueShooters => <ShooterRating>{}..addAll(knownShooters.values);

  Rater({required List<PracticalMatch> matches, required this.ratingSystem, FilterSet? filters, this.byStage = false, this.progressCallback}) : this._matches = matches, this._filters = filters {
    _matches.sort((a, b) {
      if(a.date == null && b.date == null) {
        return 0;
      }
      if(a.date == null) return -1;
      if(b.date == null) return 1;

      return a.date!.compareTo(b.date!);
    });

    for(PracticalMatch m in _matches) {
      _addShootersFromMatch(m);
    }

    _deduplicateShooters();
  }

  Future<void> calculateInitialRatings() async {
    int totalSteps = _matches.length;
    int currentSteps = 0;
    for(PracticalMatch m in _matches) {
      _rankMatch(m);

      currentSteps += 1;
      await progressCallback?.call(currentSteps, totalSteps);
    }

    _removeUnseenShooters();

    debugPrint("Initial ratings complete for ${knownShooters.length} shooters in ${_matches.length} matches in ${_filters != null ? _filters!.activeDivisions.toList() : "all divisions"}");
  }

  Rater.copy(Rater other) :
      this.knownShooters = {},
      this._matches = other._matches.map((m) => m.copy()).toList(),
      this.byStage = other.byStage,
      this._memberNumbersEncountered = Set()..addAll(other._memberNumbersEncountered),
      this._memberNumberMappings = {}..addAll(other._memberNumberMappings),
      this._filters = other._filters,
      this.ratingSystem = other.ratingSystem {
    List<String> secondPass = [];
    for(var entry in _memberNumberMappings.entries) {
      if(entry.key == entry.value) {
        // If, per the member number mappings, this is the canonical mapping, copy it immediately.
        // (The canonical mapping is the one where mappings[num] = num—i.e., no mapping)
        knownShooters[entry.value] = ShooterRating.copy(other.knownShooters[entry.value]!);
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

    _addShootersFromMatch(match);
    _deduplicateShooters();

    _rankMatch(match);

    _removeUnseenShooters();

    debugPrint("Ratings update complete for ${knownShooters.length} shooters in ${_matches.length} matches in ${_filters != null ? _filters!.activeDivisions.toList() : "all divisions"}");
  }

  void _addShootersFromMatch(PracticalMatch match) {
    var shooters = _getShooters(match);
    for(Shooter s in shooters) {
      if(processMemberNumber(s.memberNumber).isNotEmpty && !s.reentry && s.memberNumber.length > 3) {
        knownShooters[processMemberNumber(s.memberNumber)] ??= ShooterRating(s, RatingSystem.initialClassRatings[s.classification] ?? 800.0); // ratingSystem.defaultRating
      }
    }
  }

  void _deduplicateShooters() {
    Map<String, List<String>> namesToNumbers = {};

    for(var num in knownShooters.keys) {
      var shooter = knownShooters[num]!.shooter;
      var name = "${shooter.firstName.toLowerCase()}${shooter.lastName.toLowerCase()}";

      namesToNumbers[name] ??= [];
      namesToNumbers[name]!.add(num);

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

  List<Shooter> _getShooters(PracticalMatch match) {
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
    return shooters;
  }

  void _rankMatch(PracticalMatch match) {
    var shooters = _getShooters(match);
    var scores = match.getScores(shooters: shooters, scoreDQ: byStage);

    // Based on strength of competition, vary rating gain between 25% and 150%.
    var matchStrength = 0.0;
    for(var shooter in shooters) {
      matchStrength += _strengthForClass(shooter.classification);

      var rating = knownShooters[processMemberNumber(shooter.memberNumber)];
      if(rating != null) {
        rating.lastClassification = shooter.classification ?? rating.lastClassification;
      }
    }
    matchStrength = matchStrength / shooters.length;
    double strengthMod =  (1.0 + max(-0.75, min(0.5, ((matchStrength) - _strengthForClass(Classification.A)) * 0.2))) * (match.level?.strengthBonus ?? 1.0);

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
    var globalAverageConnectedness = totalShooters < 1 ? 105 : totalConnectedness / totalShooters;
    var globalMedianConnectedness = totalShooters < 1 ? 105 : connectednesses[connectednesses.length ~/ 2];
    var connectednessDenominator = globalMedianConnectedness;

    totalConnectedness = 0.0;
    totalShooters = 0;
    for(var shooter in shooters) {
      var rating = knownShooters[processMemberNumber(shooter.memberNumber)];

      if(rating != null) {
        totalConnectedness += rating.connectedness;
        totalShooters += 1;
      }
    }
    var localAverageConnectedness = totalConnectedness / (totalShooters > 0 ? totalShooters : 1.0);
    var connectednessMod = /*1.0;*/ 1.0 + max(-0.2, min(0.2, (((localAverageConnectedness / connectednessDenominator) - 1.0) * 2))); // * 1: how much to adjust the percentages by

    // debugPrint("Connectedness for ${match.name}: ${localAverageConnectedness.toStringAsFixed(2)}/${connectednessDenominator.toStringAsFixed(2)} => ${connectednessMod.toStringAsFixed(3)}");

    Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes = {};
    Set<ShooterRating> shootersAtMatch = Set();

    // Process ratings for each shooter.
    if(byStage) {
      for(Stage s in match.stages) {
        var weightMod = 1.0 + max(-0.20, min(0.10, (s.maxPoints - 120) /  400));

        for(int i = 0; i < shooters.length; i++) {
          if(ratingSystem.mode == RatingMode.roundRobin) {
            _processRoundRobin(match, s, shooters, scores, i, changes, strengthMod, connectednessMod, weightMod);
          }
          else {
            _processOneshot(match, s, shooters[i], scores, changes, strengthMod, connectednessMod, weightMod);
          }
        }

        for(var r in changes.keys) {
          var totalChange = 0.0;

          for(var event in changes[r]!.values) {
            totalChange += event.ratingChange;
            r.rating += event.ratingChange;
            r.ratingEvents.add(event);
          }

          r.updateTrends(totalChange);
          shootersAtMatch.add(r);
        }
        changes.clear();
      }
    }
    else {
      for(int i = 0; i < shooters.length; i++) {
        if(ratingSystem.mode == RatingMode.roundRobin) {
          _processRoundRobin(match, null, shooters, scores, i, changes, strengthMod, connectednessMod, 1.0);
        }
        else {
          _processOneshot(match, null, shooters[i], scores, changes, strengthMod, connectednessMod, 1.0);
        }
      }

      for(var r in changes.keys) {
        var totalChange = 0.0;

        for(var event in changes[r]!.values) {
          totalChange += event.ratingChange;
          r.rating += event.ratingChange;
          r.ratingEvents.add(event);
        }

        shootersAtMatch.add(r);
        r.updateTrends(totalChange);
      }
      changes.clear();
    }

    if(match.date != null && shooters.length > 1) {
      var averageBefore = 0.0;
      var averageAfter = 0.0;

      var encounteredList = shootersAtMatch.toList();

      // debugPrint("Updating connectedness at ${match.name} for ${shootersAtMatch.length} of ${knownShooters.length} shooters");
      for (var rating in encounteredList) {
        averageBefore += rating.connectedness;
        rating.updateConnections(match.date!, encounteredList);
      }

      for (var rating in encounteredList) {
        rating.updateConnectedness();
        averageAfter += rating.connectedness;
      }

      averageBefore /= encounteredList.length;
      averageAfter /= encounteredList.length;
      // debugPrint("Averages: ${averageBefore.toStringAsFixed(1)} -> ${averageAfter.toStringAsFixed(1)} vs. ${expectedConnectedness.toStringAsFixed(1)}");
    }

  }

  bool _verifyShooter(Shooter s) {
    if(s.memberNumber.isEmpty) return false;
    if(s.memberNumber.length <= 3) return false;
    if(!byStage && s.dq) return false;
    if(s.reentry) return false;

    String memNum = processMemberNumber(s.memberNumber);
    if(s.firstName.endsWith("2") || s.lastName.endsWith("2") || s.firstName.endsWith("3") || s.firstName.endsWith("3")) return false;

    if(knownShooters[memNum] == null) return false;

    return true;
  }

  void _processRoundRobin(PracticalMatch match, Stage? stage, List<Shooter> shooters, List<RelativeMatchScore> scores, int startIndex, Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes, double matchStrength, double connectednessMod, double weightMod) {
    Shooter a = shooters[startIndex];
    var score = scores.firstWhere((element) => element.shooter == a);

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

      if(!_verifyShooter(a) || !_verifyShooter(b)) {
        continue;
      }

      String memNumA = processMemberNumber(a.memberNumber);
      String memNumB = processMemberNumber(b.memberNumber);

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

        // Filter out badly marked classifier reshoots
        if(aStageScore.score.hits == 0 && aStageScore.score.time <= 0.1) continue;
        if(bStageScore.score.hits == 0 && bStageScore.score.time <= 0.1) continue;

        // The George Williams Rule
        if(aStageScore.stage!.type != Scoring.fixedTime && aStageScore.score.getHitFactor() > 30) continue;
        if(bStageScore.stage!.type != Scoring.fixedTime && bStageScore.score.getHitFactor() > 30) continue;

        // Filter out extremely short times that are probably DNFs or partial scores entered for DQs
        if(aStageScore.score.time <= 0.5) continue;
        if(bStageScore.score.time <= 0.5) continue;

        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          shooters: [aRating, bRating],
          scores: {
            aRating: aStageScore,
            bRating: bStageScore,
          },
          matchStrengthMultiplier: matchStrength,
          connectednessMultiplier: connectednessMod,
          eventWeightMultiplier: weightMod,
        );

        changes[aRating]![aStageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: aStageScore);
        changes[bRating]![bStageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: bStageScore);

        changes[aRating]![aStageScore]!.ratingChange += update[aRating]!.change;
        changes[bRating]![bStageScore]!.ratingChange += update[bRating]!.change;
      }
      else {
        // Filter out non-DQ DNFs
        if(_dnf(aScore) || _dnf(bScore))

        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          shooters: [aRating, bRating],
          scores: {
            aRating: aScore.total,
            bRating: bScore.total,
          },
          matchStrengthMultiplier: matchStrength,
          connectednessMultiplier: connectednessMod,
        );

        changes[aRating]![aScore.total] ??= RatingEvent(eventName: "${match.name}", score: aScore.total, ratingChange: update[aRating]!.change);
        changes[bRating]![bScore.total] ??= RatingEvent(eventName: "${match.name}", score: bScore.total, ratingChange: update[bRating]!.change);
      }
    }
  }

  void _processOneshot(PracticalMatch match, Stage? stage, Shooter shooter, List<RelativeMatchScore> scores, Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes, double matchStrength, double connectednessMod, double weightMod) {
    if(!_verifyShooter(shooter)) {
      return;
    }

    String memNum = processMemberNumber(shooter.memberNumber);

    ShooterRating rating = knownShooters[memNum]!;
    changes[rating] ??= {};
    RelativeMatchScore score = scores.firstWhere((score) => score.shooter == shooter);

    // Check for pubstomp
    var pubstompMod = 1.0;
    if(score.total.percent >= 1.0) {
      if(_pubstomp(scores)) {
        pubstompMod = 0.33;
      }
    }
    matchStrength *= pubstompMod;

    if(stage != null) {
      RelativeScore stageScore = score.stageScores[stage]!;

      // Filter out badly marked classifier reshoots
      if(stageScore.score.hits == 0 && stageScore.score.time == 0.0) return;

      // The George Williams Rule
      if(stageScore.stage!.type != Scoring.fixedTime && stageScore.score.getHitFactor() > 30) return;

      // Filter out extremely short times that are probably DNFs or partial scores entered for DQs
      if(stageScore.score.time <= 0.5) return;

      _encounteredMemberNumber(memNum);

      var scoreMap = <ShooterRating, RelativeScore>{};
      for(var s in scores) {
        if(!_verifyShooter(s.shooter)) continue;

        String num = processMemberNumber(s.shooter.memberNumber);
        var otherScore = s.stageScores[stage]!;
        if(otherScore.score.hits == 0 && otherScore.score.time == 0) continue;
        scoreMap[knownShooters[num]!] = otherScore;
      }

      var update = ratingSystem.updateShooterRatings(
        shooters: [rating],
        scores: scoreMap,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
        eventWeightMultiplier: weightMod,
      );

      changes[rating]![stageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: stageScore);
      changes[rating]![stageScore]!.ratingChange += update[rating]!.change;
      changes[rating]![stageScore]!.info = update[rating]!.info;
    }
    else {
      // Filter out non-DQ DNFs
      if(_dnf(score)) return;

      _encounteredMemberNumber(memNum);

      var scoreMap = <ShooterRating, RelativeScore>{};
      for(var s in scores) {
        if(!_verifyShooter(s.shooter)) continue;
        String num = processMemberNumber(s.shooter.memberNumber);

        scoreMap[knownShooters[num]!] = s.total;
      }
      var update = ratingSystem.updateShooterRatings(
        shooters: [rating],
        scores: scoreMap,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
      );

      changes[rating]![score.total] ??= RatingEvent(eventName: "${match.name}",
        score: score.total,
        ratingChange: update[rating]!.change,
        info: update[rating]!.info,
      );
    }
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

    var firstRating = knownShooters[processMemberNumber(first.shooter.memberNumber)];
    var secondRating = knownShooters[processMemberNumber(second.shooter.memberNumber)];

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
      if(stageScore.stage!.type != Scoring.chrono && stageScore.score.time <= 0.01 && stageScore.score.hits == 0) return true;
    }

    return false;
  }

  String toCSV() {
    String csv = "Member#,Name,Rating,Variance,Trend,Stages\n";

    var sortedShooters = uniqueShooters.sorted((a, b) => b.rating.compareTo(a.rating));

    for(var s in sortedShooters) {
      csv += "${Rater.processMemberNumber(s.shooter.memberNumber)},";
      csv += "${s.shooter.getName()},";
      csv += "${s.rating.round()},${s.variance.toStringAsFixed(2)},${s.trend.toStringAsFixed(2)},${s.ratingEvents.length}\n";
    }

    return csv;
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
  RaterStatistics getStatistics() {
    if(_cachedStats == null) _calculateStats();

    return _cachedStats!;
  }

  void _calculateStats() {
    var count = knownShooters.length;
    var allRatings = knownShooters.values.map((r) => r.rating);

    var histogram = <int, int>{};
    for(var rating in allRatings) {
      // Buckets 100 wide
      var bucket = (0 + (rating / 100).floor());

      var value = histogram[bucket] ?? 0;
      value += 1;
      histogram[bucket] = value;
    }

    var averagesByClass = <Classification, double>{};
    var minsByClass = <Classification, double>{};
    var maxesByClass = <Classification, double>{};
    var countsByClass = <Classification, int>{};

    for(var classification in Classification.values) {
      if(classification == Classification.unknown) continue;

      var shootersInClass = knownShooters.values.where((r) => r.lastClassification == classification);
      var ratingsInClass = shootersInClass.map((r) => r.rating);

      averagesByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.average : 0;
      minsByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.min : 0;
      maxesByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.max : 0;
      countsByClass[classification] = ratingsInClass.length;
    }

    _cachedStats = RaterStatistics(
      shooters: count,
      averageRating: allRatings.average,
      minRating: allRatings.min,
      maxRating: allRatings.max,
      histogram: histogram,
      countByClass: countsByClass,
      averageByClass: averagesByClass,
      minByClass: minsByClass,
      maxByClass: maxesByClass,
    );
  }

  static String processMemberNumber(String no) {
    no = no.replaceAll(RegExp(r"[^0-9]"), "");
    return no;
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

  Map<int, int> histogram;

  Map<Classification, int> countByClass;
  Map<Classification, double> averageByClass;
  Map<Classification, double> minByClass;
  Map<Classification, double> maxByClass;

  RaterStatistics({
    required this.shooters,
    required this.averageRating,
    required this.minRating,
    required this.maxRating,
    required this.countByClass,
    required this.averageByClass,
    required this.minByClass,
    required this.maxByClass,
    required this.histogram,
  });
}