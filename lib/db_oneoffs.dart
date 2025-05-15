/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:shooting_sports_analyst/data/match/practical_match.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:intl/intl.dart';

SSALogger _log = SSALogger("DbOneoffs");

Future<void> oneoffDbAnalyses(AnalystDatabase db) async {
  // await _howGoodIsTomCastro(db);
  // await _matchBumpGms(db);
  // await _addMemberNumbersToMatches(db);
  // await _doesMyQueryWork(db);

  // var project = (await db.getRatingProjectByName("L2s Main"))!;
  //await calculateMatchHeat(db, project);
}

Future<void> _howGoodIsTomCastro(AnalystDatabase db) async {
  var project = (await db.getRatingProjectByName("L2s Main"))!;
  var pccGroup = await project.groupForDivision(uspsaPcc).unwrap();
  var coGroup = await project.groupForDivision(uspsaCarryOptics).unwrap();
  Set<String> memberNumbers = {};
  var pccTom = await project.getRatingsByDeduplicatorName(pccGroup!, "tomcastro").unwrap();
  var coTom = await project.getRatingsByDeduplicatorName(coGroup!, "tomcastro").unwrap();
  memberNumbers.addAll(pccTom.map((e) => e.allPossibleMemberNumbers).flattened);
  memberNumbers.addAll(coTom.map((e) => e.allPossibleMemberNumbers).flattened);
  var tomMatches = await db.getMatchesByMemberNumbers(memberNumbers.toList());
  print("Tom matches: ${tomMatches.length}");

  List<int> tomPccFinishes = [];
  List<int> tomCoFinishes = [];
  List<String> matchNamesThatCount = [];
  List<int> pccMatchSizes = [];
  List<int> coMatchSizes = [];
  for(var match in tomMatches) {
    if(match.eventName.toLowerCase().contains("fipt") || match.eventName.toLowerCase().contains("f.i.p.t.")) continue;
    if(match.eventName.toLowerCase().contains("side match")) continue;
    if(match.eventName.toLowerCase().contains("richmond hotshots")) continue;
    if(match.matchEventLevel == uspsaLevel1
      && !match.eventName.toLowerCase().contains("national")
      && !match.eventName.toLowerCase().contains("area")
      && !match.eventName.toLowerCase().contains("championship")
      && !match.eventName.toLowerCase().contains("sectional")
      && !match.eventName.toLowerCase().contains("ipsc")) continue;
    for(var entry in match.shooters) {
      if(memberNumbers.contains(entry.memberNumber)) {
        var division = uspsaSport.divisions.lookupByName(entry.divisionName);
        if(division == uspsaPcc) {
          if(entry.precalculatedScore == null) {
            tomPccFinishes.add(await _getTomPlace(match, entry));
          }
          else {
            tomPccFinishes.add(entry.precalculatedScore!.place);
          }
          pccMatchSizes.add(match.shooters.where((e) => e.divisionName == entry.divisionName).length);
          matchNamesThatCount.add(match.eventName);
        }
        else if(division == uspsaCarryOptics) {
          if(entry.precalculatedScore == null) {
            tomCoFinishes.add(await _getTomPlace(match, entry));
          }
          else {
            tomCoFinishes.add(entry.precalculatedScore!.place);
          }
          matchNamesThatCount.add(match.eventName);
          coMatchSizes.add(match.shooters.where((e) => e.divisionName == entry.divisionName).length);
        }
        else {
          print("Tom competed in ${entry.divisionName}");
        }
      }
    }
  }

  var pccWins = tomPccFinishes.where((e) => e == 1).length;
  var coWins = tomCoFinishes.where((e) => e == 1).length;
  print("Match names that count: \n${matchNamesThatCount.join("\n")}");
  print("PCC wins: $pccWins/${tomPccFinishes.length}");
  print("CO wins: $coWins/${tomCoFinishes.length}");
  print("PCC average finish: ${tomPccFinishes.average.toStringAsFixed(2)}/${pccMatchSizes.average.toStringAsFixed(2)}");
  print("CO average finish: ${tomCoFinishes.average.toStringAsFixed(2)}/${coMatchSizes.average.toStringAsFixed(2)}");
}

Future<int> _getTomPlace(DbShootingMatch match, DbMatchEntry entry) async {
  var matchRes = await HydratedMatchCache().get(match);
  if(matchRes.isErr()) {
    throw ArgumentError();
  }
  var division = uspsaSport.divisions.lookupByName(entry.divisionName);
  if(division == null) {
    throw ArgumentError();
  }
  var scores = matchRes.unwrap().getScoresFromFilters(FilterSet(uspsaSport, divisions: [division]));
  return scores.entries.firstWhere((e) => e.key.memberNumber == entry.memberNumber).value.place;
}

