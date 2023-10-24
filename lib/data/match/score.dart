/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:uspsa_result_viewer/ui/widget/score_list.dart';

class Score {
  Shooter shooter;
  Stage? stage;
  double t1 = 0, t2 = 0, t3 = 0, t4 = 0, t5 = 0;
  double time = 0;

  int a = 0, b = 0, c = 0, d = 0, m = 0, ns = 0, npm = 0;
  int procedural = 0, lateShot = 0, extraShot = 0, extraHit = 0, otherPenalty = 0;

  /// Number of times a target was hit
  int get hits => a + b + c + d + ns;

  int get shots => hits + m;

  Score({
    required this.shooter,
    this.stage
  });

  Score copy(Shooter shooter, Stage? stage) {
    var newScore = Score(shooter: shooter, stage: stage)
      ..t1 = t1
      ..t2 = t2
      ..t3 = t3
      ..t4 = t4
      ..t5 = t5
      ..time = time
      ..a = a
      ..b = b
      ..c = c
      ..d = d
      ..m = m
      ..ns = ns
      ..npm = npm
      ..procedural = procedural
      ..lateShot = lateShot
      ..extraShot = extraShot
      ..extraHit = extraHit
      ..otherPenalty = otherPenalty;

    return newScore;
  }

  List<double> get stringTimes {
    List<double> times = [];
    if(t1 > 0) times.add(t1);
    if(t2 > 0) times.add(t2);
    if(t3 > 0) times.add(t3);
    if(t4 > 0) times.add(t4);
    if(t5 > 0) times.add(t5);
    return times;
  }

  double getPercentTotalPoints({bool scoreDQ = true, bool countPenalties = true, int? maxPoints}) {
    maxPoints ??= stage!.maxPoints;
    return getTotalPoints(scoreDQ: scoreDQ, countPenalties: countPenalties).toDouble() / maxPoints.toDouble();
  }

  double getHitFactor({bool scoreDQ = true}) {
    if(stage?.type == Scoring.fixedTime) {
      return getTotalPoints(scoreDQ: scoreDQ).toDouble();
    }
    double score = double.parse((getTotalPoints(scoreDQ: scoreDQ) / time).toStringAsFixed(4));
    if(score.isInfinite) return 0;
    if(score.isNaN) return 0;
    return score;
  }

  int get penaltyCount {
    return procedural + lateShot + extraShot + extraHit + otherPenalty;
  }

  int get proceduralCount {
    return procedural + lateShot + extraShot + extraHit + otherPenalty;
  }

  int get penaltyPoints {
    int total = 0;
    total += 10 * m;
    total += 10 * ns;
    total += 10 * procedural;
    total += 10 * extraShot;
    total += 10 * extraHit;
    total += 10 * otherPenalty;
    total += 5 * lateShot;

    return total;
  }

  bool get isDnf {
    if(stage?.type == Scoring.chrono) return true;
    if(stage?.type == Scoring.fixedTime && rawPoints == 0) return true;
    if((stage?.type == Scoring.virginia || stage?.type == Scoring.comstock) && rawPoints == 0 && time == 0) return true;

    return false;
  }

  int get rawPoints {
    if(stage?.type == Scoring.chrono) return 0;

    var alphaValue = 5;
    var charlieValue = 4;
    var deltaValue = 2;
    if(shooter.powerFactor == PowerFactor.minor) {
      charlieValue = 3;
      deltaValue = 1;
    }
    else if(shooter.powerFactor == PowerFactor.subminor) {
      alphaValue = 0;
      charlieValue = 0;
      deltaValue = 0;
    }

    return a * alphaValue + b * charlieValue + c * charlieValue + d * deltaValue;
  }

  int getTotalPoints({bool scoreDQ = true, bool countPenalties = true}) {
    if(!scoreDQ && (shooter.dq)) return 0;

    if(countPenalties) {
      return max(0, rawPoints - penaltyPoints);
    }
    else {
      return rawPoints;
    }
  }

