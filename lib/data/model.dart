
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum FilterMode {
  or, and,
}
class PracticalMatch {
  String? name;
  String? date;

  late String reportContents;

  List<Shooter> shooters = [];
  List<Stage> stages = [];

  int? maxPoints;

  PracticalMatch copy() {
    var newMatch = PracticalMatch()
        ..name = name
        ..date = date
        ..shooters = []
        ..stages = []
        ..maxPoints = maxPoints;

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
  List<Shooter> filterShooters({
    FilterMode? filterMode,
    bool? allowReentries = true,
    List<Division> divisions = Division.values,
    List<PowerFactor> powerFactors = PowerFactor.values,
    List<Classification> classes = Classification.values,
  }) {
    List<Shooter> filteredShooters = [];

    for(Shooter s in shooters) {
      if(filterMode == FilterMode.or) {
        if (divisions.contains(s.division) || powerFactors.contains(s.powerFactor) || classes.contains(s.classification)) {
          if(allowReentries! || !s.reentry) filteredShooters.add(s);
        }
      }
      else {
        if (divisions.contains(s.division) && powerFactors.contains(s.powerFactor) && classes.contains(s.classification)) {
          if(allowReentries! || !s.reentry) filteredShooters.add(s);
        }
      }
    }

    return filteredShooters;
  }

  /// Returns one relative score for each shooter provided, representing performance
  /// in a hypothetical match made up of the given shooters and stages.
  List<RelativeMatchScore> getScores({List<Shooter>? shooters, List<Stage>? stages, bool scoreDQ = true}) {
    List<Shooter> innerShooters = shooters != null ? shooters : this.shooters;
    List<Stage> innerStages = stages != null ? stages : this.stages;

    if(innerShooters.length == 0 || innerStages.length == 0) return [];

    int matchMaxPoints = innerStages.map<int>((e) => e.maxPoints).reduce((a, b) => a + b);
    debugPrint("Max points for match: $matchMaxPoints");

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
      //debugPrint("${shooter.firstName} ${shooter.lastName} shot ${totalScores[shooter].percentTotalPoints} total points");
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
        debugPrint("Winner of ${stage.name}: ${innerShooters[0].firstName} ${innerShooters[0].lastName} with ${innerShooters[0].stageScores[stage]!.getHitFactor(scoreDQ: scoreDQ)}");
        continue;
      }
      double highHitFactor = innerShooters[0].stageScores[stage]!.getHitFactor(scoreDQ: scoreDQ);
      //debugPrint("Winner of ${stage.name}: ${shooters[0].firstName} ${shooters[0].lastName} with ${shooters[0].stageScores[stage].hitFactor}");

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
}

class RelativeMatchScore {
  RelativeMatchScore({required this.shooter});

  Shooter shooter;
  late RelativeScore total;

  /// Percent of match max points shot
  late double percentTotalPoints;

  Map<Stage, RelativeScore> stageScores = {};
}

class RelativeScore {
  RelativeScore();
  late Score score;

  int place = -1;

  /// If null, treat this as a match score
  Stage? stage;

  /// For stage scores, calculate this off of
  /// hit factors and use to set relative points.
  double percent = 0;

  /// For match scores, total from stage scores
  /// and use to set percent.
  double relativePoints = 0;
}

class Shooter {
  String firstName = "";
  String lastName = "";
  String memberNumber = "";
  bool reentry = false;
  bool dq = false;

  Division? division;
  Classification? classification;
  PowerFactor? powerFactor;

  Map<Stage, Score> stageScores = {};

  String getName() {
    String dqSuffix = "";
    String reentrySuffix = "";
    if(dq) dqSuffix = "(DQ)";
    if(reentry) reentrySuffix = "(R)";
    return [firstName, lastName, reentrySuffix, dqSuffix].join(" ");
  }

  Shooter copy(PracticalMatch parent) {
    var newShooter = Shooter()
        ..firstName = firstName
        ..lastName = lastName
        ..memberNumber = memberNumber
        ..reentry = reentry
        ..dq = dq
        ..division = division
        ..classification = classification
        ..powerFactor = powerFactor
        ..stageScores = {};

    stageScores.forEach((stage, score) {
      newShooter.stageScores[parent.lookupStage(stage)!] = score.copy(newShooter, stage);
    });

    return newShooter;
  }
}

class Stage {
  String name;
  int minRounds = 0;
  int maxPoints = 0;
  bool classifier;
  String classifierNumber;
  Scoring type;

