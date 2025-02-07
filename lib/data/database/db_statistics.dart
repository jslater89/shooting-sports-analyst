/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';

class DatabaseStatistics {
  int matchCount;
  int ratingProjectCount;
  Map<DbRatingProject, int> ratingProjectRatingCounts;
  Map<DbRatingProject, int> ratingProjectEventCounts;
  int ratingCount;
  int eventCount;
  
  int matchSize;
  int ratingProjectSize;
  int eventSize;
  int ratingSize;
  int totalSize;
  int maxSize;

  double averageRatingSize;
  double averageEventSize;
  double averageProjectSize;
  double averageMatchSize;

  Map<DbRatingProject, int> estimatedProjectSizes;

  DatabaseStatistics({
    required this.matchCount,
    required this.ratingProjectCount,
    required this.ratingProjectRatingCounts,
    required this.ratingProjectEventCounts,
    required this.ratingCount,
    required this.eventCount,
    required this.totalSize,
    required this.matchSize,
    required this.ratingProjectSize,
    required this.eventSize,
    required this.ratingSize,
    required this.maxSize,
    required this.averageRatingSize,
    required this.averageEventSize,
    required this.averageProjectSize,
    required this.averageMatchSize,
    required this.estimatedProjectSizes,
  });

  @override
  String toString() {
    var buf = StringBuffer();
    buf.writeln("Match count: $matchCount");
    buf.writeln("Rating project count: $ratingProjectCount");
    buf.writeln("Rating count: $ratingCount");
    buf.writeln("Event count: $eventCount");
    buf.writeln("Total size: $totalSize");
    buf.writeln("Match size: $matchSize");
    buf.writeln("Rating project size: $ratingProjectSize");
    buf.writeln("Event size: $eventSize");
    buf.writeln("Rating size: $ratingSize");
    buf.writeln("Max size: $maxSize");
    buf.writeln("Average rating size: $averageRatingSize");
    buf.writeln("Average event size: $averageEventSize");
    return buf.toString();
  }
}

extension Statistics on AnalystDatabase {
  Future<DatabaseStatistics> getBasicDatabaseStatistics() async {
    var projectCount = await isar.dbRatingProjects.count();
    var ratingCount = await isar.dbShooterRatings.count();
    var eventCount = await isar.dbRatingEvents.count();
    var matchCount = await isar.dbShootingMatchs.count();

    var matchSize = await isar.dbShootingMatchs.getSize();
    var ratingProjectSize = await isar.dbRatingProjects.getSize();
    var eventSize = await isar.dbRatingEvents.getSize();
    var ratingSize = await isar.dbShooterRatings.getSize();
    var totalSize = await isar.getSize();
    var maxSize = AnalystDatabase.maxSizeBytes;

    var averageRatingSize = ratingSize / ratingCount;
    var averageEventSize = eventSize / eventCount;
    var averageProjectSize = ratingProjectSize / projectCount;
    var averageMatchSize = matchSize / matchCount;

    return DatabaseStatistics(
      matchCount: matchCount,
      ratingProjectCount: projectCount,
      ratingProjectRatingCounts: {},
      ratingProjectEventCounts: {},
      totalSize: totalSize,
      matchSize: matchSize,
      ratingProjectSize: ratingProjectSize,
      eventSize: eventSize,
      ratingSize: ratingSize,
      maxSize: maxSize,
      averageRatingSize: averageRatingSize,
      averageEventSize: averageEventSize,
      averageProjectSize: averageProjectSize,
      averageMatchSize: averageMatchSize,
      ratingCount: ratingCount,
      eventCount: eventCount,
      estimatedProjectSizes: {},
    );
  }

  Future<void> loadPerProjectDatabaseStatistics(DatabaseStatistics stats) async {
    var projects = await getAllRatingProjects();
    var ratingProjectRatingCounts = <DbRatingProject, int>{};
    var ratingProjectEventCounts = <DbRatingProject, int>{};

    for(var project in projects) {
      ratingProjectRatingCounts[project] = await project.ratings.count();
      ratingProjectEventCounts[project] = project.eventCount < 0 ? 0 : project.eventCount;
    }

    var estimatedProjectSizes = <DbRatingProject, int>{};
    for(var project in projects) {
      estimatedProjectSizes[project] = 
        ((ratingProjectRatingCounts[project]! * stats.averageRatingSize) 
        + (ratingProjectEventCounts[project]! * stats.averageEventSize)).round();
    }

    stats.ratingProjectRatingCounts = ratingProjectRatingCounts;
    stats.ratingProjectEventCounts = ratingProjectEventCounts;
    stats.estimatedProjectSizes = estimatedProjectSizes;
  }
}