import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';

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

  String getName({bool suffixes = true}) {
    if(!suffixes) return [firstName, lastName].join(" ");

    var components = [firstName, lastName];
    if(dq) components.add("(DQ)");
    if(reentry) components.add("(R)");
    return components.join(" ");
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
      case "pistol caliber carbine": return Division.pcc;

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

      case "rev":
      case "revo":
      case "revolver": return Division.revolver;
      default: {
        if(verboseParse) debugPrint("Unknown division: $s");
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

    if(s.isEmpty) return Classification.U;

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
      case "x": return Classification.U;
      default:
        if(verboseParse) debugPrint("Unknown classification: $s");
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

extension AsPercentage on double {
  String asPercentage({int decimals = 2}) {
    return (this * 100).toStringAsFixed(2);
  }
}