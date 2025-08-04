// ignore_for_file: unused_local_variable, unused_element
// ignore_for_file: unused_import

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:data/stats.dart' show WeibullDistribution;
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/standardized_maximum_scaler.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/classifier_import.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/icore_export_converter.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

SSALogger _log = SSALogger("DbOneoffs");

Future<void> oneoffDbAnalyses(AnalystDatabase db) async {
  // await _howGoodIsTomCastro(db);
  // await _matchBumpGms(db);
  // await _addMemberNumbersToMatches(db);
  // await _doesMyQueryWork(db);

  // var project = (await db.getRatingProjectByName("L2s Main"))!;
  //await calculateMatchHeat(db, project);

  // await _analyzeIcoreDump(File("/home/jay/Downloads/masterScores.json"));
  // await _importIcoreDump(File("/home/jay/Documents/tmp/icore-stats/masterScores-20250723.json"));
  // await _winningPointsByDate();

  // await _stageSizeAnalysis(db);
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
        eloAtMatch = EloShooterRating.wrapDbRating(gmRating).ratingAtEvent(match!, null);
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

Future<void> _analyzeIcoreDump(File file) async {
  var masterScores = IcoreClassifierExport.fromFile(file);
  var analystScores = masterScores.toAnalystScores();

  Map<DateTime, Map<String, List<ClassifierScore>>> scoresByDateDivision = {};
  for(var score in analystScores) {
    var monthDate = DateTime(score.date.year, score.date.month, 1);
    var monthMap = scoresByDateDivision[monthDate] ?? {};
    monthMap.addToList(score.division, score);
    scoresByDateDivision[monthDate] = monthMap;
  }

  for(var date in scoresByDateDivision.keys.sorted((a, b) => b.compareTo(a))) {
    var monthMap = scoresByDateDivision[date]!;
    print("${programmerYmdFormat.format(date)}:");
    for(var division in monthMap.keys.sorted((a, b) => a.compareTo(b))) {
      var scores = monthMap[division]!;
      Map<String, List<ClassifierScore>> scoresByClassifier = {};
      for(var score in scores) {
        scoresByClassifier.addToList(score.classifierCode, score);
      }
      var withEnoughScores = scoresByClassifier.values.where((e) => e.length >= 4);
      print("\t${division}: ${scores.length} (${withEnoughScores.length} eligible)");
    }
  }
}

Future<void> _importIcoreDump(File file) async {
  var masterScores = IcoreClassifierExport.fromFile(file);
  var analystScores = masterScores.toAnalystScores();
  var db = AnalystDatabase();

  await db.isar.writeTxn(() async {
    int deleted = await db.isar.dbShootingMatchs.filter()
      .eventNameStartsWith("ICORE Classifier Analysis")
      .deleteAll();
    _log.i("Deleted ${deleted} matches");
  });

  var importer = ClassifierImporter(
    sport: icoreSport,
    duration: PseudoMatchDuration.month,
    minimumScoreCount: 4,
    matchNamePrefix: "ICORE Classifier Analysis",
  );
  var matchesResult = importer.import(analystScores);
  if(matchesResult.isErr()) {
    _log.w("Error importing scores: ${matchesResult.unwrapErr()}");
    return;
  }
  var matches = matchesResult.unwrap();
  _log.i("Imported ${matches.length} matches");
  int dbInserts = 0;
  for(var match in matches) {
    var saveResult = await db.saveMatch(match);
    if(saveResult.isOk()) {
      dbInserts++;
    }
    else {
      _log.w("Error saving match: ${saveResult.unwrapErr()}");
    }
  }
  _log.i("Saved ${dbInserts} matches to DB");
}

Future<void> _winningPointsByDate() async {
  var db = AnalystDatabase();
  var project = await db.getRatingProjectByName("L2s Main");
  if(project == null) {
    _log.e("L2s Main project not found");
    return;
  }

  var sport = project.sport;

  // Map of date to map of division name to list of winning percent points.
  Map<DateTime, Map<String, List<double>>> winningPercentPoints = {};

  for(var pointer in project.matchPointers) {
    var matchRes = await pointer.getDbMatch(db);
    if(matchRes.isErr()) {
      _log.w("Error getting match: ${matchRes.unwrapErr()}");
      continue;
    }
    var match = matchRes.unwrap();
    if(!match.sport.hasDivisions) {
      _log.w("Sport has no divisions: ${match.eventName}");
      return;
    }
    var hydratedMatchRes = await match.hydrate(useCache: true);
    if(hydratedMatchRes.isErr()) {
      _log.w("Error hydrating match: ${hydratedMatchRes.unwrapErr()}");
      continue;
    }
    var hydratedMatch = hydratedMatchRes.unwrap();
    int pointsAvailable = 0;
    for(var stage in hydratedMatch.stages) {
      pointsAvailable += stage.maxPoints;
    }
    if(pointsAvailable == 0) {
      _log.w("Match has no points: ${match.eventName}");
      continue;
    }

    Set<Division> divisions = {};
    for(var entry in hydratedMatch.shooters) {
      if(entry.division != null) {
        divisions.add(entry.division!);
      }
    }

    for(var division in divisions) {
      var scores = hydratedMatch.getScoresFromFilters(FilterSet(sport, divisions: [division], mode: FilterMode.or, empty: true));
      if(scores.length < 3) {
        // skip matches with less than 3 shooters
        continue;
      }
      var firstPlace = scores.values.firstWhereOrNull((e) => e.place == 1);
      if(firstPlace != null) {
        Map<MatchStage, int> stageMax = {};
        for(var s in firstPlace.stageScores.keys) {
          if(s.scoring is PointsScoring && sport.type.isHitFactor) {
            var bestPoints = 0;
            for(var score in scores.values.where((e) => e.shooter.division == division)) {
              if(score.stageScores[s] != null && score.stageScores[s]!.score.points > bestPoints) {
                bestPoints = score.stageScores[s]!.score.points;
              }
            }
            stageMax[s] = bestPoints;
          }
        }

        var points = firstPlace.percentTotalPointsWithSettings(scoreDQ: true, countPenalties: true, stageMaxPoints: stageMax);
        var date = match.date;
        winningPercentPoints[date] ??= {};
        winningPercentPoints[date]!.addToList(division.name, points);
        _log.i("${match.eventName} ${division.name}: ${points}");
      }
    }
  }

  for(var division in sport.divisions.values) {
    List<String> csvLines = [];
    csvLines.add("Date,Winning Percent Points");
    for(var result in winningPercentPoints.entries) {
      var points = result.value[division.name];
      if(points != null) {
        for(var p in points) {
          csvLines.add("${result.key},${p}");
        }
      }
    }

    if(csvLines.isNotEmpty) {
      File f = File("/tmp/winning_percent_points_${division.name}.csv");
      f.writeAsStringSync(csvLines.join("\n"));
    }
  }
}

class _StagePointer {
  MatchPointer match;
  int stageNumber;
  int roundCount;

  _StagePointer({required this.match, required this.stageNumber, required this.roundCount});

  operator ==(Object other) {
    if(other is _StagePointer) {
      return match.sourceIds.first == other.match.sourceIds.first && stageNumber == other.stageNumber;
    }
    return false;
  }

  int get hashCode => combineHashes(match.sourceIds.first.hashCode, stageNumber.hashCode);
}

class _StagePerformance {
  _StagePointer stage;
  double place;
  double ratio;
  double ratingChange;
  bool positive;
  double positiveProportion;

  _StagePerformance({required this.stage, required this.place, required this.ratio, required this.ratingChange, required this.positive, double? positiveProportion}) :
    this.positiveProportion = positiveProportion ?? (positive ? 1 : 0);


  operator +(Object other) {
    if(other is _StagePerformance) {
      return _StagePerformance(
        stage: stage,
        place: (place + other.place),
        ratio: (ratio + other.ratio),
        ratingChange: (ratingChange + other.ratingChange),
        positive: positive && other.positive,
      );
    }
    return this;
  }

  operator /(int count) {
    return _StagePerformance(stage: stage, place: place / count, ratio: ratio / count, ratingChange: ratingChange / count, positive: positive, positiveProportion: positiveProportion / count);
  }
}

class _TotalStagePerformance {
  int count = 0;
  double place = 0;
  double placeStdDev = 0;
  double ratio = 0;
  double ratioStdDev = 0;
  double ratingChange = 0;
  double ratingChangeStdDev = 0;
  double positiveProportion = 0;

  _TotalStagePerformance();

  _TotalStagePerformance.from(List<_StagePerformance> stages) {
    count = stages.length;
    if(count == 0) {
      return;
    }
    place = stages.map((e) => e.place).average;
    ratio = stages.map((e) => e.ratio).average;
    ratingChange = stages.map((e) => e.ratingChange).average;
    positiveProportion = stages.map((e) => e.positiveProportion).average;
    placeStdDev = stages.map((e) => e.place).stdDev();
    ratioStdDev = stages.map((e) => e.ratio).stdDev();
    ratingChangeStdDev = stages.map((e) => e.ratingChange).stdDev();
  }
}

Future<void> _stageSizeAnalysis(AnalystDatabase db) async {

  final bool normalizeStageSizeCounts = false;

  var project = await db.getRatingProjectByName("L2s Main");
  if(project == null) {
    _log.e("L2s Main project not found");
    return;
  }

  var matchPointers = project.matchPointers;
  List<String> stageSizeCsvLines = ["Date, Match Name, Stage Number, Stage Size"];
  List<_StagePointer> shortCourses = [];
  List<_StagePointer> mediumCourses = [];
  List<_StagePointer> longCourses = [];
  Map<String, DbShootingMatch> matches = {};
  _log.i("Beginning stage size analysis");
  for(var pointer in matchPointers) {
    var matchRes = await pointer.getDbMatch(db);
    if(matchRes.isErr()) {
      _log.w("Error getting match: ${matchRes.unwrapErr()}");
      continue;
    }
    var match = matchRes.unwrap();
    for(var id in match.sourceIds) {
      matches[id] = match;
    }

    int shortCourseCount = 0;
    int mediumCourseCount = 0;
    int longCourseCount = 0;

    for(var stage in match.stages) {
      if(stage.minRounds > 0) {
        stageSizeCsvLines.add('${matchRes.unwrap().date},"${matchRes.unwrap().eventName}",${stage.stageId},${stage.minRounds}');
      }

      if(stage.minRounds <= 12) {
        shortCourses.add(_StagePointer(match: pointer, stageNumber: stage.stageId, roundCount: stage.minRounds));
        shortCourseCount++;
      }
      else if(stage.minRounds <= 24) {
        mediumCourses.add(_StagePointer(match: pointer, stageNumber: stage.stageId, roundCount: stage.minRounds));
        mediumCourseCount++;
      }
      else {
        longCourses.add(_StagePointer(match: pointer, stageNumber: stage.stageId, roundCount: stage.minRounds));
        longCourseCount++;
      }
    }

    int total = shortCourseCount + mediumCourseCount + longCourseCount;
    _log.v("${match.eventName}: ${shortCourseCount} short, ${mediumCourseCount} medium, ${longCourseCount} long");
  }


  _log.i("Writing ${stageSizeCsvLines.length} stage size CSV lines");
  String stageSizeCsv = stageSizeCsvLines.join("\n");
  File f = File("/tmp/stage_size_analysis.csv");
  f.writeAsStringSync(stageSizeCsv);
  _log.i("Finished writing");

  stageSizeCsvLines.clear();

  _log.i("Beginning average analysis");
  for(var group in project.groups) {
    Map<DbShooterRating, List<_StagePerformance>> stagePerformances = {};
    // Each shooter's list contains three elements, one each containing average performances for short, medium, and long courses.
    Map<DbShooterRating, List<_TotalStagePerformance>> averagePerformancesBySize = {};
    var ratingsRes = project.getRatingsSync(group);
    if(ratingsRes.isErr()) {
      _log.w("Error getting ratings: ${ratingsRes.unwrapErr()}");
      continue;
    }
    var ratings = ratingsRes.unwrap();
    int totalRatings = ratings.length;
    ratings.retainWhere((e) => e.lastSeen.isAfter(DateTime(2024, 1, 1)) && e.length >= 30);
    _log.i("Found ${ratings.length} recent-ish ratings for group ${group.name} (${totalRatings} total)");
    ratings.sort((a, b) => b.rating.compareTo(a.rating));
    for(int i = 0; i < ratings.length; i++) {
      var rating = ratings[i];

      for(var event in rating.events) {
        var match = matches[event.matchId];
        if(match == null) {
          _log.w("Match not found: ${event.matchId}");
          continue;
        }

        var stage = match.stages.firstWhereOrNull((e) => e.stageId == event.stageNumber);
        if(stage == null) {
          continue;
        }

        var stagePointer = _StagePointer(match: MatchPointer.fromDbMatch(match), stageNumber: stage.stageId, roundCount: stage.minRounds);
        var stagePerformance = _StagePerformance(stage: stagePointer, place: event.score.place.toDouble(), ratio: event.score.ratio, ratingChange: event.ratingChange, positive: event.ratingChange > 0);
        stagePerformances[rating] ??= [];
        stagePerformances[rating]!.add(stagePerformance);
      }

      List<_StagePerformance> shortCoursePerformances = [];
      List<_StagePerformance> mediumCoursePerformances = [];
      List<_StagePerformance> longCoursePerformances = [];
      int shortCourseCount = 0;
      int positiveShortCourses = 0;
        int mediumCourseCount = 0;
      int positiveMediumCourses = 0;
      int longCourseCount = 0;
      int positiveLongCourses = 0;
      // Calculate average performances for each stage size.
      for(var performance in stagePerformances[rating] ?? []) {

        if(performance.stage.roundCount <= 12) {
          shortCoursePerformances.add(performance);
          if(performance.positive) {
            positiveShortCourses++;
          }
          shortCourseCount++;
        }
        else if(performance.stage.roundCount <= 24) {
          mediumCoursePerformances.add(performance);
          if(performance.positive) {
            positiveMediumCourses++;
          }
          mediumCourseCount++;
        }
        else {
          longCoursePerformances.add(performance);
          if(performance.positive) {
            positiveLongCourses++;
          }
          longCourseCount++;
        }
      }

      averagePerformancesBySize[rating] ??= [];
      var shortCourseTotal = _TotalStagePerformance.from(shortCoursePerformances);
      averagePerformancesBySize[rating]!.add(shortCourseTotal);

      // ignore: dead_code
      if(normalizeStageSizeCounts && mediumCourseCount > shortCourseCount) {
        mediumCoursePerformances.shuffle();
        mediumCoursePerformances = mediumCoursePerformances.sublist(0, shortCourseCount);
      }

      var mediumCourseTotal = _TotalStagePerformance.from(mediumCoursePerformances);
      averagePerformancesBySize[rating]!.add(mediumCourseTotal);

      // ignore: dead_code
      if(normalizeStageSizeCounts && longCourseCount > shortCourseCount) {
        longCoursePerformances.shuffle();
        longCoursePerformances = longCoursePerformances.sublist(0, shortCourseCount);
      }

      var longCourseTotal = _TotalStagePerformance.from(longCoursePerformances);
      averagePerformancesBySize[rating]!.add(longCourseTotal);
    }

    // Write CSV lines for each competitor's averages.
    List<String> averageCsvLines = ["Shooter Number, Shooter Name, Shooter Rating, SC Count, SC Place, SC Place StdDev, SC Finish, SC Finish StdDev, SC Rating Change, SC Change StdDev, SC Positive Proportion, MC Count, MC Place, MC Place StdDev, MC Finish, MC Finish StdDev, MC Rating Change, MC Change StdDev, MC Positive Proportion, LC Count, LC Place, LC Place StdDev, LC Finish, LC Finish StdDev, LC Rating Change, LC Change StdDev, LC Positive Proportion"];
    for(var entry in averagePerformancesBySize.entries) {
      var rating = entry.key;
      var performances = entry.value;
      averageCsvLines.add('${rating.memberNumber},"${rating.name.replaceAll('"', "")}",${rating.rating},${performances[0].count}, ${performances[0].place},${performances[0].placeStdDev},${performances[0].ratio},${performances[0].ratioStdDev},${performances[0].ratingChange},${performances[0].ratingChangeStdDev},${performances[0].positiveProportion},${performances[1].count},${performances[1].place},${performances[1].placeStdDev},${performances[1].ratio},${performances[1].ratioStdDev},${performances[1].ratingChange},${performances[1].ratingChangeStdDev},${performances[1].positiveProportion},${performances[2].count},${performances[2].place},${performances[2].placeStdDev},${performances[2].ratio},${performances[2].ratioStdDev},${performances[2].ratingChange},${performances[2].ratingChangeStdDev},${performances[2].positiveProportion}');
    }

    File f = File("/tmp/stage_size_shooter_analysis_${group.name}.csv");
    f.writeAsStringSync(averageCsvLines.join("\n"));
    _log.i("Wrote ${averageCsvLines.length} average lines to ${f.path}");
  }
}
