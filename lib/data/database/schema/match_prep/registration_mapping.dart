/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'registration_mapping.g.dart';

/// A MatchRegistrationMapping is a soft link between a registration (which may or may not contain a member number)
/// and a known competitor in one or more rating projects (who has a member number by definition).
///
/// Note that the existence of a MatchRegistrationMapping does not guarantee that the competitor with the
/// given member number exists in any particular rating project, just that it was detected and saved during match prep
/// for at least one rating project.
///
/// Its ID is a hash of the match ID, shooter name, and shooter division name, so 'put' is an upsert as long as those
/// values are stable.
///
/// It implements object equality and hash code based on its database ID, so operations on lists/sets of these objects
/// enforce database equality.
@collection
class MatchRegistrationMapping {
  Id get id => combineHashList([matchId.stableHash, shooterName.stableHash, shooterDivisionName.stableHash]);

  @Index(composite: [CompositeIndex("shooterName")])
  @Index(composite: [CompositeIndex("shooterName"), CompositeIndex("shooterDivisionName")])
  @Index()
  String matchId;

  @Index()
  String shooterName;

  String shooterClassificationName;
  String shooterDivisionName;

  List<String> detectedMemberNumbers;

  String? squad;
  int? get squadNumber {
    var stringNumber = squad?.toLowerCase().replaceAll("squad", "").trim();
    return int.tryParse(stringNumber ?? "");
  }

  bool matchesRegistration(MatchRegistration registration) {
    return registration.shooterName == shooterName
      && registration.shooterDivisionName == shooterDivisionName
      && registration.shooterClassificationName == shooterClassificationName;
  }

  MatchRegistrationMapping({
    required this.matchId,
    required this.shooterName,
    required this.shooterClassificationName,
    required this.shooterDivisionName,
    required this.detectedMemberNumbers,
    this.squad,
  });

  @override
  operator ==(Object other) {
    if(!(other is MatchRegistrationMapping)) return false;
    return this.id == other.id;
  }

  @override
  int get hashCode => id;
}
