import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';

import 'base.dart';

class StateShootersCommand extends DbOneoffCommand {
  StateShootersCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "STS";
  @override
  final String title = "State Top Shooters";

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(label: "state", description: "The state to display the top shooters for", required: true),
    IntMenuArgument(label: "count", description: "The number of top shooters to display", required: false, defaultValue: 10),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var project = await db.getRatingProjectByName("L2s Main");
    if(project == null) {
      console.print("Project not found");
      return;
    }

    var state = arguments.first.getAs<String>();
    var count = arguments.last.getAs<int>();

    for(var group in project.groups) {
      var ratingsRes = await project.getRatings(group);
      if(ratingsRes.isErr()) {
        console.print("Error getting ratings for group ${group.name}: ${ratingsRes.unwrapErr()}");
        continue;
      }
      var ratings = ratingsRes.unwrap();
      ratings.sort((a, b) => b.rating.compareTo(a.rating));
      List<DbShooterRating> stateShooters = [];
      for(var rating in ratings) {
        if(rating.regionSubdivision?.toLowerCase() == state.toLowerCase()) {
          stateShooters.add(rating);
        }
        if(stateShooters.length >= count) {
          break;
        }
      }
      console.print("Top ${count} ${group.name} shooters in ${state.toUpperCase()}:");
      for(var (i, shooter) in stateShooters.indexed) {
        console.print("${i + 1}. ${shooter.name} (${shooter.rating.round()})");
      }
      console.print("");
    }
  }
}