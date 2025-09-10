/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/fantasy.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa_utils/uspsa_fantasy_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/util.dart';

Future<void> calculateAnnualStats(Console console, List<MenuArgumentValue> arguments) async {
  if(arguments.length < 2) {
    console.print("Invalid arguments: ${arguments.map((e) => e.value).join(", ")}");
    return;
  }
  if(!arguments.first.canGetAs<int>()) {
    console.print("Invalid year: ${arguments.first.value}");
    return;
  }
  if(!arguments.last.canGetAs<int>()) {
    console.print("Invalid ratings context: ${arguments.last.value}");
    return;
  }
  var year = arguments.first.getAs<int>();
  var db = AnalystDatabase();
  var project = await db.getRatingProjectById(arguments.last.getAs<int>());
  if(project == null) {
    console.print("No ratings context found for id ${arguments.last.value}");
    return;
  }
  console.print("Calculating annual fantasy stats for $year in ${project.name}");
  List<MatchPointer> matches = [];
  for(var match in project.matchPointers) {
    if(match.date?.year == year) {
      matches.add(match);
    }
  }
  console.print("Found ${matches.length} matches");

  // Objectives:
  // - For each match...
  //   - For each group...
  //     - calculateFantasyStats for the match
  //     - For each player in the group...
  //       - Find or create a fantasy player.
  //       - Find or create a [PlayerMatchPerformance] for the match/player.

  // TODO: let leagues specify which groups to use
  var groups = project.groups;

  // TODO: let leagues specify which calculator to use
  var calculator = USPSAFantasyScoringCalculator();

  var progressBar = LabeledProgressBar(maxValue: matches.length, canHaveErrors: true, initialLabel: matches.first.name);
  Map<Id, FantasyPlayer> players = {};
  Map<FantasyPlayer, List<PlayerMatchPerformance>> performancesByPlayer = {};
  List<PlayerMatchPerformance> performances = [];
  int totalPerformances = 0;

  for(var match in matches) {
    progressBar.tick(match.name);
    Map<DbShooterRating, DbFantasyStats>? stats = {};
    String? error;

    (stats, error) = await _calculateFantasyStatsByGroup(
      db: db,
      project: project,
      matchPointer: match,
      calculator: calculator,
      groups: groups,
    );
    if(error != null) {
      progressBar.error(error);
      continue;
    }

    int myPerformances = 0;

    for(var rating in stats!.keys) {
      var fantasyPlayer = await db.getPlayerFor(
        rating: rating,
        project: project,
        group: groups.first,
        createIfMissing: true,
        translateIpscUuids: true,
      );
      if(fantasyPlayer == null) {
        progressBar.error("No fantasy player found or created for $rating");
        continue;
      }
      var existingPlayer = players[fantasyPlayer.id];
      if(existingPlayer != null) {
        fantasyPlayer = existingPlayer;
      }
      else {
        players[fantasyPlayer.id] = fantasyPlayer;
      }
      var performance = PlayerMatchPerformance.fromEntities(
        player: fantasyPlayer,
        match: match,
        stats: stats[rating]!,
      );
      performances.add(performance);
      performancesByPlayer.addToList(fantasyPlayer, performance);
      totalPerformances += 1;
      if(rating.originalMemberNumber.endsWith("102675")) {
        myPerformances += 1;
        progressBar.error("Found me: ${fantasyPlayer.name} ${fantasyPlayer.groupUuid} ${fantasyPlayer.hashCode}: $myPerformances match(es)");
      }
    }
  }
  progressBar.complete();

  console.print("Found ${players.length} players and $totalPerformances performances");

  // List<String> performancesCsv = ["Player Name, Player Number, GroupMatch Name, Match Date, Total Points, ${calculator.scoringCategories.map((e) => e.toString()).join(",")}"];

  console.print("Storing performances");

  int written = db.saveMatchPerformancesSync(performances);
  console.print("Wrote $written performances");
}

/// Returns an error message if there is an error, or null if there is no error.
Future<(Map<DbShooterRating, DbFantasyStats>?, String?)> _calculateFantasyStatsByGroup({
  required AnalystDatabase db,
  required DbRatingProject project,
  required MatchPointer matchPointer,
  required FantasyScoringCalculator calculator,
  required List<RatingGroup> groups,
}) async {
  var dbMatch = db.getMatchByAnySourceIdSync(matchPointer.sourceIds);
  if(dbMatch == null) {
    return (null, "No match found for ${matchPointer.name} at ${matchPointer.sourceIds.firstOrNull}");
  }
  var hydratedMatch = dbMatch.hydrate(useCache: true);
  if(hydratedMatch.isErr()) {
    return (null, "Error hydrating match: ${hydratedMatch.unwrapErr()}");
  }
  var match = hydratedMatch.unwrap();

  Map<DbShooterRating, DbFantasyStats> statsByRating = {};
  for(var group in groups) {
    var entries = match.applyFilterSet(group.filters);
    var stats = calculator.calculateFantasyStats(match, byDivision: false, entries: entries);

    for(var entry in stats.keys) {
      var rating = await db.maybeKnownShooter(project: project, group: group, memberNumber: entry.memberNumber);
      if(rating == null) {
        continue;
      }
      statsByRating[rating] = stats[entry]!;
    }
  }

  return (statsByRating, null);
}
