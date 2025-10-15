import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class MatchBumpGmsCommand extends DbOneoffCommand {
  MatchBumpGmsCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "GM";
  @override
  final String title = "Match Bump GMs";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _matchBumpGms(db, console);
  }
}

Future<void> _matchBumpGms(AnalystDatabase db, Console console) async {
  console.print("Loading matches...");
  var matches = db.isar.dbShootingMatchs.where().anyDate()
    .filter()
    .sportNameEqualTo(uspsaSport.name)
    .sortByDate().findAllSync();


  Map<ShootingMatch, MatchEntry> gmBumpEligible = {};
  Map<MatchEntry, ShootingMatch> gmBumpMatches = {};
  Map<MatchEntry, List<MatchEntry>> gmsBeat = {};
  console.print("Searching for eligible GM bumps...");
  var matchProgressBar = LabeledProgressBar(maxValue: matches.length);
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
    matchProgressBar.tick("${dbMatch.eventName}");
  }
  matchProgressBar.complete();

  var project = (await db.getRatingProjectByName("L2s Main"))!;
  Map<MatchEntry, DbShooterRating> ratings = {};

  await project.dbGroups.load();

  var ratingLookupProgressBar = LabeledProgressBar(
    maxValue: [...gmBumpEligible.values, ...gmsBeat.values.flattened].length,
    initialLabel: "Looking up ratings...",
  );
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
    ratingLookupProgressBar.tick();
  }
  ratingLookupProgressBar.complete();

  console.clearScreen();
  console.print("Eligible for GM bumps: ");
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

  double minimumEloAtMatch = 1e20;
  double maximumEloAtMatch = 0;
  double minimumEloToday = 1e20;
  double maximumEloToday = 0;
  List<double> elosAtMatch = [];
  List<double> elosToday = [];
  List<double> beatenElos = [];
  int unratedAtMatch = 0;
  int currentlyGM = 0;
  for(var bumpEntry in bumpEligible) {
    var entry = bumpEntry;
    var match = gmBumpMatches[entry];
    var over = gmsBeat[entry];
    var rating = ratings[entry];
    if(rating == null) {
      continue;
    }
    var eloToday = rating.rating;
    minimumEloToday = min(minimumEloToday, eloToday);
    maximumEloToday = max(maximumEloToday, eloToday);
    elosToday.add(eloToday);
    var eloAtMatch = EloShooterRating.wrapDbRating(rating).ratingAtEvent(match!, null);
    if(eloAtMatch != null) {
      minimumEloAtMatch = min(minimumEloAtMatch, eloAtMatch);
      maximumEloAtMatch = max(maximumEloAtMatch, eloAtMatch);
      elosAtMatch.add(eloAtMatch);
    }
    else {
      unratedAtMatch += 1;
    }
    if(rating.lastClassification == uspsaGM) {
      currentlyGM += 1;
    }
    console.print("${entry.name} at ${match.name} in ${entry.division}");
    console.print("\tWas ${entry.classification} with ${eloAtMatch?.round()} Elo at match");
    console.print("\tIs now ${rating.lastClassification ?? "(unknown class)"} with ${eloAtMatch?.round() ?? "(unknown)"} Elo");
    console.print("\tBeat these GMs over 90%:");
    for(var gm in over!) {
      var gmRating = ratings[gm];
      double? eloAtMatch;
      if(gmRating != null) {
        beatenElos.add(gmRating.rating);
        eloAtMatch = EloShooterRating.wrapDbRating(gmRating).ratingAtEvent(match, null);
      }
      console.print("\t\t${gm.name} (${gm.memberNumber}, ${eloAtMatch?.round() ?? "(unknown)"} Elo at match, ${gmRating?.rating.round() ?? "(unrated)"} Elo today)");
    }
    console.print("\n");
  }

  console.print("Collective stats for bumped shooters:");
  console.print("Min-max Elo at match: ${minimumEloAtMatch.round()} to ${maximumEloAtMatch.round()}");
  console.print("Average Elo at match: ${elosAtMatch.average.round()}");
  console.print("Min-max Elo today: ${minimumEloToday.round()} to ${maximumEloToday.round()}");
  console.print("Average Elo today: ${elosToday.average.round()}");
  console.print("Average Elo of GMs beaten: ${beatenElos.average.round()}");
  console.print("Unrated at match: ${unratedAtMatch}");
  console.print("Currently GM: ${currentlyGM}");
  console.print("Total eligible: ${bumpEligible.length}");
}
