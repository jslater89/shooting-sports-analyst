/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/fantasy.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa_utils/uspsa_fantasy_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/server/fantasy/cli/show_valid_groups.dart';
import 'package:shooting_sports_analyst/server/fantasy/cli/util.dart';
import 'package:shooting_sports_analyst/util.dart';

Future<void> lookupCompetitorScores(Console console, List<MenuArgumentValue> arguments) async {
  var db = AnalystDatabase();
  var config = ConfigLoader().config;
  var project = await db.getRatingProjectById(config.ratingsContextProjectId ?? -1);
  if(project == null) {
    console.print("No ratings context found for id ${config.ratingsContextProjectId}");
    return;
  }

  if(arguments.length < 2) {
    console.print("Invalid arguments: ${arguments.map((e) => e.value).join(", ")}");
    return;
  }
  if(!arguments[0].canGetAs<String>()) {
    console.print("Invalid group: ${arguments[0].value}");
    return;
  }
  if(!arguments[1].canGetAs<String>()) {
    console.print("Invalid search: ${arguments[1].value}");
    return;
  }

  var groups = resolveRatingGroup(arguments[0].getAs<String>(), project);
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
  var group = groups.first;
  var nameSearch = arguments[1].getAs<String>();

  var ratings = db.findShooterRatingsSync(project: project, group: group, name: nameSearch);
  if(ratings.isEmpty) {
    console.print("No ratings found for $nameSearch in $group");
    return;
  }

  DbShooterRating? ofInterest;
  if(ratings.length == 1) {
    ofInterest = ratings.first;
  }
  else {
    var table = Table();
    table.insertColumn(header: "Select");
    table.insertColumn(header: "Name");
    table.insertColumn(header: "Member Number");
    table.insertColumn(header: "Original Member Number");
    for(int i = 0; i < min(ratings.length, 10); i++) {
      table.insertRow([i + 1, ratings[i].name, ratings[i].memberNumber, ratings[i].originalMemberNumber]);
    }
    while(true) {
      console.print(table.render());
      console.print("Enter a 'select' number, or 'B' to cancel");
      console.printNoBreak("> ");
      var input = console.readLine(cancelOnBreak: true, cancelOnEOF: true);
      if(input == null) {
        console.print("Invalid selection");
      }
      else if(input.toLowerCase() == "b") {
        return;
      }
      else {
        var selection = int.tryParse(input);
        if(selection == null) {
          console.print("Invalid selection: not a number");
        }
        else if(selection < 1 || selection > ratings.length) {
          console.print("Invalid selection: out of range");
        }
        else {
          ofInterest = ratings[selection - 1];
          break;
        }
      }
    }
  }

  console.print("Looking up fantasy history for ${ofInterest.name}");
  _printFantasyHistory(console, db, project, group, ofInterest);
}

void _printFantasyHistory(Console console, AnalystDatabase db, DbRatingProject project, RatingGroup group, DbShooterRating rating) {
  var playerId = FantasyPlayer.idFromEntities(
    sport: project.sport,
    group: group,
    shooter: rating,
    project: project,
  );
  var player = db.getPlayerByIdSync(playerId);
  if(player == null) {
    console.print("No player found for $rating");
    return;
  }
  var performances = player.matchPerformances.toList();
  // Ignore the standard offseason of December, January, and February
  performances = performances.where((e) => e.matchDate.month >= 3 && e.matchDate.month <= 11).toList();
  performances.sort((a, b) => b.matchDate.compareTo(a.matchDate));

  Map<DateTime, PlayerMatchPerformance> monthlyBests = {};
  Map<int, List<PlayerMatchPerformance>> performancesByYear = {};
  Map<int, List<PlayerMatchPerformance>> usedPerformancesByYear = {};
  Map<int, int> countsPerYear = {};
  Map<PlayerMatchPerformance, bool> isMonthlyBest = {};
  for(var performance in performances) {
    var monthDate = DateTime(performance.matchDate.year, performance.matchDate.month, 1);
    performance.points = performance.getScore(calculator: USPSAFantasyScoringCalculator(), weights: FantasyScoringCategory.defaultCategoryPoints).points;
    countsPerYear.increment(performance.matchDate.year);
    performancesByYear.addToList(performance.matchDate.year, performance);
    if(monthlyBests[monthDate] == null) {
      monthlyBests[monthDate] = performance;
      isMonthlyBest[performance] = true;
      usedPerformancesByYear.addToList(performance.matchDate.year, performance);
    }
    else {
      if(performance.points > monthlyBests[monthDate]!.points) {
        isMonthlyBest[monthlyBests[monthDate]!] = false;
        isMonthlyBest[performance] = true;
        monthlyBests[monthDate] = performance;
        usedPerformancesByYear.addToList(performance.matchDate.year, performance);
      }
    }
  }

  Table table = Table();
  table.insertColumn(header: "Date");
  table.insertColumn(header: "Match Name");
  table.insertColumn(header: "Score");
  table.insertColumn(header: "Used?");

  int? year;

  for(var performance in performances) {
    if(performance.matchDate.year != year) {
      year = performance.matchDate.year;
      var averageScore = usedPerformancesByYear[year]!.map((e) => e.points).average;
      table.insertRow([
        "($year)",
        "(${countsPerYear[year]} matches)",
        "(${averageScore.toStringAsFixed(1)})",
        "",
      ]);
    }
    var trimmedMatchName = performance.matchName.length > 30 ? performance.matchName.substring(0, 30) + "..." : performance.matchName;
    var used = isMonthlyBest[performance] ?? false;
    table.insertRow([
      programmerYmdFormat.format(performance.matchDate),
      trimmedMatchName,
      performance.points.toStringAsFixed(1),
      used ? "✓" : "",
    ]);
  }
  console.print("Fantasy history for ${rating.name}:");
  console.print(table.render());
}
