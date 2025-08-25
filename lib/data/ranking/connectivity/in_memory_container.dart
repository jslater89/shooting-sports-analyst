
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("InMemoryConnectivity");

/// A container for connectivity data stored in memory. This is used
/// in project loading so that we can calculate connectivity without
/// needing to a) save DB ratings at every step, and b) use DB queries
/// to get the list of connectivity values and scores.
class InMemoryConnectivityContainer {
  Map<String, List<double>> _connectivityScores = {};

  void primeConnectivityScores(DbRatingProject project) {
    var db = AnalystDatabase();
    for(var group in project.groups) {
      var scores = db.getConnectivitySync(project, group);
      _connectivityScores[group.uuid] = scores;
    }
  }

  void addNewConnectivityScore(String groupUuid, double score) {
    _connectivityScores[groupUuid] ??= [];
    _connectivityScores[groupUuid]!.add(score);
  }

  void updateConnectivityScore(String groupUuid, double oldScore, double newScore) {
    List<double> scores = _connectivityScores[groupUuid]!;

    var index = scores.indexOf(oldScore);
    if(index == -1) {
      _log.e("Old score not found in connectivity scores for group $groupUuid: $oldScore");
      return;
    }
    scores[index] = newScore;
  }

  List<double> getConnectivityScores(String groupUuid) {
    return _connectivityScores[groupUuid]!;
  }

  double getConnectivitySum(String groupUuid) {
    return _connectivityScores[groupUuid]!.sum;
  }

}