  operator+(Score other) {
    var s = copy(shooter, null);
    
    s.a += other.a;
    s.b += other.b;
    s.c += other.c;
    s.d += other.d;
    s.m += other.m;
    s.ns += other.ns;
    s.npm += other.npm;
    s.time += other.time;
    s.procedural += other.procedural;
    s.extraHit += other.extraHit;
    s.extraShot += other.extraShot;
    s.lateShot += other.lateShot;
    s.otherPenalty += other.otherPenalty;
    
    return s;
  }

  @override
  String toString() {
    return "${shooter.memberNumber} ${stage?.name ?? "Match"} ${getHitFactor(scoreDQ: false)}";
  }
}

enum Scoring {
  comstock,
  virginia,
  fixedTime,
  chrono,
  unknown,
}

extension ScoringFrom on Scoring {
  static Scoring string(String s) {
    s = s.trim().toLowerCase();
    switch(s) {
      case "comstock": return Scoring.comstock;
      case "virginia": return Scoring.virginia;
      case "fixed": return Scoring.fixedTime;
      case "chrono": return Scoring.chrono;
      default: {
        debugPrint("Unknown scoring: $s");
        return Scoring.unknown;
      }
    }
  }
}

extension Sorting on List<RelativeMatchScore> {
  void sortByScore({Stage? stage}) {
    if(stage != null) {
      this.sort((a, b) {
        if(a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          return b.stageScores[stage]!.relativePoints.compareTo(a.stageScores[stage]!.relativePoints);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        return b.total.relativePoints.compareTo(a.total.relativePoints);
      });
    }
  }

  void sortByTime({Stage? stage, required bool scoreDQs}) {
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
          if(a.stageScores[stage]!.score.time == 0 && b.stageScores[stage]!.score.time == 0) return 0;
          else if(a.stageScores[stage]!.score.time > 0 && b.stageScores[stage]!.score.time == 0) return -1;
          else if(a.stageScores[stage]!.score.time == 0 && b.stageScores[stage]!.score.time > 0) return 1;

          return a.stageScores[stage]!.score.time.compareTo(b.stageScores[stage]!.score.time);
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

        if(a.total.score.time == 0 && b.total.score.time == 0) return 0;
        else if(a.total.score.time > 0 && b.total.score.time == 0) return -1;
        else if(a.total.score.time == 0 && b.total.score.time > 0) return 1;

        return a.total.score.time.compareTo(b.total.score.time);
      });
    }
  }

  void sortByAlphas({Stage? stage}) {
    if (stage != null) {
      this.sort((a, b) {
        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          return b.stageScores[stage]!.score.a.compareTo(a.stageScores[stage]!.score.a);
        }
        else {
          return 0;
        }
      });
    }
    else {
      this.sort((a, b) {
        return b.total.score.a.compareTo(a.total.score.a);
      });
    }
  }

  void sortByAvailablePoints({Stage? stage, bool scoreDQ = true}) {
    if (stage != null) {
      this.sort((a, b) {
        if (a.stageScores.containsKey(stage) && b.stageScores.containsKey(stage)) {
          return b.stageScores[stage]!.score.getPercentTotalPoints(scoreDQ: scoreDQ).compareTo(a.stageScores[stage]!.score.getPercentTotalPoints(scoreDQ: scoreDQ));
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

  void sortByRating({required Map<RaterGroup, Rater> ratings, required RatingDisplayMode displayMode, required PracticalMatch match}) {
    this.sort((a, b) {
      var aRating = ratings.lookupRating(shooter: a.shooter, mode: displayMode, match: match) ?? -1000;
      var bRating = ratings.lookupRating(shooter: b.shooter, mode: displayMode, match: match) ?? -1000;
      return bRating.compareTo(aRating);
    });
  }

  void sortByClassification() {
    this.sort((a, b) {
      return (a.shooter.classification ?? Classification.U).index.compareTo((b.shooter.classification ?? Classification.U).index);
    });
  }
}
