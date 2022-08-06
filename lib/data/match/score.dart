import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';

class Score {
  Shooter shooter;
  Stage? stage;
  double t1 = 0, t2 = 0, t3 = 0, t4 = 0, t5 = 0;
  double time = 0;

  int a = 0, b = 0, c = 0, d = 0, m = 0, ns = 0, npm = 0;
  int procedural = 0, lateShot = 0, extraShot = 0, extraHit = 0, otherPenalty = 0;

  /// Number of times a target was hit
  int get hits => a + b + c + d + ns;

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

  double getPercentTotalPoints({bool scoreDQ = true}) {
    return getTotalPoints(scoreDQ: scoreDQ).toDouble() / stage!.maxPoints.toDouble();
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

  int get rawPoints {
    if(stage?.type == Scoring.chrono) return 0;

    int aValue = 5;
    int bValue = shooter.powerFactor == PowerFactor.major ? 4 : 3;
    int cValue = bValue;
    int dValue = shooter.powerFactor == PowerFactor.major ? 2 : 1;

    return a * aValue + b * bValue + c * cValue + d * dValue;
  }

  int getTotalPoints({bool scoreDQ = true}) {
    if(!scoreDQ && (shooter.dq)) return 0;
    else return max(0, rawPoints - penaltyPoints);
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
}
