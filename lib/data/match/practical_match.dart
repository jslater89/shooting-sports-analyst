/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/score_list.dart';

var _log = SSALogger("OldMatch");

enum MatchLevel {
  I,
  II,
  III,
  IV,
}

class OldFilterSet {
  FilterMode mode = FilterMode.and;
  bool reentries = true;
  bool scoreDQs = true;
  bool femaleOnly = false;

  late Map<Division, bool> divisions;
  late Map<Classification, bool> classifications;
  late Map<PowerFactor, bool> powerFactors;

  OldFilterSet({bool empty = false}) {
    divisions = {};
    classifications = {};
    powerFactors = {};

    for (Division d in Division.values) {
      divisions[d] = !empty;
    }

    for (Classification c in Classification.values) {
      classifications[c] = !empty;
    }

    for (PowerFactor f in PowerFactor.values) {
      powerFactors[f] = !empty;
    }
  }

  Iterable<Division> get activeDivisions => divisions.keys.where((div) => divisions[div] ?? false);

  Map<Division, bool> divisionListToMap(List<Division> divisions) {
    Map<Division, bool> map = {};
    for(var d in Division.values) {
      map[d] = divisions.contains(d);
    }

    return map;
  }
}

class PracticalMatch {
  String? name;
  String? rawDate;
  DateTime? date;
  MatchLevel? level;

  late String practiscoreId;
  String? practiscoreIdShort;
  late String reportContents;

  List<Shooter> shooters = [];
  List<Stage> stages = [];

  int? maxPoints;
  int stageScoreCount = 0;

  /// Whether a match is in progress for ratings purposes.
  bool get inProgress => practiscoreId == "12d1cd35-3556-44db-af09-5153f975c447";

  PracticalMatch copy() {
    var newMatch = PracticalMatch()
      ..practiscoreId = practiscoreId
      ..practiscoreIdShort = practiscoreIdShort
      ..name = name
      ..rawDate = rawDate
      ..date = date
      ..level = level
      ..shooters = []
      ..stages = []
      ..maxPoints = maxPoints
      ..reportContents = reportContents;

    newMatch.stages.addAll(stages.map((s) => s.copy()));
    newMatch.shooters.addAll(shooters.map((s) => s.copy(newMatch)));

    return newMatch;
  }

  /// Looks up a stage  by name.
  Stage? lookupStage(Stage stage) {
    for(Stage s in stages) {
      if(stage.name == s.name) return s;
    }

    return null;
  }

  /// Filters shooters by division, power factor, and classification.
  ///
  /// By default, uses [FilterMode.and], and allows all values. To filter
  /// by e.g. division alone, set [divisions] to the desired division(s).
  List<Shooter> filterShooters({
    FilterMode? filterMode,
    bool allowReentries = true,
    List<Division> divisions = Division.values,
    List<PowerFactor> powerFactors = PowerFactor.values,
    List<Classification> classes = Classification.values,
    bool ladyOnly = false,
  }) {
    List<Shooter> filteredShooters = [];

    for(Shooter s in shooters) {
      if(filterMode == FilterMode.or) {
        if (divisions.contains(s.division) || powerFactors.contains(s.powerFactor) || classes.contains(s.classification)) {
          if(allowReentries || !s.reentry) filteredShooters.add(s);
        }
      }
      else {
        if (divisions.contains(s.division) && powerFactors.contains(s.powerFactor) && classes.contains(s.classification)) {
          if(allowReentries || !s.reentry) filteredShooters.add(s);
        }
      }
    }

    if(ladyOnly) {
      filteredShooters.retainWhere((s) => s.female);
    }

    return filteredShooters;
  }

