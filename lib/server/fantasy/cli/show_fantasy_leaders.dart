/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:dart_console/dart_console.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/fantasy.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa_utils/uspsa_fantasy_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/server/fantasy/cli/show_valid_groups.dart';
import 'package:shooting_sports_analyst/server/fantasy/cli/util.dart';
import 'package:shooting_sports_analyst/util.dart';

Future<void> showFantasyScoringLeaders(Console console, List<MenuArgumentValue> arguments) async {
  var start = DateTime.now();
  var db = AnalystDatabase();
  var config = ConfigLoader().config;
  var projectId = config.ratingsContextProjectId ?? -1;
  var project = await db.getRatingProjectById(projectId);
  if(project == null) {
    console.print("No ratings context found for id $projectId");
    return;
  }

  if(arguments.length < 2) {
    console.print("Invalid arguments: ${arguments.map((e) => e.value).join(", ")}");
    return;
  }
  if(!arguments[1].canGetAs<int>()) {
    console.print("Invalid year: ${arguments.first.value}");
    return;
  }
  if(!arguments[0].canGetAs<String>()) {
    console.print("Invalid group: ${arguments.last.value}");
    return;
  }

  int? month;
  bool allMonths = false;
  if(arguments.length >= 3) {
    bool hasArgument = false;
    var monthValue = arguments[2].getAs<String>();
    if(monthValue.toLowerCase() == "all") {
      allMonths = true;
      hasArgument = true;
    }
    else {
      var month = int.tryParse(monthValue);
      if(month == null) {
        console.print("Invalid month: ${arguments[2].value}");
        return;
      }
      month = month;
      hasArgument = true;
    }

    if(!hasArgument) {
      console.print("Invalid month: ${arguments[2].value}");
      return;
    }
  }

  var year = arguments[1].getAs<int>();
  var group = arguments[0].getAs<String>();

  var groups = resolveRatingGroup(group, project);
  if(groups.isEmpty) {
    console.print("No groups found for: ${arguments[0].value}");
    console.print("Use a UUID from this list:");
    printValidGroupsTable(console, project);
    return;
  }
  else if(groups.length > 1) {
    console.print("Multiple groups found for: ${arguments[0].value}");
    console.print("Use a UUID from this list:");
    printValidGroupsTable(console, project);
    return;
  }
  var groupUuid = groups.first.uuid;

  if(allMonths) {
    for(var month = 3; month <= 11; month++) {
      _calculateForDates(
        year: year,
        month: month,
        groupUuid: groupUuid,
        projectId: projectId,
        console: console,
        db: db,
        topN: 3,
      );
    }
  }
  else {
    _calculateForDates(
      year: year,
      month: month,
      groupUuid: groupUuid,
      projectId: projectId,
      console: console,
      db: db,
    );
  }

  var end = DateTime.now();
  console.print("Time taken: ${(end.difference(start).inMilliseconds / 1000).toStringAsFixed(3)} seconds");
}

Future<void> _calculateForDates({
  required int year,
  int? month,
  required String groupUuid,
  required int projectId,
  required Console console,
  required AnalystDatabase db,
  int topN = 10,
}) async {
  var startDate = DateTime(year, 1, 1);
  var endDate = DateTime(year + 1).subtract(const Duration(seconds: 1));
  if(month != null) {
    startDate = DateTime(year, month, 1);
    endDate = DateTime(year, month + 1).subtract(const Duration(seconds: 1));
  }

  console.print("Getting performances for $year${month != null ? "-$month" : ""} $groupUuid");
  var performances = db.getMatchPerformancesForProjectGroupIdsSync(
    projectId: projectId,
    groupUuid: groupUuid,
    after: startDate,
    before: endDate,
  );
  console.print("Found ${performances.length} performances, sorting by player");

  Map<Id, List<PlayerMatchPerformance>> performancesByPlayer = {};
  for(var performance in performances) {
    performancesByPlayer.addToList(performance.playerId, performance);
  }

  var calculator = USPSAFantasyScoringCalculator();

  console.print("Calculating monthly bests");
  Map<Id, int> totalAppearances = {};
  Map<Id, Map<DateTime, PlayerMatchPerformance>> bestMonthlyPerformances = {};
  for(var id in performancesByPlayer.keys) {
    var playerPerformances = performancesByPlayer[id]!;
    for(var performance in playerPerformances) {
      if(performance.matchDate.month < 3 || performance.matchDate.month > 11) {
        // Ignore the standard offseason of December, January, and February
        continue;
      }
      totalAppearances.increment(id);
      var monthDate = DateTime(performance.matchDate.year, performance.matchDate.month, 1);
      var previousBest = bestMonthlyPerformances[id]?[monthDate];
      if(previousBest == null) {
        var newScore = calculator.calculateFantasyScore(stats: performance.dbScores, pointsAvailable: FantasyScoringCategory.defaultCategoryPoints);
        performance.points = newScore.points;
        bestMonthlyPerformances[id] ??= {};
        bestMonthlyPerformances[id]![monthDate] = performance;
      }
      else {
        var newScore = calculator.calculateFantasyScore(stats: performance.dbScores, pointsAvailable: FantasyScoringCategory.defaultCategoryPoints);
        performance.points = newScore.points;
        if(newScore.points > previousBest.points) {
          bestMonthlyPerformances[id] ??= {};
          bestMonthlyPerformances[id]![monthDate] = performance;
        }
      }
    }
  }

  console.print("Summing scores");
  Map<FantasyPlayer, double> yearlyTotals = {};
  for(var id in bestMonthlyPerformances.keys) {
    var player = db.getPlayerByIdSync(id);
    if(player == null) {
      continue;
    }
    var performances = bestMonthlyPerformances[id]!.values;
    var total = performances.fold(0.0, (sum, performance) => sum + performance.points);
    yearlyTotals[player] = total;
  }

  var sortedPlayers = yearlyTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for(int i = 0; i < min(topN, sortedPlayers.length); i++) {
    var player = sortedPlayers[i].key;
    var total = sortedPlayers[i].value;
    var performances = bestMonthlyPerformances[player.id]!.values.toList();
    performances.sort((a, b) => b.matchDate.compareTo(a.matchDate));
    String parenthetical;
    if(month == null) {
      parenthetical = "(${(total / 8).toStringAsFixed(1)} per month, ${performances.length}/8 months, ${totalAppearances[player.id]!} total matches)";
    }
    else {
      parenthetical = "(${totalAppearances[player.id]!} total matches)";
    }
    console.print("${i+1}. ${player.name} - ${total.toStringAsFixed(1)} $parenthetical");
    for(var performance in performances) {
      console.print("    ${programmerYmdFormat.format(performance.matchDate)} - ${performance.matchName} - ${performance.points.toStringAsFixed(1)}");
    }
  }
}
