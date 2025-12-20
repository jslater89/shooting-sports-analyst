import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'base.dart';

class FindAdrianRandleCommand extends DbOneoffCommand {
  FindAdrianRandleCommand(super.db);

  @override
  final String key = "FAR";
  @override
  final String title = "Find Adrian Randle";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var project = await db.getRatingProjectByName("L2s Main");
    if(project == null) {
      console.print("Project not found");
      return;
    }

    var pointers = project.matchPointers;

    for(var pointer in pointers) {
      var matchRes = await pointer.getDbMatch(db);
      if(matchRes.isErr()) {
        console.print("Error getting match: ${matchRes.unwrapErr()}");
        continue;
      }
      var match = matchRes.unwrap();
      for(var shooter in match.shooters) {
        if(shooter.lastName == "Randle") {
          console.print("Match found: ${pointer.name}");
          console.print("Shooter: ${shooter.firstName} ${shooter.lastName} (${shooter.memberNumber})");
          console.print("");
        }
      }
    }
  }
}