  /// Returns one relative score for each shooter provided, representing performance
  /// in a hypothetical match made up of the given shooters and stages.
  List<RelativeMatchScore> getScores({
    List<Shooter>? shooters,
    List<Stage>? stages,
    bool scoreDQ = true,
    MatchPredictionMode predictionMode = MatchPredictionMode.none,
    Map<RaterGroup, Rater>? ratings,
  }) {
    if(ratings == null && !MatchPredictionMode.dropdownValues(false).contains(predictionMode)) {
      throw ArgumentError("must provide ratings when asking for a ratings-aware prediction mode");
    }

    List<Shooter> innerShooters = shooters != null ? shooters : this.shooters;
    List<Stage> innerStages = stages != null ? stages : this.stages;

    if(innerShooters.length == 0 || innerStages.length == 0) return [];

    int matchMaxPoints = innerStages.map<int>((e) => e.maxPoints).reduce((a, b) => a + b);
    // _log.v("Max points for match: $matchMaxPoints");

    // Create a total score for each shooter, precalculating what we can and
    // prepopulating what we can't.
    Map<Shooter, RelativeMatchScore> matchScores = {};
    for(Shooter shooter in innerShooters) {
      int shooterTotalPoints = 0;

      matchScores[shooter] = RelativeMatchScore(shooter: shooter);
      matchScores[shooter]!.shooter = shooter;
      matchScores[shooter]!.total = RelativeScore();
      matchScores[shooter]!.total.score = Score(shooter: shooter);
      for(Stage stage in innerStages) {
        if(shooter.stageScores[stage] == null) continue;
        shooterTotalPoints += shooter.stageScores[stage]!.getTotalPoints(scoreDQ: scoreDQ);
        matchScores[shooter]!.stageScores[stage] = RelativeScore()
          ..score = shooter.stageScores[stage]!
          ..stage = stage;
      }

      for(Stage stage in innerStages) {
        if(shooter.stageScores[stage] == null) continue;
        matchScores[shooter]!.total.score.time += shooter.stageScores[stage]!.time;
        matchScores[shooter]!.total.score.a += shooter.stageScores[stage]!.a;
        matchScores[shooter]!.total.score.b += shooter.stageScores[stage]!.b;
        matchScores[shooter]!.total.score.c += shooter.stageScores[stage]!.c;
        matchScores[shooter]!.total.score.d += shooter.stageScores[stage]!.d;
        matchScores[shooter]!.total.score.m += shooter.stageScores[stage]!.m;
        matchScores[shooter]!.total.score.ns += shooter.stageScores[stage]!.ns;
        matchScores[shooter]!.total.score.npm += shooter.stageScores[stage]!.npm;
        matchScores[shooter]!.total.score.extraHit += shooter.stageScores[stage]!.extraHit;
        matchScores[shooter]!.total.score.extraShot += shooter.stageScores[stage]!.extraShot;
        matchScores[shooter]!.total.score.lateShot += shooter.stageScores[stage]!.lateShot;
        matchScores[shooter]!.total.score.procedural += shooter.stageScores[stage]!.procedural;
        matchScores[shooter]!.total.score.otherPenalty += shooter.stageScores[stage]!.otherPenalty;
      }

      matchScores[shooter]!.percentTotalPoints = shooterTotalPoints.toDouble() / matchMaxPoints.toDouble();
      //_log.v("${shooter.firstName} ${shooter.lastName} shot ${totalScores[shooter].percentTotalPoints} total points");
    }


    // First, for each stage, sort by HF. Then, calculate stage percentages.
    for(Stage stage in innerStages) {
      // Sort high to low
      innerShooters.sort((Shooter a, Shooter b) {
        if(a.stageScores[stage] == null && b.stageScores[stage] == null) return 0;
        if(a.stageScores[stage] == null && b.stageScores[stage] != null) return -1;
        if(b.stageScores[stage] == null && a.stageScores[stage] != null) {
          return 1;
        }

        return b.stageScores[stage]!.getHitFactor(scoreDQ: scoreDQ).compareTo(a.stageScores[stage]!.getHitFactor(scoreDQ: scoreDQ));
      });

      if(innerShooters[0].stageScores[stage] == null) {
        // we've clearly hit some awful condition here, so let's
        // just bail out
        _log.e("Winner of ${stage.name}: ${innerShooters[0].firstName} ${innerShooters[0].lastName} has null score");
        continue;
      }
      double highHitFactor = innerShooters[0].stageScores[stage]!.getHitFactor(scoreDQ: scoreDQ);
      //_log.v("Winner of ${stage.name}: ${shooters[0].firstName} ${shooters[0].lastName} with ${shooters[0].stageScores[stage].hitFactor}");

      int place = 1;
      for(Shooter shooter in innerShooters) {
        double hitFactor = shooter.stageScores[stage]!.getHitFactor(scoreDQ: scoreDQ);
        double percent = hitFactor / highHitFactor;
        if(percent.isNaN) percent = 0;

        double relativePoints;
        if(stage.type == Scoring.fixedTime) {
          relativePoints = shooter.stageScores[stage]!.getTotalPoints(scoreDQ: scoreDQ).toDouble();
        }
        else {
          relativePoints = stage.maxPoints * percent;
        }

        matchScores[shooter]!.stageScores[stage]!
          ..percent = percent
          ..relativePoints = relativePoints
          ..place = place++;
      }
    }

    if(predictionMode != MatchPredictionMode.none) {
      var locatedRatings = <ShooterRating>[];
      Map<ShooterRating, ShooterPrediction> predictions = {};
      ShooterPrediction? highPrediction;
      if(predictionMode.eloAware) {
        RatingSystem? r = null;
        for(var shooter in innerShooters) {
          var rating = ratings!.lookup(shooter);
          if(r == null) {
            r = ratings.lookupOldRater(shooter)?.ratingSystem;
            if(r == null) {
              break;
            }
          }
          if(rating != null) {
            locatedRatings.add(rating);
          }
        }

        if(r != null && r.supportsPrediction) {
          var preds = r.predict(locatedRatings);
          preds.sort((a, b) => b.mean.compareTo(a.mean));
          highPrediction = preds.first;
          for(var pred in preds) {
            predictions[pred.shooter] = pred;
          }
        }
      }

      for(var shooter in innerShooters) {
        // Do match predictions for shooters who have completed at least one stage.
        if(matchScores[shooter]!.total.score.rawPoints != 0 || predictionMode == MatchPredictionMode.eloAwareFull) {
          double averageStagePercentage = 0.0;
          int stagesCompleted = 0;

          if(predictionMode == MatchPredictionMode.averageStageFinish
              || predictionMode == MatchPredictionMode.averageHistoricalFinish
              || predictionMode.eloAware
          ) {
            for(Stage stage in innerStages) {
              if(stage.type == Scoring.chrono) continue;

              var stageScore = shooter.stageScores[stage];
              if(stageScore != null && !stageScore.isDnf) {
                averageStagePercentage += matchScores[shooter]!.stageScores[stage]!.percent;
                stagesCompleted += 1;
              }
            }
            if(stagesCompleted > 0) {
              averageStagePercentage = averageStagePercentage / stagesCompleted;
            }
          }

          if(stagesCompleted >= innerStages.length) continue;

          for (Stage stage in innerStages) {
            if(stage.type == Scoring.chrono) continue;

            if (shooter.stageScores[stage] == null || shooter.stageScores[stage]!.isDnf) {
              if (predictionMode == MatchPredictionMode.highAvailable) {
                matchScores[shooter]!.total.relativePoints += stage.maxPoints;
              }
              else if (predictionMode == MatchPredictionMode.averageStageFinish) {
                matchScores[shooter]!.total.relativePoints += stage.maxPoints * averageStagePercentage;
              }
              else if (predictionMode == MatchPredictionMode.averageHistoricalFinish) {
                var rating = ratings!.lookup(shooter);
                if(rating != null) {
                  matchScores[shooter]!.total.relativePoints += stage.maxPoints * rating.averagePercentFinishes(offset: stagesCompleted);
                }
                else {
                  // Use average stage percentage if we don't have a match history for this shooter
                  matchScores[shooter]!.total.relativePoints += stage.maxPoints * averageStagePercentage;
                }
              }
              else if (predictionMode.eloAware) {
                var rating = ratings!.lookup(shooter);
                var prediction = predictions[rating];
                if(prediction != null && highPrediction != null) {
                  var percent = 0.3 + ((prediction.mean + prediction.shift / 2) / (highPrediction.halfHighPrediction + highPrediction.shift / 2) * 0.7);
                  matchScores[shooter]!.total.relativePoints += stage.maxPoints * percent;
                }
                else {
                  // Use average stage percentage
                  matchScores[shooter]!.total.relativePoints += stage.maxPoints * averageStagePercentage;
                }
              }
            }
          }
        }
      }
    }

    // Next, for each shooter, add relative points for all stages and sort by relative points. Then,
    // calculate percentages for each shooter.
    for(Shooter shooter in innerShooters) {
      for(Stage stage in innerStages) {
        matchScores[shooter]!.total.relativePoints += matchScores[shooter]!.stageScores[stage]?.relativePoints ?? 0;
      }
    }

    // Sort the scores.
    List<RelativeMatchScore> finalScores = matchScores.values.toList();
    finalScores.sortByScore();
    double highScore = finalScores[0].total.relativePoints;

    int place = 1;
    for(RelativeMatchScore score in finalScores) {
      score.total.percent = score.total.relativePoints / highScore;
      score.total.place = place++;
    }

    return finalScores;
  }

  @override
  String toString() {
    return name ?? "unnamed match";
  }

  static int Function(PracticalMatch a, PracticalMatch b) dateComparator = (a, b) {
    // Sort remaining matches by date descending, then by name ascending
    var dateSort = b.date!.compareTo(a.date!);
    if (dateSort != 0) return dateSort;

    return a.name!.compareTo(b.name!);
  };

}

class Stage {
  String name;
  int internalId;
  int minRounds = 0;
  int maxPoints = 0;
  bool classifier;
  String classifierNumber;
  Scoring type;

  Stage({
    required this.name,
    required this.internalId,
    required this.minRounds,
    required this.maxPoints,
    required this.classifier,
    required this.classifierNumber,
    required this.type,
  });

  Stage copy() {
    return Stage(
      internalId: internalId,
      name: name,
      minRounds: minRounds,
      maxPoints: maxPoints,
      classifier: classifier,
      classifierNumber: classifierNumber,
      type: type,
    );
  }

  @override
  String toString() {
    return name;
  }

// @override
// bool operator ==(Object other) {
//   if(!(other is Stage)) return false;
//   return this.name == other.name;
// }
//
// bool exactEquals(Object other) {
//   return other == this;
// }
//
// @override
// int get hashCode => this.name.hashCode;
}