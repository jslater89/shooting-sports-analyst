import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';

class Rater {
  List<PracticalMatch> _matches;
  Map<String, ShooterRating> knownShooters = {};
  Set<String> _memberNumbersEncountered = Set<String>();
  RatingSystem ratingSystem;
  FilterSet? _filters;
  bool byStage;

  Rater({required List<PracticalMatch> matches, required this.ratingSystem, FilterSet? filters, this.byStage = false}) : this._matches = matches, this._filters = filters {
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
      this.knownShooters = other.knownShooters.map((key, value) => MapEntry(key, ShooterRating.copy(value))),
      this._matches = other._matches.map((m) => m.copy()).toList(),
      this.byStage = other.byStage,
      this._memberNumbersEncountered = Set()..addAll(other._memberNumbersEncountered),
      this._filters = other._filters,
      this.ratingSystem = other.ratingSystem;

  
  void addMatch(PracticalMatch match) {
    _matches.add(match);

    _addShootersFromMatch(match);
    _deduplicateShooters();

    _rankMatch(match);

    _removeUnseenShooters();

    debugPrint("Ratings update complete for ${knownShooters.length} shooters in ${_matches.length} matches in ${_filters != null ? _filters!.activeDivisions.toList() : "all divisions"}");
  }

  void _addShootersFromMatch(PracticalMatch match) {
    for(Shooter s in match.shooters) {
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
    }

    // shooter numbers to remove from known shooters, because they're duplicates
    var numsToRemove = <String>[];

    for(var name in namesToNumbers.keys) {
      var list = namesToNumbers[name]!;
      if(list.length == 2) {
        debugPrint("Shooter $name has two member numbers: $list");
        if(list[0].length <= 4 && list[1].length > 4) {
          knownShooters[list[1]] = knownShooters[list[0]]!;
          numsToRemove.add(list[1]);
        }
        else if(list[1].length <= 4 && list[0].length > 4) {
          knownShooters[list[0]] = knownShooters[list[1]]!;
          numsToRemove.add(list[0]);
        }
      }
    }
  }

  void _removeUnseenShooters() {
    List<String> shooterNumbers = knownShooters.keys.toList();
    for(String num in shooterNumbers) {
      if(!_memberNumbersEncountered.contains(num)) {
        knownShooters.remove(num);
      }
    }
  }

  void _rankMatch(PracticalMatch match) {
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
    var scores = match.getScores(shooters: shooters, scoreDQ: false);

    // Based on strength of competition, vary rating gain between 50% and 130%.
    var matchStrength = 0.0;
    for(var shooter in shooters) {
      matchStrength += _strengthForClass(shooter.classification);
    }
    matchStrength = matchStrength / shooters.length;
    double strengthMod = 1.0 + max(-0.5, min(1.3, ((matchStrength) - 4) * 0.2));

    Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes = {};

    // TODO: pull match stage iteration out to here, if present.
    // TODO: don't update ratings in the rating system—do that here
    // TODO: gather rating events for each match/stage, and apply them after all changes have been calculated
    //        (this means you aren't handicapping/handicapped based on your ratings happening first)

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
          for(var event in changes[r]!.values) {
            r.rating += event.ratingChange;
            r.ratingEvents.add(event);
          }
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
        for(var event in changes[r]!.values) {
          r.rating += event.ratingChange;
          r.ratingEvents.add(event);
        }
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

      _memberNumbersEncountered.add(memNumA);
      _memberNumbersEncountered.add(memNumB);

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

        changes[aRating]![aStageScore]!.ratingChange += update[aRating]!;
        changes[bRating]![bStageScore]!.ratingChange += update[bRating]!;
      }
      else {
        var update = ratingSystem.updateShooterRatings(
          shooters: [aRating, bRating],
          scores: {
            aRating: aScore.total,
            bRating: bScore.total,
          },
          matchStrength: matchStrength,
        );

        changes[aRating]![aScore.total] ??= RatingEvent(eventName: "${match.name}", score: aScore.total, ratingChange: update[aRating]!);
        changes[bRating]![bScore.total] ??= RatingEvent(eventName: "${match.name}", score: bScore.total, ratingChange: update[bRating]!);
      }
    }
  }

  void _processOneshot(PracticalMatch match, Stage? stage, Shooter shooter, List<RelativeMatchScore> scores, Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes, double matchStrength) {
    if(!_verifyShooter(shooter)) {
      return;
    }

    String memNum = processMemberNumber(shooter.memberNumber);
    _memberNumbersEncountered.add(memNum);

    ShooterRating rating = knownShooters[memNum]!;
    changes[rating] ??= {};
    RelativeMatchScore score = scores.firstWhere((score) => score.shooter == shooter);

    if(stage != null) {
      RelativeScore stageScore = score.stageScores[stage]!;

      // Filter out badly marked classifier reshoots
      if(stageScore.score.hits == 0 && stageScore.score.time == 0) return;

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
      changes[rating]![stageScore]!.ratingChange += update[rating]!;
    }
    else {
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
          ratingChange: update[rating]!);
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