/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("MatchScoring");

/// Match scoring is how a list of absolute scores are converted to relative
/// scores, and then to overall match scores.
sealed class MatchScoring {
  /// Calculate match scores, given a list of shooters, and optionally a list of stages to limit to.
  Map<MatchEntry, RelativeMatchScore> calculateMatchScores({
    required ShootingMatch match,
    required List<MatchEntry> shooters,
    required List<MatchStage> stages,
    bool scoreDQ = true,
    MatchPredictionMode predictionMode = MatchPredictionMode.none,
    PreloadedRatingDataSource? ratings,
    DateTime? scoresAfter,
    DateTime? scoresBefore,
  });
}

/// In relative stage finish scoring, finish percentage on a stage scores
/// you a proportion of the stage's value: 95% finish on a 100-point stage
/// gets you 95 match points.
///
/// Stages in matches scored with RelativeStageFinishScoring must have
/// maxPoints, or else [fixedStageValue] must be set.
final class RelativeStageFinishScoring extends MatchScoring {
  /// If not null, all stages are worth this many match points, like in USPSA
  /// multigun: time plus yields a percentage stage finish, multiplied by
  /// fixedStageValue = 100 for match points.
  ///
  /// Otherwise, as USPSA scoring, where stages are worth their total point
  /// value.
  final int? fixedStageValue;

  /// If true, treat stages with 'points' scoring like USPSA fixed time stages.
  ///
  /// Percentages are relative to the winner, but stage points are the number
  /// of points scored.
  final bool pointsAreUSPSAFixedTime;

  RelativeStageFinishScoring({this.fixedStageValue, this.pointsAreUSPSAFixedTime = false});