  Stage({
    required this.name,
    required this.minRounds,
    required this.maxPoints,
    required this.classifier,
    required this.classifierNumber,
    required this.type,
  });

  Stage copy() {
    return Stage(
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

  @override
  bool operator ==(Object other) {
    if(!(other is Stage)) return false;
    return this.name == other.name;
  }

  @override
  // TODO: implement hashCode
  int get hashCode => this.name.hashCode;
}

class Score {
  Shooter shooter;
  Stage? stage;
  double t1 = 0, t2 = 0, t3 = 0, t4 = 0, t5 = 0;
  double time = 0;

  int a = 0, b = 0, c = 0, d = 0, m = 0, ns = 0, npm = 0;
  int procedural = 0, lateShot = 0, extraShot = 0, extraHit = 0, otherPenalty = 0;

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
    if(stage!.type == Scoring.fixedTime) {
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

enum Division {
  pcc,
  open,
  limited,
  carryOptics,
  limited10,
  production,
  singleStack,
  revolver,
  unknown,
}

extension DivisionFrom on Division {
  static Division string(String s) {
    s = s.trim().toLowerCase();
    switch(s) {
      case "pcc": return Division.pcc;
      case "open": return Division.open;

      case "ltd":
      case "limited": return Division.limited;

      case "co":
      case "carry optics": return Division.carryOptics;

      case "l10":
      case "ltd10":
      case "limited 10": return Division.limited10;

      case "prod":
      case "production": return Division.production;

      case "ss":
      case "single stack": return Division.singleStack;

      case "revo":
      case "revolver": return Division.revolver;
      default: {
        debugPrint("Unknown division: $s");
        return Division.unknown;
      }
    }
  }
}

extension DDisplayString on Division? {
  String displayString() {
    switch(this) {

      case Division.pcc:
        return "PCC";
      case Division.open:
        return "Open";
      case Division.limited:
        return "Limited";
      case Division.carryOptics:
        return "Carry Optics";
      case Division.limited10:
        return "Limited 10";
      case Division.production:
        return "Production";
      case Division.singleStack:
        return "Single Stack";
      case Division.revolver:
        return "Revolver";
      default:
        return "INVALID DIVISION";
    }
  }
}

enum Classification {
  GM,
  M,
  A,
  B,
  C,
  D,
  U,
  unknown,
}

extension ClassificationFrom on Classification {
  static Classification string(String s) {
    s = s.trim().toLowerCase();
    switch(s) {
      case "gm": return Classification.GM;
      case "grandmaster": return Classification.GM;
      case "g": return Classification.GM;
      case "m": return Classification.M;
      case "master": return Classification.M;
      case "a": return Classification.A;
      case "b": return Classification.B;
      case "c": return Classification.C;
      case "d": return Classification.D;
      case "u": return Classification.U;
      default:
        debugPrint("Unknown classification: $s");
        return Classification.U;
    }
  }
}

extension CDisplayString on Classification? {
  String displayString() {
    switch(this) {

      case Classification.GM:
        return "GM";
      case Classification.M:
        return "M";
      case Classification.A:
        return "A";
      case Classification.B:
        return "B";
      case Classification.C:
        return "C";
      case Classification.D:
        return "D";
      case Classification.U:
        return "U";
      case Classification.unknown:
        return "?";
      default: return "?";
    }
  }
}

enum PowerFactor {
  major,
  minor,
  unknown,
}

extension PowerFactorFrom on PowerFactor {
  static PowerFactor string(String s) {
    s = s.trim().toLowerCase();
    switch(s) {
      case "major": return PowerFactor.major;
      case "minor": return PowerFactor.minor;
      default: return PowerFactor.unknown;
    }
  }
}

extension PDisplayString on PowerFactor?{
  String displayString() {
    switch(this) {
      case PowerFactor.major: return "Major";
      case PowerFactor.minor: return "Minor";
      default: return "?";
    }
  }

  String shortString() {
    switch(this) {
      case PowerFactor.major: return "Maj";
      case PowerFactor.minor: return "min";
      default: return "?";
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

extension AsPercentage on double {
  String asPercentage({int decimals = 2}) {
    return (this * 100).toStringAsFixed(2);
  }
}