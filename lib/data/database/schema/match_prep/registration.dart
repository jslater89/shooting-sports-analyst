/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'registration.g.dart';

/// A MatchRegistration is information about a match registration that may be sufficient
/// to look up a shooter in a rating project, sourced from a registration source.
///
/// It implements object equality and hash code based on its database ID, so operations on
/// list/sets of these objects enforce database equality.
@collection
class MatchRegistration {
  /// A unique identifier for the registration based on the match ID and entry ID.
  ///
  /// If a registration source does not have a stable entryId, that registration source
  /// should prefer to delete and recreate the FutureMatch and MatchRegistration objects.
  Id get id {
    return combineHashList([
      matchId.stableHash,
      entryId.stableHash,
    ]);
  }
  /// A unique identifier for the match.
  @Index()
  String matchId;
  /// An entry identifier for the shooter, used to uniquely identify the shooter in the match.
  /// This may be synthetic if a unique ID is unavailable in the registration source.
  String entryId;
  /// The name of the competitor.
  String? shooterName;
  /// The classification of the competitor.
  String? shooterClassificationName;
  /// The division of the competitor.
  String? shooterDivisionName;
  /// The member number of the competitor.
  List<String> shooterMemberNumbers;
  /// The squad of the competitor.
  String? squad;
  /// The number of the squad of the competitor.
  int? get squadNumber {
    var stringNumber = squad?.toLowerCase().replaceAll("squad", "").trim();
    return int.tryParse(stringNumber ?? "");
  }

  MatchRegistration({
    required this.matchId,
    required this.entryId,
    this.shooterName,
    this.shooterClassificationName,
    this.shooterDivisionName,
    this.shooterMemberNumbers = const [],
    this.squad,
  });

  operator ==(Object other) {
    if(!(other is MatchRegistration)) return false;
    return this.id == other.id;
  }

  @override
  int get hashCode => id;
}
