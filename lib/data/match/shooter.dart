import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/parser/hitfactor/results_file_parser.dart';

class Shooter {
  String firstName = "";
  String lastName = "";

  String _memberNumber = "";
  late final String originalMemberNumber;
  bool _hasOriginalMemberNumber = false;

  String get memberNumber => _memberNumber;
  set memberNumber(String m) {
    if(!_hasOriginalMemberNumber) {
      originalMemberNumber = m.toUpperCase().replaceAll(RegExp(r"[^A-Z0-9]"), "");
      _hasOriginalMemberNumber = true;
    }
    _memberNumber = m;
  }

  bool reentry = false;
  bool dq = false;

  Division? division;
  USPSAClassification? classification;
  PowerFactor? powerFactor;

  Map<Stage, Score> stageScores = {};

  String getName({bool suffixes = true}) {
    if(!suffixes) return [firstName, lastName].join(" ");

    var components = [firstName, lastName];
    if(dq) components.add("(DQ)");
    if(reentry) components.add("(R)");
    return components.join(" ");
  }

  Shooter copy(HitFactorMatch parent) {
    var newShooter = Shooter()
      ..firstName = firstName
      ..lastName = lastName
      ..originalMemberNumber = originalMemberNumber
      .._hasOriginalMemberNumber = _hasOriginalMemberNumber
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

  @override
  String toString() {
    return getName(suffixes: false);
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

/// USPSA/ICORE-style letter-grade plus M/GM classification.
enum USPSAClassification {
  GM,
  M,
  A,
  B,
  C,
  D,
  U,
  unknown,
}

extension USPSAClassificationFrom on USPSAClassification {
  static USPSAClassification string(String s) {
    s = s.trim().toLowerCase();

    if(s.isEmpty) return USPSAClassification.U;

    switch(s) {
      case "gm": return USPSAClassification.GM;
      case "grandmaster": return USPSAClassification.GM;
      case "g": return USPSAClassification.GM;
      case "m": return USPSAClassification.M;
      case "master": return USPSAClassification.M;
      case "a": return USPSAClassification.A;
      case "b": return USPSAClassification.B;
      case "c": return USPSAClassification.C;
      case "d": return USPSAClassification.D;
      case "u": return USPSAClassification.U;
      case "x": return USPSAClassification.U;
      default:
        if(verboseParse) debugPrint("Unknown classification: $s");
        return USPSAClassification.U;
    }
  }
}

extension CDisplayString on USPSAClassification? {
  String displayString() {
    switch(this) {

      case USPSAClassification.GM:
        return "GM";
      case USPSAClassification.M:
        return "M";
      case USPSAClassification.A:
        return "A";
      case USPSAClassification.B:
        return "B";
      case USPSAClassification.C:
        return "C";
      case USPSAClassification.D:
        return "D";
      case USPSAClassification.U:
        return "U";
      case USPSAClassification.unknown:
        return "?";
      default: return "?";
    }
  }
}

enum IDPAClassification {
  DM,
  MA,
  EX,
  SS,
  MM,
  NV,
  UN,
  unknown,
}

extension IDPAClassificationFrom on IDPAClassification {
  static IDPAClassification string(String s) {
    s = s.trim().toLowerCase();

    if(s.isEmpty) return IDPAClassification.UN;

    switch(s) {
      case "dm": return IDPAClassification.DM;
      case "distinguished master": return IDPAClassification.DM;
      case "m": return IDPAClassification.MA;
      case "master": return IDPAClassification.MA;
      case "ma": return IDPAClassification.MA;
      case "ex": return IDPAClassification.EX;
      case "expert": return IDPAClassification.EX;
      case "ss": return IDPAClassification.SS;
      case "sharpshooter": return IDPAClassification.SS;
      case "mm": return IDPAClassification.MM;
      case "marksman": return IDPAClassification.MM;
      case "nv": return IDPAClassification.NV;
      case "novice": return IDPAClassification.NV;
      case "un": return IDPAClassification.UN;
      case "unclassified": return IDPAClassification.UN;
      default:
        if(verboseParse) debugPrint("Unknown classification: $s");
        return IDPAClassification.UN;
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