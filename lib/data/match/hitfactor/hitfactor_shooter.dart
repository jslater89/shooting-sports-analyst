import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/parser/hitfactor/results_file_parser.dart';

class HitFactorShooter extends Shooter {
  USPSADivision? division;
  USPSAClassification? classification;

  Map<Stage, Score> stageScores = {};

  String getName({bool suffixes = true}) {
    if(!suffixes) return [firstName, lastName].join(" ");

    var components = [firstName, lastName];
    if(dq) components.add("(DQ)");
    if(reentry) components.add("(R)");
    return components.join(" ");
  }

  HitFactorShooter copy(HitFactorMatch parent) {
    var newShooter = HitFactorShooter()
      ..division = division
      ..classification = classification
      ..stageScores = {};

    newShooter.copyFrom(this, parent);

    stageScores.forEach((stage, score) {
      newShooter.stageScores[parent.lookupStage(stage)!] = score.copy(newShooter, stage);
    });

    return newShooter;
  }

  @override
  String toString() {
    return getName(suffixes: false);
  }
}