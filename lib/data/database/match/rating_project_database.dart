/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

extension RatingProjectDatabase on AnalystDatabase {
  Future<DbRatingProject?> getRatingProjectById(int id) async {
    return isar.dbRatingProjects.where().idEqualTo(id).findFirst();
  }

  Future<DbRatingProject> saveRatingProject(DbRatingProject project) async {
    await isar.writeTxn(() async {
      await isar.dbRatingProjects.put(project);
      project.customGroups.save();
      project.ratings.save();
      project.matches.save();
      project.filteredMatches.save();
      project.lastUsedMatches.save();
    });
    return project;
  }

  Future<List<DbRatingProject>> getAllRatingProjects() async {
    return isar.dbRatingProjects.where().findAll();
  }

  Future<bool> deleteRatingProject(DbRatingProject project) async {
    // clear all linked shooter ratings
    if(!project.ratings.isLoaded) {
      await project.ratings.load();
      for(var rating in project.ratings) {
        deleteShooterRating(rating);
      }
    }

    return isar.dbRatingProjects.delete(project.id);
  }

  Future<bool> deleteShooterRating(DbShooterRating rating) async {
    // TODO: clear all linked rating events
    return isar.dbShooterRatings.delete(rating.id);
  }
}