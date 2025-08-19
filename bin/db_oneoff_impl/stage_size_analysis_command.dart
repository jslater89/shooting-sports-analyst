import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class StageSizeAnalysisCommand extends DbOneoffCommand {
  StageSizeAnalysisCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "SSA";
  @override
  final String title = "Stage Size Analysis";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _stageSizeAnalysis(db, console);
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
  double hitFactor;
  double place;
  double ratio;
  double ratingChange;
  bool positive;
  double positiveProportion;

  _StagePerformance({required this.stage, required this.hitFactor, required this.place, required this.ratio, required this.ratingChange, required this.positive, double? positiveProportion}) :
    this.positiveProportion = positiveProportion ?? (positive ? 1 : 0);


  operator +(Object other) {
    if(other is _StagePerformance) {
      return _StagePerformance(
        stage: stage,
        hitFactor: (hitFactor + other.hitFactor),
        place: (place + other.place),
        ratio: (ratio + other.ratio),
        ratingChange: (ratingChange + other.ratingChange),
        positive: positive && other.positive,
      );
    }
    return this;
  }

  operator /(int count) {
    return _StagePerformance(stage: stage, hitFactor: hitFactor / count, place: place / count, ratio: ratio / count, ratingChange: ratingChange / count, positive: positive, positiveProportion: positiveProportion / count);
  }
}

class _TotalStagePerformance {
  int count = 0;
  double hitFactor = 0;
  double hitFactorStdDev = 0;
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
    hitFactor = stages.map((e) => e.hitFactor).average;
    hitFactorStdDev = stages.map((e) => e.hitFactor).stdDev();
    place = stages.map((e) => e.place).average;
    ratio = stages.map((e) => e.ratio).average;
    ratingChange = stages.map((e) => e.ratingChange).average;
    positiveProportion = stages.map((e) => e.positiveProportion).average;
    placeStdDev = stages.map((e) => e.place).stdDev();
    ratioStdDev = stages.map((e) => e.ratio).stdDev();
    ratingChangeStdDev = stages.map((e) => e.ratingChange).stdDev();
  }
}