Future<void> _matchBumpGms(AnalystDatabase db) async {
  var matches = await db.isar.dbShootingMatchs.where().anyDate()
    .filter()
    .sportNameEqualTo(uspsaSport.name)
    .sortByDate().findAll();


  Map<ShootingMatch, MatchEntry> gmBumpEligible = {};
  Map<MatchEntry, ShootingMatch> gmBumpMatches = {};
  Map<MatchEntry, List<MatchEntry>> gmsBeat = {};
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
      List<MatchEntry> gmsOver90 = [];
      for(var scoreEntry in scores.entries) {
        var entry = scoreEntry.key;
        var score = scoreEntry.value;
        if(score.place == 1) {
          winner = entry;
        }
        else if(entry.classification == uspsaGM && score.percentage >= 90) {
          gmsOver90.add(entry);
        }
        else if(score.percentage < 90) {
          break;
        }
      }

      if(gmsOver90.length >= 3 && winner != null && winner.classification != uspsaGM) {
        gmBumpEligible[match] = winner;
        gmBumpMatches[winner] = match;
        gmsBeat[winner] = gmsOver90;
      }
    }
  }

  var project = (await db.getRatingProjectByName("L2s Main"))!;
  Map<MatchEntry, DbShooterRating> ratings = {};

  await project.dbGroups.load();

  for(var entry in [...gmBumpEligible.values, ...gmsBeat.values.flattened]) {
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
    var over = gmsBeat[entry];
    var rating = ratings[entry];
    print("${entry.name} at ${match?.name} in ${entry.division}");
    print("\tWas ${entry.classification} at match");
    print("\tIs now ${rating?.lastClassification ?? "(unknown class)"} with ${rating?.rating.round() ?? "(unrated)"} Elo");
    print("\tBeat these GMs over 90%:");
    for(var gm in over!) {
      var gmRating = ratings[gm];
      double? eloAtMatch;
      if(gmRating != null) {
        eloAtMatch = EloShooterRating.wrapDbRating(gmRating!).ratingAtEvent(match!, null);
      }
      print("\t\t${gm.name} (${gm.memberNumber}, ${eloAtMatch?.round() ?? "(unknown)"} Elo at match, ${gmRating?.rating.round() ?? "(unrated)"} Elo today)");
    }
    print("\n");
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
  _log.d("Starting oneoffDbAnalyses");
  // await _matchChronoCounts();
}

// Future<void> _matchChronoCounts() async {
//   await MatchCache().ready;
//   Map<MatchLevel, List<PracticalMatch>> matches = {};
//   Map<MatchLevel, int> matchCounts = {};
//   Map<MatchLevel, int> chronoCounts = {};
//   await RatingProjectManager().ready;

//   var project = RatingProjectManager().loadProject("L2s Main");
//   for(var url in project!.matchUrls) {
//     var match = await MatchCache().getMatchImmediate(url);
//     matches.addToList(match!.level ?? MatchLevel.I, match);
//   }

//   for(var match in matches.values.flattened) {
//     var date = match.date!;
//     if(match.name!.toLowerCase().contains("national")) {
//       match.level = MatchLevel.III;
//     }
//     else if(match.level == MatchLevel.I || match.level == null) {
//       match.level = MatchLevel.II;
//     }
//     matchCounts.increment(match.level ?? MatchLevel.I);
//     if(match.hasChrono) {
//       chronoCounts.increment(match.level ?? MatchLevel.I);
//     }
//   }

//   for(var level in MatchLevel.values) {
//     if(matchCounts[level] == null || matchCounts[level] == 0) continue;
//     _log.i("Level ${level.name}: ${chronoCounts[level]}/${matchCounts[level]}");
//   }

//   File f = File("chrono_by_match.csv");
//   String csv = "Match Name,Match Date,Probable Match Level,Has Chrono\n";
//   for(var level in MatchLevel.values) {
//     if(matches[level] == null || matches[level]!.isEmpty) continue;
//     for(var match in matches[level]!) {
//       csv += '"${match.name}",${programmerYmdFormat.format(match.date!)},${match.level?.name ?? MatchLevel.I.name},${match.hasChrono}\n';
//     }
//   }
//   f.writeAsStringSync(csv);
//   _log.i("Analysis complete: wrote ${f.path}");
// }

// Future<void> _lady90PercentFinishes(AnalystDatabase db) async {
//   var startTime = DateTime.now();
//   var matches = await db.matchDb.dbShootingMatchs
//     .filter()
//     .shootersElement((q) =>
//       q.femaleEqualTo(true)
//       .and()
//       .precalculatedScore((q) => q.percentageGreaterThan(90, include: true))
//     )
//     .sortByDate()
//     .findAll();

//   var buf = StringBuffer();
//   for(var match in matches) {
//     for(var shooter in match.shooters) {
//       if(shooter.female && (shooter.precalculatedScore?.percentage ?? 0) >= 90) {
//         var competitorCount = match.shooters.where((e) => e.divisionName == shooter.divisionName).length;
//         buf.writeln('${match.date},${match.eventName.replaceAll(',', ' ')},${match.matchLevelName},${shooter.firstName},${shooter.lastName},${shooter.divisionName},${shooter.precalculatedScore?.percentage},${shooter.precalculatedScore?.place},${competitorCount}');
//       }
//     }
//   }

