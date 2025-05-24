/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

class RatingContext with ChangeNotifier {
  int? _projectId;

  RatingContext() {
    _projectId = ConfigLoader().config.ratingsContextProjectId;
  }

  bool get hasProjectId => _projectId != null;
  Future<bool> hasValidProject() async {
    if(_projectId == null) {
      return false;
    }
    else {
      return (await AnalystDatabase().getRatingProjectById(_projectId!)) != null;
    }
  }

  Future<DbRatingProject?> getProject() {
    if(_projectId == null) {
      return Future.value(null);
    }
    else {
      return AnalystDatabase().getRatingProjectById(_projectId!);
    }
  }

  Future<void> setProjectId(int projectId) async {
    _projectId = projectId;
    ConfigLoader().config.ratingsContextProjectId = projectId;
    await ConfigLoader().save();
    notifyListeners();
  }

  Future<void> clearProjectId() async {
    _projectId = null;
    ConfigLoader().config.ratingsContextProjectId = null;
    await ConfigLoader().save();
    notifyListeners();
  }

  Future<void> setProject(DbRatingProject project) async {
    _projectId = project.id;
    ConfigLoader().config.ratingsContextProjectId = project.id;
    await ConfigLoader().save();
    notifyListeners();
  }
}
