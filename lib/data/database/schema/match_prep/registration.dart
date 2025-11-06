/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'registration.g.dart';

/// A MatchRegistration is information about a match registration that may be sufficient
/// to look up a shooter in a rating project.
@collection
class DbMatchRegistration {
  Id get id {
    if(shooterMemberNumber != null) {
      return combineHashes(matchId.stableHash, shooterMemberNumber!.stableHash);
    }
    else {
      return combineHashes(matchId.stableHash, entryId.stableHash);
    }
  }
  /// A unique identifier for the match.
  @Index()
  String matchId;
  /// An entry identifier for the shooter, used to uniquely identify the shooter in the match.
  /// This may be synthetic if a unique ID is unavailable in the registration source, e.g.
  /// the Practiscore squadding page parser may use name/classification/division as the entry ID.
  String entryId;
  /// The name of the competitor.
  String shooterName;
  /// The classification of the competitor.
  String? shooterClassificationName;
  /// The division of the competitor.
  String? shooterDivisionName;
  /// The member number of the competitor.
  String? shooterMemberNumber;
  /// The squad of the competitor.
  String? squad;
  /// The number of the squad of the competitor.
  int? get squadNumber {
    var stringNumber = squad?.toLowerCase().replaceAll("squad", "").trim();
    return int.tryParse(stringNumber ?? "");
  }

  DbMatchRegistration({
    required this.matchId,
    required this.entryId,
    required this.shooterName,
    this.shooterClassificationName,
    this.shooterDivisionName,
    this.shooterMemberNumber,
    this.squad,
  });

  DbMatchRegistration.from(MatchRegistration registration) :
    matchId = registration.matchId,
    entryId = registration.entryId,
    shooterName = registration.name,
    shooterClassificationName = registration.classification?.name,
    shooterDivisionName = registration.division?.name,
    shooterMemberNumber = registration.memberNumber,
    squad = registration.squad;

  MatchRegistration? hydrate(Sport sport) {
    var division = sport.divisions.lookupByName(shooterDivisionName);
    var classification = sport.classifications.lookupByName(shooterClassificationName);

    return MatchRegistration(
      name: shooterName,
      matchId: matchId,
      entryId: entryId,
      division: division,
      classification: classification,
      squad: squad,
    );
  }
}

class MatchRegistration {
  final String name;
  final String matchId;
  final String entryId;
  final String? memberNumber;
  final Division? division;
  final Classification? classification;
  final String? squad;
  int? get squadNumber {
    var stringNumber = squad?.toLowerCase().replaceAll("squad", "").trim();
    return int.tryParse(stringNumber ?? "");
  }


  const MatchRegistration({
    required this.name,
    required this.matchId,
    required this.entryId,
    this.memberNumber,
    required this.division,
    required this.classification,
    this.squad,
  });

  @override
  bool operator ==(Object other) {
    return (other is MatchRegistration)
        && other.name == this.name
        && other.division == this.division
        && other.classification == this.classification
        && other.memberNumber == this.memberNumber;
  }

  @override
  int get hashCode => combineHashList([name.stableHash, division?.name.stableHash ?? 0, classification?.name.stableHash ?? 0, memberNumber?.stableHash ?? 0]);

  static String syntheticEntryId(String name, String divisionName, String classificationName) {
    return combineHashList([name.stableHash, divisionName.stableHash, classificationName.stableHash]).toRadixString(36);
  }
}
