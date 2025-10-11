/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

List<RatingGroup> resolveRatingGroup(String groupUuid, DbRatingProject project) {
  if(!groupUuid.startsWith("uspsa-")) {
    groupUuid = "uspsa-$groupUuid";
  }
  var groups = project.groups.where((g) => g.uuid.startsWith(groupUuid)).toList();
  return groups.toList();
}
