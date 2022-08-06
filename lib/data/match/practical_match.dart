import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';

class PracticalMatch {
  String? name;
  String? rawDate;
  DateTime? date;

  late String reportContents;

  List<Shooter> shooters = [];
  List<Stage> stages = [];

  int? maxPoints;

  PracticalMatch copy() {
    var newMatch = PracticalMatch()
      ..name = name
      ..rawDate = rawDate
      ..date = date
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
    // debugPrint("Max points for match: $matchMaxPoints");

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

  @override
  String toString() {
    return name ?? "unnamed match";
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