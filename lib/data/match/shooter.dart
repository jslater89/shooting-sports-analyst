import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/match/match.dart';
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

  PowerFactor? powerFactor;
  bool reentry = false;
  bool dq = false;

  Map<Stage, Score> stageScores = {};

  String getName({bool suffixes = true}) {
    if(!suffixes) return [firstName, lastName].join(" ");

    var components = [firstName, lastName];
    if(dq) components.add("(DQ)");
    if(reentry) components.add("(R)");
    return components.join(" ");
  }

  void copyFrom(Shooter other, PracticalMatch parent) {
    firstName = other.firstName;
    lastName = other.lastName;
    originalMemberNumber = other.originalMemberNumber;
    _hasOriginalMemberNumber = other._hasOriginalMemberNumber;
    memberNumber = other.memberNumber;
    reentry = other.reentry;
    dq = other.dq;
    powerFactor = other.powerFactor;
  }

  @override
  String toString() {
    return getName(suffixes: false);
  }
}

enum USPSADivision {
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

extension USPSADivisionFrom on USPSADivision {
  static USPSADivision string(String s) {
    s = s.trim().toLowerCase();
    switch(s) {
      case "pcc": return USPSADivision.pcc;
      case "pistol caliber carbine": return USPSADivision.pcc;

      case "open": return USPSADivision.open;

      case "ltd":
      case "limited": return USPSADivision.limited;

      case "co":
      case "carry optics": return USPSADivision.carryOptics;

      case "l10":
      case "ltd10":
      case "limited 10": return USPSADivision.limited10;

      case "prod":
      case "production": return USPSADivision.production;

      case "ss":
      case "single stack": return USPSADivision.singleStack;

      case "rev":
      case "revo":
      case "revolver": return USPSADivision.revolver;
      default: {
        if(verboseParse) debugPrint("Unknown division: $s");
        return USPSADivision.unknown;
      }
    }
  }
}

extension USPSADivisionDisplay on USPSADivision? {
  String displayString() {
    switch(this) {

      case USPSADivision.pcc:
        return "PCC";
      case USPSADivision.open:
        return "Open";
      case USPSADivision.limited:
        return "Limited";
      case USPSADivision.carryOptics:
        return "Carry Optics";
      case USPSADivision.limited10:
        return "Limited 10";
      case USPSADivision.production:
        return "Production";
      case USPSADivision.singleStack:
        return "Single Stack";
      case USPSADivision.revolver:
        return "Revolver";
      default:
        return "INVALID DIVISION";
    }
  }
}

enum ICOREDivision {
  open,
  limited,
  limited6,
  classic,
  unknown;

  static ICOREDivision fromString(String s) {
    s = s.trim().toLowerCase();
    switch(s) {
      case "o":
      case "open": return ICOREDivision.open;

      case "l":
      case "lim":
      case "limited": return ICOREDivision.limited;

      case "l6":
      case "lim6":
      case "limited6":
      case "limited 6": return ICOREDivision.limited6;

      case "c":
      case "classic": return ICOREDivision.classic;

      default: return ICOREDivision.unknown;
    }
  }

  String displayString() {
    switch(this) {
      case ICOREDivision.open:
        return "Open";
      case ICOREDivision.limited:
        return "Limited";
      case ICOREDivision.limited6:
        return "Limited 6";
      case ICOREDivision.classic:
        return "Classic";
      case ICOREDivision.unknown:
        return "Unknown";
    }
  }
}

enum IDPADivision {
  cdp,
  esp,
  co,
  ssp,
  ccp,
  rev,
  bug,
  pcc,
  unknown;

  static IDPADivision fromString(String s) {
    s = s.trim().toLowerCase();
    switch(s) {
      case "cdp": return IDPADivision.cdp;
      case "esp": return IDPADivision.esp;
      case "co": return IDPADivision.co;
      case "ssp": return IDPADivision.ssp;
      case "ccp": return IDPADivision.ccp;
      case "rev": return IDPADivision.rev;
      case "bug": return IDPADivision.bug;
      case "pcc": return IDPADivision.pcc;
      default: return IDPADivision.unknown;
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