//   File f = File("female_90_percent.csv");
//   f.writeAsString(buf.toString());
//   _log.i("Analysis complete: wrote ${f.path} in ${DateTime.now().difference(startTime).inMilliseconds}ms");
// }

class MatchHeat {
  MatchPointer matchPointer;
  double topTenPercentAverageRating;
  double medianRating;
  double classificationStrength;
  int ratedCompetitorCount;
  int unratedCompetitorCount;

  int get competitorCount => ratedCompetitorCount + unratedCompetitorCount;

  MatchHeat({
    required this.matchPointer,
    required this.topTenPercentAverageRating,
    required this.medianRating,
    required this.classificationStrength,
    required this.ratedCompetitorCount,
    required this.unratedCompetitorCount,
  });

  @override
  String toString() {
    return
"""MatchHeat(
  topTenPercentAverageRating: $topTenPercentAverageRating,
  medianRating: $medianRating,
  classificationStrength: $classificationStrength,
  ratedCompetitorCount: $ratedCompetitorCount,
  unratedCompetitorCount: $unratedCompetitorCount,
)""";
  }
}

Future<Map<MatchPointer, MatchHeat>> calculateMatchHeat(AnalystDatabase db, DbRatingProject project, {void Function(MatchPointer, MatchHeat)? heatCallback}) async {
  var sport = project.sport;

  Map<MatchPointer, MatchHeat> matchHeat = {};

  // For each match, calculate the match heat.
  for(var ptr in project.matchPointers) {
    var dbMatch = await db.getMatchByAnySourceId(ptr.sourceIds);
    if(dbMatch == null) {
      _log.w("Match not found: ${ptr.name}");
      continue;
    }
    var matchRes = await HydratedMatchCache().get(dbMatch);
    if(matchRes.isErr()) {
      _log.w("Error hydrating match: ${matchRes.unwrapErr()}");
      continue;
    }
    var match = matchRes.unwrap();
    Map<MatchEntry, double> shooterRatings = {};
    int ratedCompetitorCount = 0;
    int unratedCompetitorCount = 0;
    List<double> topTenPercentAverageRatings = [];
    List<double> medianRatings = [];
    List<double> classificationStrengths = [];

    // For each division, find ratings for all rated competitors, ignoring divisions with fewer than 5 competitors.
    for(var division in sport.divisions.values) {
      var groupRes = await project.groupForDivision(division);

      if(groupRes.isErr()) {
        _log.w("Error getting group for division ${division.name}: ${groupRes.unwrapErr()}");
        continue;
      }
      var group = groupRes.unwrap();
      if(group == null) {
        _log.w("No group found for division: ${division.name}");
        continue;
      }

      var divisionEntries = match.filterShooters(divisions: [division]);
      if(divisionEntries.length < 5) {
        continue;
      }
      for(var entry in divisionEntries) {
        var rating = await db.maybeKnownShooter(
          project: project,
          group: group,
          memberNumber: entry.memberNumber,
          useCache: true,
          usePossibleMemberNumbers: true,
        );
        if(rating != null) {
          shooterRatings[entry] = rating.rating;
          ratedCompetitorCount++;
        }
        else {
          unratedCompetitorCount++;
        }
      }
    }

    // For each division, calculate divisional heat.
    for(var division in sport.divisions.values) {
      var scores = match.getScoresFromFilters(FilterSet(sport, divisions: [division]));
      if(scores.length < 5) {
        continue;
      }

      var competitors = scores.keys.toList();
      var ratedCompetitors = competitors.where((e) => shooterRatings.containsKey(e));

      // Get the average rating of the top 10% of rated competitors.
      var topTenPercentAverageRating = ratedCompetitors
        .map((e) => shooterRatings[e]!)
        .take(max(1, (ratedCompetitors.length * 0.1).round()))
        .average;

      // Get the median rating of rated competitors.
      var medianRating = ratedCompetitors
        .map((e) => shooterRatings[e]!)
        .sorted((a, b) => a.compareTo(b))
        .toList()[ratedCompetitors.length ~/ 2];

      // Get the average classification strength of all competitors.
      var classificationStrength = competitors
        .map((e) => sport.ratingStrengthProvider?.strengthForClass(e.classification))
        .whereNotNull()
        .average;

      topTenPercentAverageRatings.add(topTenPercentAverageRating);
      medianRatings.add(medianRating);
      classificationStrengths.add(classificationStrength);
    }

    if(topTenPercentAverageRatings.isEmpty) {
      _log.w("No top ten percent average ratings for match: ${ptr.name}");
      continue;
    }

    // The match heat is (for now) the average of divisional heats.
    matchHeat[ptr] = MatchHeat(
      matchPointer: ptr,
      topTenPercentAverageRating: topTenPercentAverageRatings.average,
      medianRating: medianRatings.average,
      classificationStrength: classificationStrengths.average,
      ratedCompetitorCount: ratedCompetitorCount,
      unratedCompetitorCount: unratedCompetitorCount,
    );
    heatCallback?.call(ptr, matchHeat[ptr]!);
  }

  return matchHeat;
}
