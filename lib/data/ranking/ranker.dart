import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';

class Ranker {
  List<PracticalMatch> _matches;
  Map<String, ShooterRating> knownShooters = {};
  Set<String> _memberNumbersEncountered = Set<String>();
  RatingSystem ratingSystem;
  FilterSet? _filters;
  bool byStage;

  Ranker({required List<PracticalMatch> matches, required this.ratingSystem, FilterSet? filters, this.byStage = false}) : this._matches = matches, this._filters = filters {
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
      for(int j = i + 1; j < shooters.length; j++) {
        Shooter a = shooters[i];
        Shooter b = shooters[j];

        // No non-members (can't uniquely ID them)
        if(a.memberNumber.isEmpty || b.memberNumber.isEmpty) continue;

        // Sorry, L1-L99
        if(a.memberNumber.length <= 3 || b.memberNumber.length <= 3) continue;

        // Ignore DQs
        if(a.dq || b.dq) continue;

        // Ignore second guns
        if(a.reentry || b.reentry) continue;

        String memNumA = _processMemberNumber(a.memberNumber);
        String memNumB = _processMemberNumber(b.memberNumber);

        // unmarked reentries
        if(memNumA == memNumB) continue;
        if(a.firstName.endsWith("2") || a.lastName.endsWith("2") || b.firstName.endsWith("2") || b.lastName.endsWith("2")) continue;
        if(a.firstName.endsWith("3") || a.lastName.endsWith("3") || b.firstName.endsWith("3") || b.lastName.endsWith("3")) continue;

        if(knownShooters[memNumA] == null) {
          debugPrint("Unknown shooter ${a.getName()} ${a.memberNumber}");
          continue;
        }
        if(knownShooters[memNumB] == null) {
          debugPrint("Unknown shooter ${b.getName()} ${b.memberNumber}");
          continue;
        }

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

            var update = ratingSystem.updateShooterRatings({
              aRating: aStageScore,
              bRating: bStageScore,
            });

            changes[aRating]![aStageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: aStageScore);
            changes[bRating]![bStageScore] ??= RatingEvent(eventName: "${match.name} - ${stage.name}", score: bStageScore);

            changes[aRating]![aStageScore]!.ratingChange += update[aRating]!;
            changes[bRating]![bStageScore]!.ratingChange += update[bRating]!;
          }
        }
        else {
          var update = ratingSystem.updateShooterRatings({
            aRating: aScore.total,
            bRating: bScore.total,
          });
          changes[aRating]![aScore.total] ??= RatingEvent(eventName: "${match.name}", score: aScore.total, ratingChange: update[aRating]!);
          changes[bRating]![bScore.total] ??= RatingEvent(eventName: "${match.name}", score: bScore.total, ratingChange: update[bRating]!);
        }
      }
    }

    for(var r in changes.keys) {
      for(var event in changes[r]!.values) {
        r.ratingEvents.add(event);
      }
    }
  }

  String _processMemberNumber(String no) {
    no = no.replaceAll(RegExp(r"[^0-9]"), "");
    return no;
  }
}

class ShooterRating {
  final Shooter shooter;
  double rating;

  List<RatingEvent> ratingEvents = [];

  ShooterRating(this.shooter, this.rating);
}

class RatingEvent {
  String eventName;
  RelativeScore score;
  double ratingChange;

  RatingEvent({required this.eventName, required this.score, this.ratingChange = 0});
}

abstract class RatingSystem {
  double get defaultRating;

  /// Given two shooters, their current ratings, and a match score for each of them,
  /// mutate their ratings and return a map of ratings to the change in each rating.
  Map<ShooterRating, double> updateShooterRatings(Map<ShooterRating, RelativeScore> scores);
}