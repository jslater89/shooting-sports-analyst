/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// Biographical information on a shooter.
class Shooter {
  String firstName;
  String lastName;

  String _memberNumber = "";

  /// The first member number this shooter appeared with.
  String originalMemberNumber = "";

  /// All member numbers this shooter has been known by.
  Set<String> knownMemberNumbers = {};

  /// The shooter's most recent processed member number.
  String get memberNumber => _memberNumber;
  set memberNumber(String m) {
    var processedNumber = _processNumber(m);
    if(originalMemberNumber.isEmpty) {
      originalMemberNumber = processedNumber;
    }
    knownMemberNumbers.add(processedNumber);
    _memberNumber = processedNumber;
  }

  String _processNumber(String number) {
    return number.toUpperCase().replaceAll(RegExp(r"[^A-Z0-9]"), "");
  }

  AgeCategory? ageCategory;
  bool female = false;

  Shooter({
    required this.firstName,
    required this.lastName,
    String? memberNumber,
    this.female = false,
    this.ageCategory,
  }) {
    if(memberNumber != null) {
      this.memberNumber = memberNumber;
    }
  }

  String get name => getName(suffixes: false);

  String getName({bool suffixes = true}) {
    if(!suffixes) return [firstName, lastName].join(" ");

    var components = [firstName, lastName];
    if(female) components.add("(F)");
    return components.join(" ");
  }
}

/// A shooter embodied as a match entry.
class MatchEntry extends Shooter {
  int entryId;

  bool reentry;
  bool dq;
  PowerFactor powerFactor;

  /// The division this shooter entered. This will only be null when the
  /// sport doesn't have divisions.
  Division? division;

  /// The classification this shooter held at the time of the match entry.
  ///
  /// This will only be null when the sport doesn't have classifications.
  Classification? classification;

  Map<MatchStage, RawScore> scores;

  int? squad;

  MatchEntry({
    required super.firstName,
    required super.lastName,
    super.memberNumber,
    super.ageCategory,
    this.reentry = false,
    this.dq = false,
    required this.entryId,
    required this.powerFactor,
    required this.scores,
    this.squad,
    this.division,
    this.classification,
    super.female,
  });

  MatchEntry copy(List<MatchStage> stageCopies) {
    Map<MatchStage, RawScore> scoreCopies = {};
    for(var entry in scores.entries) {
      var oldStage = entry.key;
      var score = entry.value;
      var newStage = stageCopies.firstWhere((element) => element.stageId == oldStage.stageId);
      scoreCopies[newStage] = score.copy();
    }

    var e = MatchEntry(
      firstName: firstName,
      lastName: lastName,
      memberNumber: memberNumber,
      reentry: reentry,
      dq: dq,
      entryId: entryId,
      powerFactor: powerFactor,
      scores: scoreCopies,
      division: division,
      classification: classification,
      female: female,
      ageCategory: ageCategory,
      squad: squad,
    );

    e.knownMemberNumbers = {}..addAll(knownMemberNumbers);
    e._memberNumber = _memberNumber;
    e.originalMemberNumber = originalMemberNumber;

    return e;
  }

  String getName({bool suffixes = true}) {
    if(!suffixes) return [firstName, lastName].join(" ");

    var components = [firstName, lastName];
    if(dq) components.add("(DQ)");
    if(reentry) components.add("(R)");
    if(female) components.add("(F)");
    return components.join(" ");
  }

  @override
  String toString() {
    return "${getName(suffixes: false)} ($memberNumber)";
  }
}