Future<void> _stageSizeAnalysis(AnalystDatabase db, Console console) async {

  final bool normalizeStageSizeCounts = false;

  var project = await db.getRatingProjectByName("L2s Main");
  if(project == null) {
    console.print("L2s Main project not found");
    return;
  }

  var matchPointers = project.matchPointers;
  List<String> stageSizeCsvLines = ["Date, Match Name, Stage Number, Stage Size"];
  List<_StagePointer> shortCourses = [];
  List<_StagePointer> mediumCourses = [];
  List<_StagePointer> longCourses = [];
  Map<String, DbShootingMatch> matches = {};
  console.print("Beginning stage size analysis");
  console.print("Loading ${matchPointers.length} matches and counting stages...");

  var progressBar = LabeledProgressBar(maxValue: matchPointers.length, initialLabel: "<event name>");

  for(var pointer in matchPointers) {
    var matchRes = await pointer.getDbMatch(db);
    if(matchRes.isErr()) {
      console.print("Error getting match: ${matchRes.unwrapErr()}");
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

    progressBar.tick("${match.eventName}: ${shortCourseCount} short, ${mediumCourseCount} medium, ${longCourseCount} long");
  }
  progressBar.complete();


  console.print("Writing ${stageSizeCsvLines.length} stage size CSV lines");
  String stageSizeCsv = stageSizeCsvLines.join("\n");
  File f = File("/tmp/stage_size_analysis.csv");
  f.writeAsStringSync(stageSizeCsv);
  console.print("Finished writing");

  stageSizeCsvLines.clear();

  console.print("Beginning average analysis");
  for(var group in project.groups) {
    Map<DbShooterRating, List<_StagePerformance>> stagePerformances = {};
    // Each shooter's list contains three elements, one each containing average performances for short, medium, and long courses.
    Map<DbShooterRating, List<_TotalStagePerformance>> averagePerformancesBySize = {};
    var ratingsRes = project.getRatingsSync(group);
    if(ratingsRes.isErr()) {
      console.print("Error getting ratings: ${ratingsRes.unwrapErr()}");
      continue;
    }
    var ratings = ratingsRes.unwrap();
    int totalRatings = ratings.length;
    ratings.retainWhere((e) => e.lastSeen.isAfter(DateTime(2024, 1, 1)) && e.length >= 30);
    console.print("Found ${ratings.length} recent-ish ratings for group ${group.name} (${totalRatings} total)");
    ratings.sort((a, b) => b.rating.compareTo(a.rating));
    console.print("Analyzing ${ratings.length} ratings...");
    var progressBar = LabeledProgressBar(maxValue: ratings.length, canHaveErrors: true);
    Map<String, Map<MatchEntry, RelativeMatchScore>> matchScores = {};
    for(int i = 0; i < ratings.length; i++) {
      var rating = ratings[i];

      for(var event in rating.events) {
        var match = matches[event.matchId];
        if(match == null) {
          progressBar.error("Match not found: ${event.matchId}");
          continue;
        }

        var stage = match.stages.firstWhereOrNull((e) => e.stageId == event.stageNumber);
        if(stage == null) {
          continue;
        }

        var matchScore = matchScores[match.sourceIds.first];
        if(matchScore == null) {
          var fullMatchRes = HydratedMatchCache().get(match);
          if(fullMatchRes.isErr()) {
            progressBar.error("Error hydrating match: ${fullMatchRes.unwrapErr()}");
            continue;
          }
          var fullMatch = fullMatchRes.unwrap();
          var groupFilters = group.filters;
          var scores = fullMatch.getScoresFromFilters(groupFilters);
          matchScores[match.sourceIds.first] = scores;
          matchScore = scores;
        }
        var competitorEntry = matchScore.entries.firstWhereOrNull((e) => rating.matchesShooter(e.key));
        if(competitorEntry == null) {
          progressBar.error("Competitor not found: ${rating.memberNumber}");
          continue;
        }
        var competitorScore = competitorEntry.value;
        var competitorStageScoreEntry = competitorScore.stageScores.entries.firstWhereOrNull((e) => e.key.stageId == stage.stageId);
        if(competitorStageScoreEntry == null) {
          progressBar.error("Competitor stage score not found: ${rating.memberNumber} ${stage.stageId}");
          continue;
        }
        var competitorStageScore = competitorStageScoreEntry.value;

        var stagePointer = _StagePointer(match: MatchPointer.fromDbMatch(match), stageNumber: stage.stageId, roundCount: stage.minRounds);
        var stagePerformance = _StagePerformance(stage: stagePointer, hitFactor: competitorStageScore.score.hitFactor, place: event.score.place.toDouble(), ratio: event.score.ratio, ratingChange: event.ratingChange, positive: event.ratingChange > 0);
        stagePerformances[rating] ??= [];
        stagePerformances[rating]!.add(stagePerformance);
      }

      List<_StagePerformance> shortCoursePerformances = [];
      List<_StagePerformance> mediumCoursePerformances = [];
      List<_StagePerformance> longCoursePerformances = [];
      int shortCourseCount = 0;
      int mediumCourseCount = 0;
      int longCourseCount = 0;
      // Calculate average performances for each stage size.
      for(var performance in stagePerformances[rating] ?? []) {

        if(performance.stage.roundCount <= 12) {
          shortCoursePerformances.add(performance);
          shortCourseCount++;
        }
        else if(performance.stage.roundCount <= 24) {
          mediumCoursePerformances.add(performance);
          mediumCourseCount++;
        }
        else {
          longCoursePerformances.add(performance);
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

      progressBar.tick(rating.toString());
    }
    progressBar.complete();

    // Write CSV lines for each competitor's averages.
    List<String> averageCsvLines = [
      [
        "Shooter Number",
        "Shooter Name",
        "Shooter Rating",
        "SC Count", "SC HF", "SC HF StdDev", "SC Place", "SC Place StdDev", "SC Finish", "SC Finish StdDev", "SC Rating Change", "SC Change StdDev", "SC Positive Proportion",
        "MC Count", "MC HF", "MC HF StdDev", "MC Place", "MC Place StdDev", "MC Finish", "MC Finish StdDev", "MC Rating Change", "MC Change StdDev", "MC Positive Proportion",
        "LC Count", "LC HF", "LC HF StdDev", "LC Place", "LC Place StdDev", "LC Finish", "LC Finish StdDev", "LC Rating Change", "LC Change StdDev", "LC Positive Proportion"
      ].join(", ")
    ];
    for (var entry in averagePerformancesBySize.entries) {
      var rating = entry.key;
      var performances = entry.value;
      averageCsvLines.add([
        rating.memberNumber,
        '"${rating.name.replaceAll('"', "")}"',
        rating.rating,
        // SC
        performances[0].count,
        performances[0].hitFactor,
        performances[0].hitFactorStdDev,
        performances[0].place,
        performances[0].placeStdDev,
        performances[0].ratio,
        performances[0].ratioStdDev,
        performances[0].ratingChange,
        performances[0].ratingChangeStdDev,
        performances[0].positiveProportion,
        // MC
        performances[1].count,
        performances[1].hitFactor,
        performances[1].hitFactorStdDev,
        performances[1].place,
        performances[1].placeStdDev,
        performances[1].ratio,
        performances[1].ratioStdDev,
        performances[1].ratingChange,
        performances[1].ratingChangeStdDev,
        performances[1].positiveProportion,
        // LC
        performances[2].count,
        performances[2].hitFactor,
        performances[2].hitFactorStdDev,
        performances[2].place,
        performances[2].placeStdDev,
        performances[2].ratio,
        performances[2].ratioStdDev,
        performances[2].ratingChange,
        performances[2].ratingChangeStdDev,
        performances[2].positiveProportion
      ].join(", "));
    }

    File f = File("/tmp/stage_size_shooter_analysis_${group.name}.csv");
    f.writeAsStringSync(averageCsvLines.join("\n"));
    console.print("Wrote ${averageCsvLines.length} average lines to ${f.path}");
  }
}
