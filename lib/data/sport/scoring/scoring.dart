/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/match/practical_match.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/score_list.dart';
import 'package:shooting_sports_analyst/util.dart';

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
    Map<DbRatingGroup, Rater>? ratings,
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
    Map<DbRatingGroup, Rater>? ratings,
  }) {
    if(shooters.length == 0 || stages.length == 0) return {};

    Map<MatchEntry, RelativeMatchScore> matchScores = {};
    Map<MatchEntry, Map<MatchStage, RelativeStageScore>> stageScores = {};

    // First, fill in the stageScores map with relative placements on each stage.
    for(var stage in stages) {
      StageScoring scoring = stage.scoring;
      if(scoring is IgnoredScoring) continue;

      if(stage.maxPoints == 0 && fixedStageValue == null) {
        throw ArgumentError("relative stage finish scoring requires stage max points or fixed stage value");
      }

      Map<MatchEntry, RawScore> scores = {};

      RawScore? bestScore = null;

      // Find the high score on the stage.
      for(var shooter in shooters) {
        var stageScore = shooter.scores[stage];

        if(stageScore == null) {
          stageScore = RawScore(scoring: scoring, targetEvents: {});
          shooter.scores[stage] = stageScore;
        }

        scores[shooter] = stageScore;

        // A DNF/zero score doesn't count for best.
        if(stageScore.dnf) continue;

        if(bestScore == null || scoring.firstScoreBetter(stageScore, bestScore)) {
          bestScore = stageScore;
        }
      }

      if(bestScore == null) {
        // Nobody completed this stage, so move on to the next one
        continue;
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
          var rating = ratings!.lookupNew(match, shooter);
          if(r == null) {
            r = ratings.lookupRater(match, shooter)?.ratingSystem;
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

      for(var shooter in shooters) {
        // Do match predictions for shooters who have completed at least one stage.
        if(shooter.firstName == "Matthew" && shooter.lastName == "Hemple") {
          print("break");
        }
        if((stageScores[shooter]?.length ?? 0) > 0 || predictionMode == MatchPredictionMode.eloAwareFull) {
          double averageStagePercentage = 0.0;
          int stagesCompleted = 0;

          if(predictionMode == MatchPredictionMode.averageStageFinish
              || predictionMode == MatchPredictionMode.averageHistoricalFinish
              || predictionMode.eloAware
          ) {
            for(MatchStage stage in stages) {
              if(stage.scoring is IgnoredScoring) continue;

              var stageScore = stageScores[shooter]?[stage];
              if(stageScore != null && !stageScore.score.dnf) {
                averageStagePercentage += stageScore.ratio;
                stagesCompleted += 1;
              }
            }
            if(stagesCompleted > 0) {
              averageStagePercentage = averageStagePercentage / stagesCompleted;
            }
          }

          if(stagesCompleted >= stages.length) continue;

          for (MatchStage stage in stages) {
            if(stage.scoring is IgnoredScoring) continue;

            if (shooter.scores[stage] == null || shooter.scores[stage]!.dnf) {
              if (predictionMode == MatchPredictionMode.highAvailable) {
                stageScoreTotals.incrementBy(shooter, stage.maxPoints.toDouble());
              }
              else if (predictionMode == MatchPredictionMode.averageStageFinish) {
                stageScoreTotals.incrementBy(shooter, stage.maxPoints * averageStagePercentage);
              }
              else if (predictionMode == MatchPredictionMode.averageHistoricalFinish) {
                var rating = ratings!.lookupNew(match, shooter);
                if(rating != null) {
                  stageScoreTotals.incrementBy(shooter, stage.maxPoints * rating.averagePercentFinishes(offset: stagesCompleted));
                }
                else {
                  // Use average stage percentage if we don't have a match history for this shooter
                  stageScoreTotals.incrementBy(shooter, stage.maxPoints * averageStagePercentage);
                }
              }
              else if (predictionMode.eloAware) {
                var rating = ratings!.lookupNew(match, shooter);
                var prediction = predictions[rating];
                if(prediction != null && highPrediction != null) {
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
        ratio: totalScore / bestTotalScore,
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
    Map<DbRatingGroup, Rater>? ratings,
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

        if(stageScore == null) {
          stageScore = RawScore(scoring: scoring, targetEvents: {});
          shooter.scores[stage] = stageScore;
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

sealed class StageScoring {
  /// Provide a comparative value for a raw score, using this scoring system.
  num interpret(RawScore score);

  /// If true, better scores in this scoring system are higher numeric values,
  /// and lower scores are worse.
  ///
  /// The opposite is true when false.
  bool get highScoreBest;

  /// The opposite of [highScoreBest].
  bool get lowScoreBest => !highScoreBest;

  String get dbString => this.runtimeType.toString();

  /// A label to use in the UI adjacent to a score value.
  String displayLabel(RawScore score) {
    switch(this) {
      case HitFactorScoring():
        return "Hit Factor";
      case TimePlusScoring():
        return "Time";
      case PointsScoring():
        return "Points";
      case IgnoredScoring():
        return "-";
    }
  }

  /// A displayable string interpreting this score.
  String displayString(RawScore score) {
    switch(this) {
      case HitFactorScoring():
        return "${interpret(score).toStringAsFixed(4)}HF";
      case TimePlusScoring():
        return "${interpret(score).toStringAsFixed(2)}s";
      case PointsScoring(allowDecimal: var allowDecimal):
        if(allowDecimal) {
          return "${interpret(score).toStringAsFixed(2)}pt";
        }
        else {
          return "${interpret(score).round()}pt";
        }
      case IgnoredScoring():
        return "-";
    }
  }

  /// Returns >0 if a is better than b, 0 if they are equal, and <0 is b is better than a.
  int compareScores(RawScore a, RawScore b) {
    var aInt = interpret(a);
    var bInt = interpret(b);
    if(highScoreBest) {
      if (aInt > bInt) return 1;
      if (aInt < bInt) return -1;
      return 0;
    }
    else {
      if (aInt < bInt) return 1;
      if (aInt > bInt) return -1;
      return 0;
    }
  }

  /// Returns true if a is better than b.
  bool firstScoreBetter(RawScore a, RawScore b) {
    return compareScores(a, b) > 0;
  }

  /// Returns the ratio of [score] to [comparedTo].
  ///
  /// If score is 95 and comparedTo is 100, this will return
  /// 0.95 for a highScoreBest scoring.
  double ratio(RawScore score, RawScore comparedTo) {
    var result = 0.0;
    if(highScoreBest) {
      result = interpret(score) / interpret(comparedTo);
    }
    else {
      result = interpret(comparedTo) / interpret(score);
    }

    if(result.isNaN) {
      return 0.0;
    }
    else {
      return result;
    }
  }

  const StageScoring();

  static StageScoring fromDbString(String string) {
    if(string.startsWith(const HitFactorScoring().dbString)) return const HitFactorScoring();
    else if(string.startsWith(const TimePlusScoring().dbString)) return TimePlusScoring();
    else if(string.startsWith(const PointsScoring(highScoreBest: true).dbString)) {
      var options = string.split("|");
      var highScoreBest = options[1] == "true";

      var allowDecimal = false;
      if(options.length >= 3) {
        allowDecimal = options[2] == "true";
      }

      // If this gets any more gnarly, skip
      if(highScoreBest && allowDecimal) {
        return const PointsScoring(highScoreBest: true, allowDecimal: true);
      }
      else if(highScoreBest && !allowDecimal) {
        return const PointsScoring(highScoreBest: true, allowDecimal: false);
      }
      else if(!highScoreBest && allowDecimal) {
        return const PointsScoring(highScoreBest: false, allowDecimal: true);
      }
      else {
        return const PointsScoring(highScoreBest: false, allowDecimal: false);
      }
    }
    else return const IgnoredScoring();
  }
}

class HitFactorScoring extends StageScoring {
  num interpret(RawScore score) => score.hitFactor;
  bool get highScoreBest => true;

  const HitFactorScoring();
}

class TimePlusScoring extends StageScoring {
  num interpret(RawScore score) => score.finalTime;
  bool get highScoreBest => false;

  const TimePlusScoring();
}

class PointsScoring extends StageScoring {
  num interpret(RawScore score) => score.points;
  final bool highScoreBest;
  final bool allowDecimal;

  String get dbString => "${this.runtimeType.toString()}|$highScoreBest|$allowDecimal";

  const PointsScoring({this.highScoreBest = true, this.allowDecimal = false});

  @override
  bool operator ==(Object other) {
    if(other is PointsScoring) {
      return highScoreBest == other.highScoreBest && allowDecimal == other.allowDecimal;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(highScoreBest, allowDecimal);
}

class IgnoredScoring extends StageScoring {
  num interpret(RawScore score) => 0;
  bool get highScoreBest => true;

  const IgnoredScoring();
}

/// A relative score is a raw score placed against other scores.
abstract class RelativeScore {
  /// The shooter to whom this score belongs.
  MatchEntry shooter;

  /// The ordinal place represented by this score: 1 for 1st, 2 for 2nd, etc.
  int place;
  /// The ratio of this score to the winning score: 1.0 for the winner, 0.9 for a 90% finish,
  /// 0.8 for an 80% finish, etc.
  double ratio;
  /// A convenience getter for [ratio] * 100.
  double get percentage => ratio * 100;

  /// points holds the final score for this relative score, whether
  /// calculated or simply repeated from an attached [RawScore].
  ///
  /// In a [RelativeStageFinishScoring] match, it's the number of stage
  /// points or the total number of match points. In a [CumulativeScoring]
  /// match, it's the final points or time per stage/match.
  double points;

  RelativeScore({
    required this.shooter,
    required this.place,
    required this.ratio,
    required this.points,
  });
}

/// A relative match score is an overall score for an entire match.
class RelativeMatchScore extends RelativeScore {
  Map<MatchStage, RelativeStageScore> stageScores;
  RawScore total;

  RelativeMatchScore({
    required super.shooter,
    required this.stageScores,
    required super.place,
    required super.ratio,
    required super.points,
  }) : total = stageScores.values.map((e) => e.score).sum {
    var max = maxPoints();
    var actualPoints = stageScores.values.map((e) => e.score.getTotalPoints(countPenalties: true)).sum.toDouble();
    percentTotalPoints = actualPoints / max;
  }

  late double percentTotalPoints;
  double percentTotalPointsWithSettings({bool scoreDQ = true, bool countPenalties = true, Map<MatchStage, int> stageMaxPoints = const {}}) {
    if(scoreDQ && countPenalties && stageMaxPoints.isEmpty) {
      return percentTotalPoints;
    }

    var max = maxPoints(stageMaxPoints: stageMaxPoints);
    var actualPoints = stageScores.values.map((e) => !scoreDQ && shooter.dq ? 0 : e.score.getTotalPoints(countPenalties: countPenalties)).sum.toDouble();

    return actualPoints / max;
  }

  int maxPoints({Map<MatchStage, int> stageMaxPoints = const{}}) {
    int max = 0;
    for(var stage in stageScores.keys) {
      max += stageMaxPoints[stage] ?? stageScores[stage]!.stage!.maxPoints;
    }
    return max;
  }

  bool get isDnf => stageScores.values.any((s) => s.isDnf);

  bool get hasResults {
    for(var s in stageScores.values) {
      if(!s.score.dnf) {
        return true;
      }
    }

    return false;
  }
}

class RelativeStageScore extends RelativeScore {
  MatchStage stage;
  RawScore score;
  RelativeStageScore({
    required super.shooter,
    required this.stage,
    required this.score,
    required super.place,
    required super.ratio,
    required super.points,
  });

  double getPercentTotalPoints({bool scoreDQ = true, bool countPenalties = true, int? maxPoints}) {
    maxPoints ??= stage.maxPoints;
    if(maxPoints == 0) return 0.0;
    return !scoreDQ && shooter.dq ? 0.0 : score.getTotalPoints(countPenalties: countPenalties).toDouble() / maxPoints.toDouble();
  }

  bool get isDnf => score.dnf;
}

/// A raw score is what we store in the DB, and is what we can determine entirely from the shooter's
/// time and hits.
class RawScore {
  /// How this score should be interpreted.
  StageScoring scoring;

  /// The raw time on the shot timer. Use 0 for untimed sports.
  double rawTime;

  /// Scoring events for this score: that is, events caused by a hit or
  /// lack of hit on a target.
  Map<ScoringEvent, int> targetEvents;

  /// Penalty events for this score: that is, events caused by a competitor's
  /// actions or failures to act outside of hits or misses on targets.
  Map<ScoringEvent, int> penaltyEvents;
  List<double> stringTimes;
  
  List<Map<ScoringEvent, int>> get _scoreMaps => [targetEvents, penaltyEvents];

  int get scoringEventCount => targetEventCount + penaltyEventCount;

  int get targetEventCount => targetEvents.values.sum;
  int get penaltyEventCount => penaltyEvents.values.sum;

  int countForEvent(ScoringEvent event) {
    var fromTarget = targetEvents[event];
    if(fromTarget != null) return fromTarget;

    var fromPenalty = penaltyEvents[event];
    if(fromPenalty != null) return fromPenalty;

    return 0;
  }
  
  int get points => _scoreMaps.points;
  int get penaltyCount => penaltyEvents.values.sum;
  double get finalTime => rawTime + _scoreMaps.timeAdjustment;

  int getTotalPoints({bool countPenalties = true, bool allowNegative = false}) {
    if(countPenalties) {
      if(allowNegative) {
        return points;
      }
      else {
        return max(0, points);
      }
    }
    else {
      return targetEvents.points;
    }
  }

  RawScore({
    required this.scoring,
    this.rawTime = 0.0,
    required this.targetEvents,
    this.penaltyEvents = const {},
    this.stringTimes = const [],
  });

  bool get dnf =>
      (this.scoring is HitFactorScoring && targetEvents.length == 0 && rawTime == 0.0)
      || (this.scoring is TimePlusScoring && rawTime == 0.0)
      || (this.scoring is PointsScoring && points == 0);

  /// The hit factor represented by this score.
  ///
  /// Returns 0 (DNF) when raw time is zero, unless [scoring] is
  /// [PointsScoring], in which case this is treated like a USPSA
  /// fixed time stage, and the raw point total is returned as a
  /// 'hit factor'.
  double get hitFactor {
    if(rawTime == 0.0) {
      if(rawTime == 0.0 && scoring is PointsScoring && points > 0) {
        return points.toDouble();
      }
      // DNF
      return 0;
    }
    else {
      return getTotalPoints() / rawTime;
    }
  }

  String get displayString => scoring.displayString(this);
  String get displayLabel => scoring.displayLabel(this);

  RawScore copy() {
    return RawScore(
      scoring: scoring,
      stringTimes: []..addAll(stringTimes),
      rawTime: rawTime,
      targetEvents: {}..addAll(targetEvents),
      penaltyEvents: {}..addAll(penaltyEvents),
    );
  }

  operator +(RawScore other) {
    Map<ScoringEvent, int> targetEvents = {};
    Map<ScoringEvent, int> penaltyEvents = {};
    for(var entry in this.targetEvents.entries) {
      targetEvents.incrementBy(entry.key, entry.value);
    }
    for(var entry in this.penaltyEvents.entries) {
      penaltyEvents.incrementBy(entry.key, entry.value);
    }
    for(var entry in other.targetEvents.entries) {
      targetEvents.incrementBy(entry.key, entry.value);
    }
    for(var entry in other.penaltyEvents.entries) {
      penaltyEvents.incrementBy(entry.key, entry.value);
    }

    var s = RawScore(
      scoring: this.scoring,
      rawTime: this.rawTime + other.rawTime,
      stringTimes: []..addAll(this.stringTimes)..addAll(other.stringTimes),
      targetEvents: targetEvents,
      penaltyEvents: penaltyEvents,
    );

    return s;
  }
}

/// A ScoringEvent is the minimal unit of score change in a shooting sports
/// discipline, based on a hit on target.
class ScoringEvent implements NameLookupEntity {
  String get longName => name;
  final String name;
  final String shortName;
  final List<String> alternateNames;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  final int pointChange;
  final double timeChange;
  final bool displayInOverview;

  /// bonus indicates that this hit is a bonus/tiebreaker score with no other scoring implications:
  ///
  /// An ICORE stage with a time bonus for a X-ring hits is _not_ a bonus like this, because it scores
  /// differently than an A. A Bianchi X hit _is_ a bonus: it scores 10 points, but also increments
  /// your X count.
  final bool bonus;
  final String bonusLabel;

  bool get fallback => false;

  const ScoringEvent(this.name, {this.displayInOverview = true, this.shortName = "", this.pointChange = 0, this.timeChange = 0, this.bonus = false, this.bonusLabel = "X", this.alternateNames = const []});

  @override
  String toString() {
    return name;
  }
}

extension ScoreUtilities on Map<ScoringEvent, int> {
  int get points {
    int total = 0;
    for(var s in keys) {
      int occurrences = this[s]!;
      total += s.pointChange * occurrences;
    }
    return total;
  }
  
  double get timeAdjustment {
    double total = 0;
    for(var s in keys) {
      int occurrences = this[s]!;
      total += s.timeChange * occurrences;
    }
    return total;
  }
}

extension ScoreMapUtilities on List<Map<ScoringEvent, int>> {
  int get points {
    return this.map((m) => m.points).sum;
  }
  double get timeAdjustment {
    return this.map((m) => m.timeAdjustment).sum;
  }
}

extension ScoreListUtilities on Iterable<RawScore> {
  RawScore get sum {
    Map<ScoringEvent, int> scoringEvents = {};
    Map<ScoringEvent, int> penaltyEvents = {};
    double rawTime = 0;
    StageScoring scoring = HitFactorScoring();

    for(var s in this) {
      scoring = s.scoring;
      for(var e in s.targetEvents.keys) {
        scoringEvents[e] ??= 0;
        scoringEvents.incrementBy(e, s.targetEvents[e]!);
      }

      for(var e in s.penaltyEvents.keys) {
        penaltyEvents[e] ??= 0;
        penaltyEvents.incrementBy(e, s.penaltyEvents[e]!);
      }

      rawTime += s.rawTime;
    }

    return RawScore(scoring: scoring, targetEvents: scoringEvents, penaltyEvents: penaltyEvents, rawTime: rawTime);
  }
}

extension MatchScoresToCSV on List<RelativeMatchScore> {
  String toCSV() {
    String csv = "Member#,Name,MatchPoints,Percentage\n";
    var sorted = this.sorted((a, b) => a.place.compareTo(b.place));

    for(var score in sorted) {
      csv += "${score.shooter.memberNumber},";
      csv += "${score.shooter.getName(suffixes: false)},";
      csv += "${score.total.points.toStringAsFixed(2)},";
      csv += "${score.ratio.asPercentage()}\n";
    }

    return csv;
  }
}

extension Sorting on List<RelativeMatchScore> {
  void sortByScore({MatchStage? stage}) {
    if(stage != null) {
      this.sort((a, b) {
        if(a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          return b.stageScores[stage]!.points.compareTo(a.stageScores[stage]!.points);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        return b.points.compareTo(a.points);
      });
    }
  }

  void sortByTime({MatchStage? stage, required bool scoreDQs, required MatchScoring scoring}) {
    if (stage != null) {
      this.sort((a, b) {
        if(!scoreDQs) {
          if (a.shooter.dq && !b.shooter.dq) {
            return 1;
          }
          if (b.shooter.dq && !a.shooter.dq) {
            return -1;
          }
        }

        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          if(a.stageScores[stage]!.score.finalTime == 0 && b.stageScores[stage]!.score.finalTime == 0) return 0;
          else if(a.stageScores[stage]!.score.finalTime > 0 && b.stageScores[stage]!.score.finalTime == 0) return -1;
          else if(a.stageScores[stage]!.score.finalTime == 0 && b.stageScores[stage]!.score.finalTime > 0) return 1;

          return a.stageScores[stage]!.score.finalTime.compareTo(b.stageScores[stage]!.score.finalTime);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        if (!scoreDQs) {
          if (a.shooter.dq && !b.shooter.dq) {
            return 1;
          }
          else if (b.shooter.dq && !a.shooter.dq) {
            return -1;
          }
          else if(a.shooter.dq && b.shooter.dq) {
            return a.shooter.lastName.compareTo(b.shooter.lastName);
          }
        }

        if(scoring is CumulativeScoring) {
          if(scoring.lowScoreWins) {
            var aDnf = a.stageScores.values.any((s) => s.score.dnf);
            var bDnf = b.stageScores.values.any((s) => s.score.dnf);

            if(aDnf && !bDnf) {
              return 1;
            }
            else if(bDnf && !aDnf) {
              return -1;
            }
            else if(aDnf && bDnf) {
              return a.shooter.lastName.compareTo(b.shooter.lastName);
            }
          }
        }

        if(a.total.finalTime == 0 && b.total.finalTime == 0) return 0;
        else if(a.total.finalTime > 0 && b.total.finalTime == 0) return -1;
        else if(a.total.finalTime == 0 && b.total.finalTime > 0) return 1;

        return a.total.finalTime.compareTo(b.total.finalTime);
      });
    }
  }

  void sortByRawTime({MatchStage? stage, required bool scoreDQs, required MatchScoring scoring}) {
    if (stage != null) {
      this.sort((a, b) {
        if(!scoreDQs) {
          if (a.shooter.dq && !b.shooter.dq) {
            return 1;
          }
          if (b.shooter.dq && !a.shooter.dq) {
            return -1;
          }
        }

        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          if(a.stageScores[stage]!.score.rawTime == 0 && b.stageScores[stage]!.score.rawTime == 0) return 0;
          else if(a.stageScores[stage]!.score.rawTime > 0 && b.stageScores[stage]!.score.rawTime == 0) return -1;
          else if(a.stageScores[stage]!.score.rawTime == 0 && b.stageScores[stage]!.score.rawTime > 0) return 1;

          return a.stageScores[stage]!.score.rawTime.compareTo(b.stageScores[stage]!.score.rawTime);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        if (!scoreDQs) {
          if (a.shooter.dq && !b.shooter.dq) {
            return 1;
          }
          if (b.shooter.dq && !a.shooter.dq) {
            return -1;
          }
        }

        if(scoring is CumulativeScoring) {
          if(scoring.lowScoreWins) {
            var aDnf = a.stageScores.values.any((s) => s.score.dnf);
            var bDnf = b.stageScores.values.any((s) => s.score.dnf);

            if(aDnf && !bDnf) {
              return 1;
            }
            else if(bDnf && !aDnf) {
              return -1;
            }
            else if(aDnf && bDnf) {
              return a.shooter.lastName.compareTo(b.shooter.lastName);
            }
          }
        }

        if(a.total.rawTime == 0 && b.total.rawTime == 0) return 0;
        else if(a.total.rawTime > 0 && b.total.rawTime == 0) return -1;
        else if(a.total.rawTime == 0 && b.total.rawTime > 0) return 1;

        return a.total.rawTime.compareTo(b.total.rawTime);
      });
    }
  }

  void sortByIdpaAccuracy({MatchStage? stage, required MatchScoring scoring}) {
    this.sort((a, b) {
      if (a.total.dnf && !b.total.dnf) {
        return 1;
      }
      if (b.total.dnf && !a.total.dnf) {
        return -1;
      }

      if(scoring is CumulativeScoring) {
        if(scoring.lowScoreWins) {
          var aDnf = a.stageScores.values.any((s) => s.score.dnf);
          var bDnf = b.stageScores.values.any((s) => s.score.dnf);

          if(aDnf && !bDnf) {
            return 1;
          }
          else if(bDnf && !aDnf) {
            return -1;
          }
          else if(aDnf && bDnf) {
            return a.shooter.lastName.compareTo(b.shooter.lastName);
          }
        }
      }

      var aPointDown = a.shooter.powerFactor.targetEvents.lookupByName("-1");
      var bPointDown = b.shooter.powerFactor.targetEvents.lookupByName("-1");
      var aNonThreat = a.shooter.powerFactor.penaltyEvents.lookupByName("Non-Threat");
      var bNonThreat = b.shooter.powerFactor.penaltyEvents.lookupByName("Non-Threat");

      if(aPointDown == null || bPointDown == null || aNonThreat == null || bNonThreat == null) {
        return 0;
      }

      RawScore? aScore, bScore;
      if(stage != null) {
        aScore = a.stageScores[stage]?.score;
        bScore = b.stageScores[stage]?.score;
      }
      else {
        aScore = a.total;
        bScore = b.total;
      }

      if(aScore == null && bScore == null) return 0;
      else if(aScore != null && bScore == null) return -1;
      else if(aScore == null && bScore != null) return 1;

      var aDown = aScore!.targetEvents[aPointDown] ?? 0;
      var bDown = bScore!.targetEvents[bPointDown] ?? 0;
      var aNT = aScore.penaltyEvents[aNonThreat] ?? 0;
      var bNT = bScore.penaltyEvents[bNonThreat] ?? 0;

      if(aNT == bNT) return aDown.compareTo(bDown);
      else return aNT.compareTo(bNT);
    });
  }

  void sortByAlphas({MatchStage? stage}) {
    if (stage != null) {
      this.sort((a, b) {
        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          var aAlpha = a.shooter.powerFactor.targetEvents.lookupByName("A");
          var bAlpha = b.shooter.powerFactor.targetEvents.lookupByName("A");

          if(aAlpha == null || bAlpha == null) return 0;

          var aAlphaCount = a.stageScores[stage]!.score.targetEvents[aAlpha]!;
          var bAlphaCount = b.stageScores[stage]!.score.targetEvents[bAlpha]!;
          return bAlphaCount.compareTo(aAlphaCount);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        var aAlpha = a.shooter.powerFactor.targetEvents.lookupByName("A");
        var bAlpha = b.shooter.powerFactor.targetEvents.lookupByName("A");

        if(aAlpha == null || bAlpha == null) return 0;

        var aAlphaCount = a.total.targetEvents[aAlpha] ?? 0;
        var bAlphaCount = b.total.targetEvents[bAlpha] ?? 0;
        return bAlphaCount.compareTo(aAlphaCount);
      });
    }
  }

  void sortByAvailablePoints({MatchStage? stage, bool scoreDQ = true}) {
    // Available points is meaningless if max points is 0.
    if(this.length > 0) {
      if(this.first.stageScores.values.map((e) => e.stage.maxPoints).sum == 0) {
        sortByScore(stage: stage);
        return;
      }
    }

    if (stage != null) {
      this.sort((a, b) {
        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          return b.stageScores[stage]!.getPercentTotalPoints(scoreDQ: scoreDQ).compareTo(a.stageScores[stage]!.getPercentTotalPoints(scoreDQ: scoreDQ));
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        return b.percentTotalPoints.compareTo(a.percentTotalPoints);
      });
    }
  }

  void sortBySurname() {
    this.sort((a, b) {
      return a.shooter.lastName.compareTo(b.shooter.lastName);
    });
  }

  void sortByRating({required Map<DbRatingGroup, Rater> ratings, required RatingDisplayMode displayMode, required PracticalMatch match}) {
    this.sort((a, b) {
      return a.shooter.lastName.compareTo(b.shooter.lastName);

      // TODO: restore when ratings use the new feature
      // var aRating = ratings.lookupRating(shooter: a.shooter, mode: displayMode, match: match) ?? -1000;
      // var bRating = ratings.lookupRating(shooter: b.shooter, mode: displayMode, match: match) ?? -1000;
      // return bRating.compareTo(aRating);
    });
  }

  void sortByClassification() {
    this.sort((a, b) {
      return (a.shooter.classification?.index ?? 100000).compareTo(b.shooter.classification?.index ?? 100000);
    });
  }
}