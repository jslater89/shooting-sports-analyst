import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class CheckLocationProportionCommand extends DbOneoffCommand {
  CheckLocationProportionCommand(AnalystDatabase db) : super(db);

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _checkLocationProportion(db, console);
  }

  @override
  String get key => "CLP";
  @override
  String get title => "Check Location Proportion";
}

Future<void> _checkLocationProportion(AnalystDatabase db, Console console) async {
  var project = await db.getRatingProjectByName("L2s Main");
  if(project == null) {
    console.print("Project not found");
    return;
  }

  var dbIds = project.matchPointers.map((e) => e.sourceIds.first).toList();
  var matches = await db.getMatchesByAnySourceIds(dbIds);

  int matchesWith20PercentLocation = 0;
  int totalMatches = matches.length;
  for(var match in matches) {
    int locationCount = 0;
    int threshold = (match.shooters.length * 0.2).round();
    for(var s in match.shooters) {
      if(s.regionSubdivision != null) {
        locationCount++;
      }
      if(locationCount >= threshold) {
        matchesWith20PercentLocation++;
        break;
      }
    }
  }
  console.print("Matches with 20% location: ${matchesWith20PercentLocation} / ${totalMatches} (${(matchesWith20PercentLocation / totalMatches * 100).toStringAsFixed(2)}%)");

  var groups = project.groups;
  Map<RatingGroup, Map<String, List<double>>> ratingsByLocationByGroup = {};
  for(var group in groups) {
    var ratingsByLocation = <String, List<double>>{};
    var ratingsRes = await project.getRatings(group);
    if(ratingsRes.isErr()) {
      console.print("Error getting ratings for group ${group.name}: ${ratingsRes.unwrapErr()}");
      continue;
    }
    var ratings = ratingsRes.unwrap();
    int totalRatings = 0;
    int locatedRatings = 0;
    for(var rating in ratings) {
      if(rating.lastSeen.isBefore(DateTime(2024, 1, 1))) {
        continue;
      }
      totalRatings++;
      if(rating.regionSubdivision != null) {
        ratingsByLocation.addToList(rating.regionSubdivision!, rating.rating);
        locatedRatings++;
      }

      ratingsByLocationByGroup[group] = ratingsByLocation;
    }
    console.print("Group ${group.name}: ${locatedRatings} / ${totalRatings} (${(locatedRatings / totalRatings * 100).toStringAsFixed(2)}%)");
    var sortedKeys = ratingsByLocation.keys.sorted((a, b) => ratingsByLocation[b]!.average.compareTo(ratingsByLocation[a]!.average));
    for(var key in sortedKeys) {
      console.print("  $key: ${ratingsByLocation[key]!.average.toStringAsFixed(2)} (${ratingsByLocation[key]!.length})");
    }
  }
}