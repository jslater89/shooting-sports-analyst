/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:io';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

SSALogger _log = SSALogger("DbOneoffs");

Future<void> oneoffDbAnalyses(AnalystDatabase db) async {
  // await _matchBumpGms(db);
  // await _addMemberNumbersToMatches(db);
  // await _doesMyQueryWork(db);
}

Future<void> _matchBumpGms(AnalystDatabase db) async {
  var matches = await db.isar.dbShootingMatchs.where().anyDate()
    .filter()
    .sportNameEqualTo(uspsaSport.name)
    .sortByDate().findAll();


  Map<ShootingMatch, MatchEntry> gmBumpEligible = {};
  Map<MatchEntry, ShootingMatch> gmBumpMatches = {};
  for(var dbMatch in matches) {
    var matchRes = await HydratedMatchCache().get(dbMatch);
    if(matchRes.isErr()) {
      continue;
    }
    var match = matchRes.unwrap();
    for(var division in uspsaSport.divisions.values) {
      // to be eligible for match bumps, a non-GM must win, and three GMs 
      // must finish above 90%.
      var scores = match.getScoresFromFilters(
        FilterSet(
          match.sport,
          divisions: [division],
          empty: true,
          mode: FilterMode.or,
        )
      );

      MatchEntry? winner;
      int gmsOver90 = 0;
      for(var scoreEntry in scores.entries) {
        var entry = scoreEntry.key;
        var score = scoreEntry.value;
        if(score.place == 1) {
          winner = entry;
        }
        else if(entry.classification == uspsaGM && score.percentage >= 90) {
          gmsOver90 += 1;
        }
        else if(score.percentage < 90) {
          break;
        }
      }

      if(gmsOver90 >= 3 && winner != null && winner.classification != uspsaGM) {
        gmBumpEligible[match] = winner;
        gmBumpMatches[winner] = match;
      }
    }
  }

  var project = (await db.getRatingProjectByName("L2s Main"))!;
  Map<MatchEntry, DbShooterRating> ratings = {};

  await project.dbGroups.load();

  for(var entry in gmBumpEligible.values) {
    if(entry.memberNumber == "TY104882") {
      print("break");
    }
    var group = await project.groupForDivision(entry.division).unwrap();
    if(group != null) {
      var rating = await project.lookupRating(group, entry.memberNumber, allPossibleMemberNumbers: true).unwrap();
      if(rating != null) {
        ratings[entry] = rating;
      }
    }
    else {
      print("!!! null group for ${entry.name} ${entry.memberNumber} ${entry.division}");
    }
  }

  print("Eligible for GM bumps: ");
  var bumpEligible = gmBumpEligible.values.sorted((a, b) {
    var aRating = ratings[a];
    var bRating = ratings[b];
    // The one without a rating comes first.
    if(aRating != null && bRating == null) {
      return 1;
    }
    else if(aRating == null && bRating != null) {
      return -1;
    }
    else if(aRating == null && bRating == null) {
      return a.name.compareTo(b.name);
    }
    else {
      return aRating!.rating.compareTo(bRating!.rating);
    }
  });
  for(var bumpEntry in bumpEligible) {
    var entry = bumpEntry;
    var match = gmBumpMatches[entry];
    var rating = ratings[entry];
    print("${entry.name} (${entry.memberNumber} ${entry.division} ${entry.classification}) (${rating?.rating.round() ?? "unrated"} ${rating?.lastClassification}) ${match?.name}");
  }
}

Future<void> _addMemberNumbersToMatches(AnalystDatabase db) async {
  var matches = await db.isar.dbShootingMatchs.where().anyDate().findAll();
  for(var match in matches) {
    match.memberNumbersAppearing = match.shooters.map((e) => e.memberNumber).where((e) => e.isNotEmpty).toList();
  }
  await db.isar.writeTxn(() async {
    await db.isar.dbShootingMatchs.putAll(matches);
  });
  _log.i("${matches.length} matches updated");
}

Future<void> _doesMyQueryWork(AnalystDatabase db) async {
  var startTime = DateTime.now();
  var matches = await db.queryMatchesByCompetitorMemberNumbers(["A102675", "TY102675", "FY102675"], pageSize: 5);
  var timeTaken = DateTime.now().difference(startTime).inMilliseconds;
  for(var match in matches) {
    _log.i("${match}");
  }
  _log.i("${matches.length} matches found in ${timeTaken}ms");
}

Future<void> _lady90PercentFinishes(AnalystDatabase db) async {
  var startTime = DateTime.now();
  var matches = await db.isar.dbShootingMatchs
    .filter()
    .shootersElement((q) =>
      q.femaleEqualTo(true)
      .and()
      .precalculatedScore((q) => q.percentageGreaterThan(90, include: true))
    )
    .sortByDate()
    .findAll();

  var buf = StringBuffer();
  for(var match in matches) {
    for(var shooter in match.shooters) {
      if(shooter.female && (shooter.precalculatedScore?.percentage ?? 0) >= 90) {
        var competitorCount = match.shooters.where((e) => e.divisionName == shooter.divisionName).length;
        buf.writeln('${match.date},${match.eventName.replaceAll(',', ' ')},${match.matchLevelName},${shooter.firstName},${shooter.lastName},${shooter.divisionName},${shooter.precalculatedScore?.percentage},${shooter.precalculatedScore?.place},${competitorCount}');
      }
    }
  }

  File f = File("female_90_percent.csv");
  f.writeAsString(buf.toString());
  _log.i("Analysis complete: wrote ${f.path} in ${DateTime.now().difference(startTime).inMilliseconds}ms");
}