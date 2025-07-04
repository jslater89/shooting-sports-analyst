/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// import 'package:shooting_sports_analyst/data/db/object/match/shooter.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/results_file_parser.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("OldShooter");

class Shooter {
  String firstName = "";
  String lastName = "";

  int internalId = -1;
  String _memberNumber = "";

  /// The shooter's mostly-unprocessed member number.
  ///
  /// All non-alphanumeric characters are removed, and any alphabetic
  /// characters are made uppercase.
  String originalMemberNumber = "";

  /// The shooter's processed member number, i.e., the member number
  /// without any alphabetic characters.
  String get memberNumber => _memberNumber;
  set memberNumber(String m) {
    if(originalMemberNumber.isEmpty) {
      originalMemberNumber = m.toUpperCase().replaceAll(RegExp(r"[^A-Z0-9]"), "");
    }
    _memberNumber = m;
  }

  bool equalsShooter(Shooter other) {
    return memberNumber == other.memberNumber;
  }

  bool reentry = false;
  bool dq = false;

  bool female = false;

  Division? division;
  Classification? classification;
  PowerFactor? powerFactor;
  List<ShooterCategory> categories = [];

  Map<Stage, Score> stageScores = {};

  String getName({bool suffixes = true}) {
    if(!suffixes) return [firstName, lastName].join(" ");

    var components = [firstName, lastName];
    if(dq) components.add("(DQ)");
    if(reentry) components.add("(R)");
    if(female) components.add("(F)");
    return components.join(" ");
  }

  Shooter copy(PracticalMatch parent) {
    var newShooter = copyWithoutScores();

    stageScores.forEach((stage, score) {
      newShooter.stageScores[parent.lookupStage(stage)!] = score.copy(newShooter, stage);
    });

    return newShooter;
  }

  Shooter copyWithoutScores() {
    var newShooter = Shooter()
      ..firstName = firstName
      ..lastName = lastName
      ..internalId = internalId
      ..originalMemberNumber = originalMemberNumber
      ..memberNumber = memberNumber
      ..reentry = reentry
      ..dq = dq
      ..division = division
      ..classification = classification
      ..powerFactor = powerFactor
      ..female = female
      ..categories = ([]..addAll(categories))
      ..stageScores = {};

    return newShooter;
  }

  void copyVitalsFrom(Shooter other) {
    firstName = other.firstName;
    lastName = other.lastName;
    internalId = other.internalId;
    originalMemberNumber = other.originalMemberNumber;
    memberNumber = other.memberNumber;
    reentry = other.reentry;
    dq = other.dq;
    division = other.division;
    classification = other.classification;
    powerFactor = other.powerFactor;
    female = other.female;
    categories = []..addAll(other.categories);
  }

  // void copyDbVitalsFrom(DbShooterVitals other) {
  //   firstName = other.firstName;
  //   lastName = other.lastName;
  //   internalId = -1;
  //   originalMemberNumber = other.originalMemberNumber;
  //   memberNumber = other.memberNumber;
  //   reentry = false;
  //   dq = false;
  //   division = other.division;
  //   classification = other.classification;
  //   powerFactor = other.powerFactor;
  // }

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
  limitedOptics,
  limited10,
  production,
  singleStack,
  revolver,
  unknown;

  static Division fromString(String s) {
    s = s.trim().toLowerCase();
    switch(s) {
      case "pcc": return Division.pcc;
      case "pistol caliber carbine": return Division.pcc;

      case "open": return Division.open;

      case "ltd":
      case "standard":
      case "std":
      case "limited": return Division.limited;

      case "co":
      case "po":
      case "production optics":
      case "carry optics": return Division.carryOptics;

      case "lo":
      case "limited optics": return Division.limitedOptics;

      case "l10":
      case "ltd10":
      case "limited 10": return Division.limited10;

      case "prod":
      case "production": return Division.production;

      case "ss":
      case "classic":
      case "single stack": return Division.singleStack;

      case "rev":
      case "revo":
      case "revolver": return Division.revolver;
      default: {
        if(verboseParse) _log.w("Unknown division: $s");
        return Division.unknown;
      }
    }
  }

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
      case Division.limitedOptics:
        return "Limited Optics";
      case Division.unknown:
        return "Unknown Division";
    }
  }

  String abbreviation() {
    switch(this) {

      case Division.pcc:
        return "PCC";
      case Division.open:
        return "OPEN";
      case Division.limited:
        return "LIM";
      case Division.carryOptics:
        return "CO";
      case Division.limited10:
        return "L10";
      case Division.production:
        return "PROD";
      case Division.singleStack:
        return "SS";
      case Division.revolver:
        return "REV";
      case Division.limitedOptics:
        return "LO";
      case Division.unknown:
        return "UNK";
    }
  }
}

extension DivisionFrom on Division {
  static Division string(String s) {
    s = s.trim().toLowerCase();
    return Division.fromString(s);
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

enum ShooterCategory {
  junior,
  senior,
  superSenior,
  distinguishedSenior,
  lawEnforcement,
  military;

  static ShooterCategory? fromString(String s) {
    return switch(s.toLowerCase()) {
      "junior" => junior,
      "senior" => senior,
      "super senior" => superSenior,
      "distinguished senior" => distinguishedSenior,
      "law enforcement" => lawEnforcement,
      "military" => military,
      String() => null,
    };
  }

  String displayString() {
    return switch(this) {
      junior => "Junior",
      senior => "Senior",
      superSenior => "Super Senior",
      distinguishedSenior => "Distinguished Senior",
      lawEnforcement => "Law Enforcement",
      military => "Military",
    };
  }
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
        if(verboseParse) _log.w("Unknown classification: $s");
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
  subminor,
  unknown,
}

extension PowerFactorFrom on PowerFactor {
  static PowerFactor string(String s) {
    s = s.trim().toLowerCase();
    switch(s) {
      case "major": return PowerFactor.major;
      case "minor": return PowerFactor.minor;
      case "subminor": return PowerFactor.subminor;
      default: return PowerFactor.unknown;
    }
  }
}

extension PDisplayString on PowerFactor?{
  String displayString() {
    switch(this) {
      case PowerFactor.major: return "Major";
      case PowerFactor.minor: return "Minor";
      case PowerFactor.subminor: return "Subminor";
      default: return "?";
    }
  }

  String shortString() {
    switch(this) {
      case PowerFactor.major: return "Maj";
      case PowerFactor.minor: return "min";
      case PowerFactor.subminor: return "sub";
      default: return "?";
    }
  }
}