  @override
  Map<MatchEntry, RelativeMatchScore> calculateMatchScores({
    required ShootingMatch match,
    required List<MatchEntry> shooters, 
    required List<MatchStage> stages,
    bool scoreDQ = true, 
    MatchPredictionMode predictionMode = MatchPredictionMode.none,
    PreloadedRatingDataSource? ratings,
    DateTime? scoresAfter,
    DateTime? scoresBefore,
  }) {
    if(shooters.length == 0 || stages.length == 0) return {};

    Map<MatchEntry, RelativeMatchScore> matchScores = {};
    Map<MatchEntry, Map<MatchStage, RelativeStageScore>> stageScores = {};

    // First, fill in the stageScores map with relative placements on each stage.
    for(var stage in stages) {
      StageScoring scoring = stage.scoring;
      if(scoring is IgnoredScoring) continue;

      if(stage.maxPoints == 0 && fixedStageValue == null) {
        _log.e("relative stage finish scoring requires stage max points or fixed stage value");
        throw ArgumentError("relative stage finish scoring requires stage max points or fixed stage value");
      }

      Map<MatchEntry, RawScore> scores = {};

      RawScore? bestScore = null;

      // Find the high score on the stage.
      for(var shooter in shooters) {
        var stageScore = shooter.scores[stage];

        bool isInTimeRange = _isInTimeRange(stageScore, scoresAfter: scoresAfter, scoresBefore: scoresBefore);

        if(stageScore == null || !isInTimeRange) {
          stageScore = RawScore(scoring: scoring, targetEvents: {});
        }

        scores[shooter] = stageScore;

        // A DNF/zero score doesn't count for best.
        if(stageScore.dnf) continue;

        if(bestScore == null || scoring.firstScoreBetter(stageScore, bestScore)) {
          bestScore = stageScore;
        }
      }

      if(bestScore == null) {
        // Nobody completed this stage, so set bestScore to avoid any /0
        bestScore = RawScore(scoring: scoring, targetEvents: {});
      }

      // How many match points the stage is worth.
      int stageValue = fixedStageValue ?? stage.maxPoints;

      // Sort the shooters by raw score on this stage, so we can assign places in one step.
      var sortedShooters = scores.keys.sorted((a, b) => scoring.compareScores(scores[b]!, scores[a]!));

      // Based on the high score, calculate ratios.
      for(int i = 0; i < sortedShooters.length; i++) {
        var shooter = sortedShooters[i];
        var score = scores[shooter]!;
        var ratio = max(0.0, scoring.ratio(score, bestScore));
        late double points;

        if(shooter.dq && !scoreDQ) {
          points = 0;
          ratio = 0;
        }
        else if(scoring is PointsScoring && pointsAreUSPSAFixedTime) {
          points = score.points.toDouble();
        }
        else {
          points = max(0.0, stageValue * ratio);
        }

        var relativeStageScore = RelativeStageScore(
          shooter: shooter,
          stage: stage,
          score: score,
          place: i + 1,
          ratio: ratio,
          points: points,
        );
        stageScores[shooter] ??= {};
        stageScores[shooter]![stage] = relativeStageScore;
      }
    }

    if(stageScores.isEmpty) {
      // Nobody completed any stages, so set all their stage scores to 0.
      for(var shooter in shooters) {
        for(var stage in stages) {
          var stageScore = shooter.scores[stage];
          if(stageScore == null) {
            // deleted shooters don't have scores, so generate a bunch of DNF scores
            // for them.
            // _log.w("Filling in empty score for ${shooter.getName()} on ${stage.toString()}");
            shooter.scores[stage] = RawScore(
              scoring: stage.scoring,
              targetEvents: {},
              modified: match.date.copyWith(hour: 0, minute: 0, second: 0),
            );
          }
          stageScores[shooter] ??= {};
          // stageScores[shooter]![stage] = RelativeStageScore(
          //   shooter: shooter,
          //   stage: stage,
          //   score: shooter.scores[stage]!,
          //   place: 0,
          //   ratio: 0,
          //   points: 0,
          // );
        }
      }
    }

    // Next, build match point totals for each shooter, summing the points available
    // per stage.
    Map<MatchEntry, double> stageScoreTotals = {};
    double bestTotalScore = 0;
    for(var s in shooters) {
      var shooterStageScores = stageScores[s];

      if(shooterStageScores == null) {
        throw StateError("shooter has no stage scores");
      }

      var totalScore = shooterStageScores.values.map((e) => e.points).sum;
      stageScoreTotals[s] = totalScore;
      if(totalScore > bestTotalScore) {
        bestTotalScore = totalScore;
      }
    }
    
    // Do predictions
    if(predictionMode != MatchPredictionMode.none) {
      // If we're doing Elo aware predictions, fetch some data.
      var locatedRatings = <ShooterRating>[];
      Map<ShooterRating, ShooterPrediction> predictions = {};
      ShooterPrediction? highPrediction;
      if(predictionMode.eloAware) {
        RatingSystem? r = null;
        for(var shooter in shooters) {
          var group = ratings!.groupForDivisionSync(shooter.division);
          if(group == null) continue;

          var rating = ratings.lookupRatingSync(group, shooter.memberNumber);
          if(predictionMode == MatchPredictionMode.eloAwarePartial) {
            var nonDnf = false;
            for(var score in shooter.scores.values) {
              if(score.scoring is IgnoredScoring) continue;
              if(!score.dnf) {
                nonDnf = true;
                break;
              }
            }
            if(!nonDnf) continue;
          }
          if(r == null) {
            r = ratings.getSettingsSync().algorithm;
          }
          if(rating != null) {
            locatedRatings.add(r.wrapDbRating(rating));
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

      for(var shooter in shooters) {
        // Do match predictions for shooters who have completed at least one stage.
        if((stageScores[shooter]?.length ?? 0) > 0 || predictionMode == MatchPredictionMode.eloAwareFull) {
          double averageStagePercentage = 0.0;
          int stagesCompleted = 0;

          for(MatchStage stage in stages) {
            if(stage.scoring is IgnoredScoring) continue;

            var stageScore = stageScores[shooter]?[stage];
            if(stageScore != null && !stageScore.score.dnf && _isInTimeRange(stageScore.score, scoresAfter: scoresAfter, scoresBefore: scoresBefore)) {
              averageStagePercentage += stageScore.ratio;
              stagesCompleted += 1;
            }
          }
          if(stagesCompleted > 0) {
            averageStagePercentage = averageStagePercentage / stagesCompleted;
          }
        

          // If they're already done, there's nothing to predict.
          if(stagesCompleted >= stages.length) continue;

          // If they've completed zero stages, high available is
          // meaningless (it's just 100%), and average stage finish
          // is also meaningless (it's just 0%), so skip them.
          if(stagesCompleted == 0) continue;

          // Average stage finish with only one stage completed means a bunch of people will have 100%
          // predicted scores at the very start of a day, so at least wait until they have two scores
          // and a slightly better chance of dropping some points somewhere, or overlapping with another
          // high-quality shooter.
          if(predictionMode == MatchPredictionMode.averageStageFinish && stagesCompleted < 2) continue;

          for (MatchStage stage in stages) {
            if(stage.scoring is IgnoredScoring) continue;
            var stageScore = shooter.scores[stage];

            if (stageScore == null || stageScore.dnf || !_isInTimeRange(stageScore, scoresAfter: scoresAfter, scoresBefore: scoresBefore)) {
              if (predictionMode == MatchPredictionMode.highAvailable) {
                stageScoreTotals.incrementBy(shooter, stage.maxPoints.toDouble());
              }
              else if (predictionMode == MatchPredictionMode.averageStageFinish) {
                stageScoreTotals.incrementBy(shooter, stage.maxPoints * averageStagePercentage);
              }
              else if (predictionMode == MatchPredictionMode.averageHistoricalFinish) {
                var group = ratings!.groupForDivisionSync(shooter.division);
                if(group != null) {
                  var rating = ratings.lookupRatingSync(group, shooter.memberNumber);
                  if (rating != null) {
                    stageScoreTotals.incrementBy(shooter, stage.maxPoints * rating.averageFinishRatio(offset: stagesCompleted));
                  }
                  else {
                    // Use average stage percentage if we don't have a match history for this shooter
                    stageScoreTotals.incrementBy(shooter, stage.maxPoints * averageStagePercentage);
                  }
                }
              }
              else if (predictionMode.eloAware) {
                var group = ratings!.groupForDivisionSync(shooter.division);
                if(group != null) {
                  var rating = ratings.lookupRatingSync(group, shooter.memberNumber);
                  var prediction = predictions[rating];
                  if (prediction != null && highPrediction != null) {
                    // TODO: distribute this according to a Gumbel or normal cumulative distribution function
                    var percent = 0.3 + ((prediction.mean + prediction.shift / 2) / (highPrediction.halfHighPrediction + highPrediction.shift / 2) * 0.7);
                    stageScoreTotals.incrementBy(shooter, stage.maxPoints * percent);
                  }
                  else {
                    // Use average stage percentage
                    stageScoreTotals.incrementBy(shooter, stage.maxPoints * averageStagePercentage);
                  }
                }
              }
            }
          }
        }

        if(stageScoreTotals[shooter]! > bestTotalScore) {
          bestTotalScore = stageScoreTotals[shooter]!;
        }
      }
    }

    // Sort the shooters by stage score totals and create relative match scores.
    var sortedShooters = shooters.sorted((a, b) => stageScoreTotals[b]!.compareTo(stageScoreTotals[a]!));
    for(int i = 0; i < sortedShooters.length; i++) {
      var shooter = sortedShooters[i];
      var shooterStageScores = stageScores[shooter]!;
      var totalScore = stageScoreTotals[shooter]!;

      matchScores[shooter] = RelativeMatchScore(
        shooter: shooter,
        stageScores: shooterStageScores,
        place: i + 1,
        ratio: bestTotalScore == 0 ? 0 : totalScore / bestTotalScore,
        points: totalScore,
      );
    }

    return matchScores;
  }
}

/// In cumulative scoring, the scores from each stage are tallied up, and
/// the sums are compared directly.
///
/// In something like Bianchi Cup, points are tallied and the highest
/// wins. In something like IDPA, times are tallied and the lowest wins.
final class CumulativeScoring extends MatchScoring {
  /// True if a higher cumulative score is better than a lower one.
  ///
  /// Time-plus sports will set this to false. Other sports will set it
  /// to true.
  bool highScoreWins;
  bool get lowScoreWins => !highScoreWins;

  CumulativeScoring({this.highScoreWins = true});

  Map<MatchEntry, RelativeMatchScore> calculateMatchScores({
    required ShootingMatch match,
    required List<MatchEntry> shooters,
    required List<MatchStage> stages,
    bool scoreDQ = true,
    MatchPredictionMode predictionMode = MatchPredictionMode.none,
    PreloadedRatingDataSource? ratings,
    DateTime? scoresAfter,
    DateTime? scoresBefore,
  }) {
    if(shooters.length == 0 || stages.length == 0) return {};

    Map<MatchEntry, RelativeMatchScore> matchScores = {};
    Map<MatchEntry, Map<MatchStage, RelativeStageScore>> stageScores = {};

    // hasDNF indicates when a shooter should be sorted to the bottom of the scores, either
    // because of a DQ or a lowScoreWins stage DNF.
    Set<MatchEntry> matchDNF = {};

    for(var stage in stages) {
      StageScoring scoring = stage.scoring;

      if(scoring is IgnoredScoring) continue;

      Set<MatchEntry> stageDNF = {};
      Map<MatchEntry, RawScore> scores = {};

      RawScore? bestScore = null;

      // Find the high score on the stage.
      for(var shooter in shooters) {
        var stageScore = shooter.scores[stage];

        bool isInTimeRange = _isInTimeRange(stageScore, scoresAfter: scoresAfter, scoresBefore: scoresBefore);

        if(stageScore == null || !isInTimeRange) {
          stageScore = RawScore(scoring: scoring, targetEvents: {});
        }

        scores[shooter] = stageScore;

        // Score DQ/DNF logic is complicated for cumulative matches.
        // If a lowScoreWins shooter DNFs a stage, they cannot have a
        // match score—they'd have a 0 where everyone else has an N, so
        // they would finish ahead of people they 'lost to' by DNFing.
        // If a highScoreWins shooter DNFs a stage, that's fine. They get
        // a 0, and finish behind anyone who got points.
        // If a shooter in either cumulative mode DQs, and scoreDQ is off,
        // they get added to the DNF lists and sort to the end of all stages
        // and the match score. If scoreDQ is on (and a lowScoreWins shooter
        // did not DNF this stage), they count for this stage.
        // A lowScoreWins shooter will be added to the match DNF list if they
        // DNF any stage for any reason, or if they DQ and scoreDQ is off. A
        // highScoreWins shooter will only be added to the match DNF list if
        // score DQ is off.
        if((stageScore.dnf && lowScoreWins) || (!scoreDQ && shooter.dq)) {
          stageDNF.add(shooter);
          matchDNF.add(shooter);
          continue;
        }

        if(bestScore == null || scoring.firstScoreBetter(stageScore, bestScore)) {
          bestScore = stageScore;
        }
      }

      if(bestScore == null) {
        // Nobody completed this stage, so move on to the next one
        bestScore = RawScore(scoring: scoring, targetEvents: {});
        continue;
      }

      // Sort the shooters by raw score on this stage, so we can assign places in one step.
      var sortedShooters = scores.keys.sorted((a, b) {
        // If both are DNF/DQ, sort equally.
        if(stageDNF.contains(a) && stageDNF.contains(b)) return a.lastName.compareTo(b.lastName);
        // If A is DNF and B is not DNF, A sorts after B, and vice versa.
        else if(stageDNF.contains(a) && !stageDNF.contains(b)) return 1;
        else if(!stageDNF.contains(a) && stageDNF.contains(b)) return -1;
        // If neither A nor B is DNF, sort by descending order of finish.
        return scoring.compareScores(scores[b]!, scores[a]!);
      });

      // Based on the high score, calculate ratios.
      // In the event that a shooter is DNF on this stage, their points will be 0, and they'll be
      // sorted to the end because of the sort in sortedShooters.
      for(int i = 0; i < sortedShooters.length; i++) {
        var shooter = sortedShooters[i];
        var score = scores[shooter]!;

        // Ratio is 0.0 for lowScoreWins stageDNF shooters. Points is 0 because of DNF.
        var ratio = scoring.ratio(score, bestScore);
        if(lowScoreWins && stageDNF.contains(shooter)) ratio = 0.0;

        var points = scoring.interpret(score);
        var relativeStageScore = RelativeStageScore(
          shooter: shooter,
          stage: stage,
          score: score,
          place: i + 1,
          ratio: ratio,
          points: points.toDouble(),
        );
        stageScores[shooter] ??= {};
        stageScores[shooter]![stage] = relativeStageScore;
      }
    }

    if(stageScores.isEmpty) {
      // Nobody completed any stages, so set all their stage scores to 0.
      for(var shooter in shooters) {
        for(var stage in stages) {
          var stageScore = shooter.scores[stage];
          if(stageScore == null) {
            // deleted shooters don't have scores, so generate a bunch of DNF scores
            // for them.
            // _log.w("Filling in empty score for ${shooter.getName()} on ${stage.toString()}");
            shooter.scores[stage] = RawScore(
              scoring: stage.scoring,
              targetEvents: {},
              modified: match.date.copyWith(hour: 0, minute: 0, second: 0),
            );
          }
          stageScores[shooter] ??= {};
          // stageScores[shooter]![stage] = RelativeStageScore(
          //   shooter: shooter,
          //   stage: stage,
          //   score: shooter.scores[stage]!,
          //   place: 0,
          //   ratio: 0,
          //   points: 0,
          // );
        }
      }
    }

    // Next, build match point totals for each shooter, summing the points available
    // per stage.
    Map<MatchEntry, double> stageScoreTotals = {};
    double bestTotalScore = highScoreWins ? 0 : double.maxFinite;
    for(var s in shooters) {
      var shooterStageScores = stageScores[s];

      if(shooterStageScores == null) {
        throw StateError("shooter has no stage scores");
      }

      var totalScore = shooterStageScores.values.map((e) => e.points!).sum;
      stageScoreTotals[s] = totalScore;
      if(lowScoreWins) {
        // Match DNFs can't be the best total score.
        if(totalScore < bestTotalScore && !matchDNF.contains(s)) {
          bestTotalScore = totalScore;
        }
      }
      else {
        if (totalScore > bestTotalScore) {
          bestTotalScore = totalScore;
        }
      }
    }

    // Sort the shooters by stage score totals.
    // People on the match DNF list get sorted to the end of the list.
    late List<MatchEntry> sortedShooters;
    if(lowScoreWins) {
      sortedShooters = shooters.sorted((a, b) {
        // If both are DNF/DQ, sort equally.
        if(matchDNF.contains(a) && matchDNF.contains(b)) return a.lastName.compareTo(b.lastName);
        // If A is DNF and B is not DNF, A sorts after B, and vice versa.
        else if(matchDNF.contains(a) && !matchDNF.contains(b)) return 1;
        else if(!matchDNF.contains(a) && matchDNF.contains(b)) return -1;

        return stageScoreTotals[a]!.compareTo(stageScoreTotals[b]!);
      });
    }
    else {
      sortedShooters = shooters.sorted((a, b) {
        // If both are DNF/DQ, sort equally.
        if(matchDNF.contains(a) && matchDNF.contains(b)) return a.lastName.compareTo(b.lastName);
        // If A is DNF and B is not DNF, A sorts after B, and vice versa.
        else if(matchDNF.contains(a) && !matchDNF.contains(b)) return 1;
        else if(!matchDNF.contains(a) && matchDNF.contains(b)) return -1;

        return stageScoreTotals[b]!.compareTo(stageScoreTotals[a]!);
      });
    }

    for(int i = 0; i < sortedShooters.length; i++) {
      var shooter = sortedShooters[i];
      var shooterStageScores = stageScores[shooter]!;
      var totalScore = stageScoreTotals[shooter]!;

      // In lowScoreWins mode, if someone is on the match DNF list, we can't
      // give them a valid score, so their total score becomes 0, as does their
      // ratio.
      if(lowScoreWins && matchDNF.contains(shooter)) {
        totalScore = 0.0;
      }

      var ratio = 0.0;
      if(lowScoreWins) {
        if(totalScore != 0.0) {
          ratio = bestTotalScore / totalScore;
        }
      }
      else {
        ratio = totalScore / bestTotalScore;
      }

      matchScores[shooter] = RelativeMatchScore(
        shooter: shooter,
        stageScores: shooterStageScores,
        place: i + 1,
        ratio: ratio,
        points: totalScore,
      );
    }

    return matchScores;
  }
}


bool _isInTimeRange(RawScore? score, {DateTime? scoresAfter, DateTime? scoresBefore}) {
  if(score == null) return true;

  if(scoresAfter != null && score.modified != null && score.modified!.isBefore(scoresAfter)) {
    return false;
  }
  if(scoresBefore != null && score.modified != null && score.modified!.isAfter(scoresBefore)) {
    return false;
  }
  return true;
}