import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class WinningPointsByDateCommand extends DbOneoffCommand {
  WinningPointsByDateCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "WPD";
  @override
  final String title = "Winning Points By Date";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _winningPointsByDate(db, console);
  }
}

Future<void> _winningPointsByDate(AnalystDatabase db, Console console) async {
  var project = await db.getRatingProjectByName("L2s Main");
  if(project == null) {
    console.print("L2s Main project not found");
    return;
  }

  var sport = project.sport;

  // Map of date to map of division name to list of winning percent points.
  Map<DateTime, Map<String, List<double>>> winningPercentPoints = {};

  for(var pointer in project.matchPointers) {
    var matchRes = await pointer.getDbMatch(db);
    if(matchRes.isErr()) {
      console.print("Error getting match: ${matchRes.unwrapErr()}");
      continue;
    }
    var match = matchRes.unwrap();
    if(!match.sport.hasDivisions) {
      console.print("Sport has no divisions: ${match.eventName}");
      return;
    }
    var hydratedMatchRes = await match.hydrate(useCache: true);
    if(hydratedMatchRes.isErr()) {
        console.print("Error hydrating match: ${hydratedMatchRes.unwrapErr()}");
      continue;
    }
    var hydratedMatch = hydratedMatchRes.unwrap();
    int pointsAvailable = 0;
    for(var stage in hydratedMatch.stages) {
      pointsAvailable += stage.maxPoints;
    }
    if(pointsAvailable == 0) {
      console.print("Match has no points: ${match.eventName}");
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
        console.print("${match.eventName} ${division.name}: ${points}");
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
