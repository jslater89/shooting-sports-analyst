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
      for(Shooter s in m.shooters) {
        if(_processMemberNumber(s.memberNumber).isNotEmpty && !s.reentry && s.memberNumber.length > 3) {
          knownShooters[_processMemberNumber(s.memberNumber)] = ShooterRating(s, ratingSystem.defaultRating);
        }
      }
    }

    for(PracticalMatch m in _matches) {
      _rankMatch(m);
    }

    List<String> shooterNumbers = knownShooters.keys.toList();
    for(String num in shooterNumbers) {
      if(!_memberNumbersEncountered.contains(num)) {
        knownShooters.remove(num);
      }
    }

    debugPrint("Rated ${knownShooters.length} shooters in ${_matches.length} matches in ${filters != null ? filters!.activeDivisions.toList() : "all divisions"}");
  }
  
  void addMatch(PracticalMatch match) {
    _matches.add(match);
    _rankMatch(match);
  }

  void _rankMatch(PracticalMatch match) {
    var scores = match.getScores(scoreDQ: false);
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

    Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes = {};

    for(int i = 0; i < shooters.length; i++) {
      if(ratingSystem.mode == RatingMode.roundRobin) {
        _processRoundRobin(match, shooters, scores, i, changes);
      }
      else {
        _processOneshot(match, shooters[i], scores, changes);
      }
    }

    for(var r in changes.keys) {
      for(var event in changes[r]!.values) {
        r.ratingEvents.add(event);
      }
    }
  }

  bool _verifyShooter(Shooter s) {
    if(s.memberNumber.isEmpty) return false;
    if(s.memberNumber.length <= 3) return false;
    if(s.dq) return false;
    if(s.reentry) return false;

    String memNum = _processMemberNumber(s.memberNumber);
    if(s.firstName.endsWith("2") || s.lastName.endsWith("2") || s.firstName.endsWith("3") || s.firstName.endsWith("3")) return false;

    if(knownShooters[memNum] == null) return false;

    return true;
  }

  void _processRoundRobin(PracticalMatch match, List<Shooter> shooters, List<RelativeMatchScore> scores, int startIndex, Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes) {
    for(int j = startIndex + 1; j < shooters.length; j++) {
      Shooter a = shooters[startIndex];
      Shooter b = shooters[j];

      if(!_verifyShooter(a) || !_verifyShooter(b)) {
        continue;
      }

      String memNumA = _processMemberNumber(a.memberNumber);
      String memNumB = _processMemberNumber(b.memberNumber);

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

      if(byStage) {
        for(Stage stage in match.stages) {
          RelativeScore aStageScore = aScore.stageScores[stage]!;
          RelativeScore bStageScore = bScore.stageScores[stage]!;

          // Filter out badly marked classifier reshoots
          if(aStageScore.score.hits == 0 && aStageScore.score.time == 0) continue;
          if(bStageScore.score.hits == 0 && bStageScore.score.time == 0) continue;

          var update = ratingSystem.updateShooterRatings(
            {
              aRating: aStageScore,
              bRating: bStageScore,
            },
            match: match,
            stage: stage,
          );

          changes[aRating]![aStageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: aStageScore);
          changes[bRating]![bStageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: bStageScore);

          changes[aRating]![aStageScore]!.ratingChange += update[aRating]!;
          changes[bRating]![bStageScore]!.ratingChange += update[bRating]!;
        }
      }
      else {
        var update = ratingSystem.updateShooterRatings(
          {
            aRating: aScore.total,
            bRating: bScore.total,
          },
          match: match,
        );

        changes[aRating]![aScore.total] ??= RatingEvent(eventName: "${match.name}", score: aScore.total, ratingChange: update[aRating]!);
        changes[bRating]![bScore.total] ??= RatingEvent(eventName: "${match.name}", score: bScore.total, ratingChange: update[bRating]!);
      }
    }
  }

  void _processOneshot(PracticalMatch match, Shooter shooter, List<RelativeMatchScore> scores, Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes) {
    if(!_verifyShooter(shooter)) {
      return;
    }

    String memNum = _processMemberNumber(shooter.memberNumber);

    _memberNumbersEncountered.add(memNum);

    ShooterRating rating = knownShooters[memNum]!;

    changes[rating] ??= {};

    RelativeMatchScore score = scores.firstWhere((score) => score.shooter == shooter);

    if(byStage) {
      for(Stage stage in match.stages) {
        RelativeScore stageScore = score.stageScores[stage]!;

        // Filter out badly marked classifier reshoots
        if(stageScore.score.hits == 0 && stageScore.score.time == 0) continue;

        var update = ratingSystem.updateShooterRatings(
          {
            rating: stageScore,
          },
          match: match,
          stage: stage,
        );

        changes[rating]![stageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: stageScore);

        changes[rating]![stageScore]!.ratingChange += update[rating]!;
      }
    }
    else {
      var update = ratingSystem.updateShooterRatings(
        {
          rating: score.total,
        },
        match: match,
      );

      changes[rating]![score.total] ??= RatingEvent(eventName: "${match.name}",
          score: score.total,
          ratingChange: update[rating]!);
    }
  }

  String _processMemberNumber(String no) {
    no = no.replaceAll(RegExp(r"[^0-9]"), "");
    return no;
  }
}