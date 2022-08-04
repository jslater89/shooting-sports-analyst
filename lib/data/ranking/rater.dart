import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';

class Rater {
  List<PracticalMatch> _matches;
  Map<String, ShooterRating> knownShooters = {};
  Map<String, String> _memberNumberMappings = {};
  Set<String> _memberNumbersEncountered = Set<String>();
  RatingSystem ratingSystem;
  FilterSet? _filters;
  bool byStage;

  Set<ShooterRating> get uniqueShooters => <ShooterRating>{}..addAll(knownShooters.values);

  Rater({required List<PracticalMatch> matches, required this.ratingSystem, FilterSet? filters, this.byStage = false}) : this._matches = matches, this._filters = filters {
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

    for(PracticalMatch m in _matches) {
      _rankMatch(m);
    }

    _removeUnseenShooters();

    debugPrint("Initial ratings complete for ${knownShooters.length} shooters in ${_matches.length} matches in ${filters != null ? filters.activeDivisions.toList() : "all divisions"}");
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
      debugPrint("Mapped $mappedNumber to $actualNumber with ${knownShooters[actualNumber]?.ratingEvents.length} ratings during copy");

      if(knownShooters[actualNumber] == null) {
        // break
      }

      knownShooters[mappedNumber] = knownShooters[actualNumber]!;
    }
  }

  
  void addMatch(PracticalMatch match) {
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
        knownShooters[processMemberNumber(s.memberNumber)] ??= ShooterRating(s, ratingSystem.defaultRating);
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

        debugPrint("Shooter $name has two member numbers, not already mapped: $list (${knownShooters[list[0]]}, ${knownShooters[list[1]]})");

        var rating0 = knownShooters[list[0]]!;
        var rating1 = knownShooters[list[1]]!;

        if (rating0.ratingEvents.length > 0 && rating1.ratingEvents.length > 0) {
          throw StateError("Both ratings have events");
        }

        if (rating0.ratingEvents.length == 0) {
          rating0.copyRatingFrom(rating1);
          knownShooters[list[1]] = rating0;
          _memberNumberMappings[list[1]] = list[0];

          debugPrint("Mapped r1-r0 ${list[1]} to ${list[0]} with ${rating0.ratingEvents.length} ratings during deduplication");
        }
        else {
          rating1.copyRatingFrom(rating0);
          knownShooters[list[0]] = rating1;
          _memberNumberMappings[list[0]] = list[1];

          debugPrint("Mapped r0-r1 ${list[0]} to ${list[1]} with ${rating1.ratingEvents.length} ratings during deduplication");
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
    var scores = match.getScores(shooters: shooters, scoreDQ: false);

    // Based on strength of competition, vary rating gain between 50% and 130%.
    var matchStrength = 0.0;
    for(var shooter in shooters) {
      matchStrength += _strengthForClass(shooter.classification);
    }
    matchStrength = matchStrength / shooters.length;
    double strengthMod = 1.0 + max(-0.5, min(1.3, ((matchStrength) - 4) * 0.2));

    Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes = {};

    // Process ratings for each shooter.
    if(byStage) {
      for(Stage s in match.stages) {
        for(int i = 0; i < shooters.length; i++) {
          if(ratingSystem.mode == RatingMode.roundRobin) {
            _processRoundRobin(match, s, shooters, scores, i, changes, strengthMod);
          }
          else {
            _processOneshot(match, s, shooters[i], scores, changes, strengthMod);
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
        }
        changes.clear();
      }
    }
    else {
      for(int i = 0; i < shooters.length; i++) {
        if(ratingSystem.mode == RatingMode.roundRobin) {
          _processRoundRobin(match, null, shooters, scores, i, changes, strengthMod);
        }
        else {
          _processOneshot(match, null, shooters[i], scores, changes, strengthMod);
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
      }
      changes.clear();
    }
  }

  bool _verifyShooter(Shooter s) {
    if(s.memberNumber.isEmpty) return false;
    if(s.memberNumber.length <= 3) return false;
    if(s.dq) return false;
    if(s.reentry) return false;

    String memNum = processMemberNumber(s.memberNumber);
    if(s.firstName.endsWith("2") || s.lastName.endsWith("2") || s.firstName.endsWith("3") || s.firstName.endsWith("3")) return false;

    if(knownShooters[memNum] == null) return false;

    return true;
  }

  void _processRoundRobin(PracticalMatch match, Stage? stage, List<Shooter> shooters, List<RelativeMatchScore> scores, int startIndex, Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes, double matchStrength) {
    for(int j = startIndex + 1; j < shooters.length; j++) {
      Shooter a = shooters[startIndex];
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
        if(aStageScore.score.hits == 0 && aStageScore.score.time == 0) continue;
        if(bStageScore.score.hits == 0 && bStageScore.score.time == 0) continue;

        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          shooters: [aRating, bRating],
          scores: {
            aRating: aStageScore,
            bRating: bStageScore,
          },
          matchStrength: matchStrength,
        );

        changes[aRating]![aStageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: aStageScore);
        changes[bRating]![bStageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: bStageScore);

        changes[aRating]![aStageScore]!.ratingChange += update[aRating]!.change;
        changes[bRating]![bStageScore]!.ratingChange += update[bRating]!.change;
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
          matchStrength: matchStrength,
        );

        changes[aRating]![aScore.total] ??= RatingEvent(eventName: "${match.name}", score: aScore.total, ratingChange: update[aRating]!.change);
        changes[bRating]![bScore.total] ??= RatingEvent(eventName: "${match.name}", score: bScore.total, ratingChange: update[bRating]!.change);
      }
    }
  }

  void _processOneshot(PracticalMatch match, Stage? stage, Shooter shooter, List<RelativeMatchScore> scores, Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes, double matchStrength) {
    if(!_verifyShooter(shooter)) {
      return;
    }

    String memNum = processMemberNumber(shooter.memberNumber);

    ShooterRating rating = knownShooters[memNum]!;
    changes[rating] ??= {};
    RelativeMatchScore score = scores.firstWhere((score) => score.shooter == shooter);

    if(stage != null) {
      RelativeScore stageScore = score.stageScores[stage]!;

      // Filter out badly marked classifier reshoots
      if(stageScore.score.hits == 0 && stageScore.score.time == 0) return;

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
        matchStrength: matchStrength,
      );

      changes[rating]![stageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: stageScore);
      changes[rating]![stageScore]!.ratingChange += update[rating]!.change;
      changes[rating]![stageScore]!.info = update[rating]!.info;
    }
    else {
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
        matchStrength: matchStrength,
      );

      changes[rating]![score.total] ??= RatingEvent(eventName: "${match.name}",
        score: score.total,
        ratingChange: update[rating]!.change,
        info: update[rating]!.info,
      );
    }
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
        return 8;
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
        return 0;
      default:
        return 2.5;
    }
  }

  static String processMemberNumber(String no) {
    no = no.replaceAll(RegExp(r"[^0-9]"), "");
    return no;
  }
}