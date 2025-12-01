/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'registration_mapping.g.dart';

/// A MatchRegistrationMapping is a mapping of competitor name to a member number. While FutureMatches may
/// be deleted and recreated as registrations update (depending on the details of the registration source),
/// registration mappings are durable and can be used to re-link shooters to registrations.
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

  MatchRegistrationMapping({
    required this.matchId,
    required this.shooterName,
    required this.shooterClassificationName,
    required this.shooterDivisionName,
    required this.detectedMemberNumbers,
    this.squad,
  });
}
