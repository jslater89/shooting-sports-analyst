/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'registration.g.dart';

@collection
class MatchRegistrationMapping {
  Id get id => matchId.stableHash ^ shooterName.stableHash ^ shooterDivisionName.stableHash;

  @Index(composite: [CompositeIndex("shooterName")])
  @Index(composite: [CompositeIndex("shooterName"), CompositeIndex("shooterDivisionName")])
  @Index()
  String matchId;

  @Index()
  String shooterName;

  String shooterClassificationName;
  String shooterDivisionName;

  List<String> detectedMemberNumbers;

  MatchRegistrationMapping({
    required this.matchId,
    required this.shooterName,
    required this.shooterClassificationName,
    required this.shooterDivisionName,
    required this.detectedMemberNumbers,
  });
}
