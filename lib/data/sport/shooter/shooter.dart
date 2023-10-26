/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

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

  bool female = false;

  Shooter({
    required this.firstName,
    required this.lastName,
    String? memberNumber,
    this.female = false,
  }) {
    if(memberNumber != null) {
      this.memberNumber = memberNumber;
    }
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

  MatchEntry({
    required super.firstName,
    required super.lastName,
    super.memberNumber,
    this.reentry = false,
    this.dq = false,
    required this.entryId,
    required this.powerFactor,
    required this.scores,
    this.division,
    this.classification,
    super.female,
  });

  MatchEntry copy() {
    var e = MatchEntry(
      firstName: firstName,
      lastName: lastName,
      memberNumber: memberNumber,
      reentry: reentry,
      dq: dq,
      entryId: entryId,
      powerFactor: powerFactor,
      scores: scores,
      division: division,
      classification: classification,
      female: female,
    );

    e.knownMemberNumbers = {}..addAll(knownMemberNumbers);
    e._memberNumber = _memberNumber;
    e.originalMemberNumber = originalMemberNumber;

    return e;
  }
}