/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

extension ConnectivityCompetitors on List<MatchEntry> {
  List<MatchEntry> get connectivityCompetitors => this.where((e) => !e.dq && !e.reentry && e.memberNumber.isNotEmpty).toList();
}

extension ConnectivityMatchEntries on ShootingMatch {
  List<MatchEntry> connectivityCompetitors(RatingGroup group) {
    return this.filterShooters(
      filterMode: group.filters.mode,
      divisions: group.filters.activeDivisions.toList(),
      powerFactors: [],
      classes: [],
      allowReentries: false,
    ).connectivityCompetitors;
  }
}
