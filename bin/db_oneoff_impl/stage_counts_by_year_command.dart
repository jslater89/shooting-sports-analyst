
import 'package:collection/collection.dart';
import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'base.dart';

class StageCountsByYearCommand extends DbOneoffCommand {
  StageCountsByYearCommand(super.db);

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _stageCountsByYear(db, console);
  }

  @override
  String get key => "SCY";

  @override
  String get title => "Stage Counts By Year";

  Future<void> _stageCountsByYear(AnalystDatabase db, Console console) async {
    var project = await db.getRatingProjectByName("L2s Main");
    if(project == null) {
      console.print("L2s Main project not found");
      return;
    }
    var matchPointers = project.matchPointers;
    console.print("Found ${matchPointers.length} matches");
    Map<int, int> stageCountsByYear = {};
    for(var pointer in matchPointers) {
      var year = pointer.date!.year;
      var matchRes = await pointer.getDbMatch(db);
      if(matchRes.isErr()) {
        console.print("Error getting match: ${matchRes.unwrapErr()}");
        continue;
      }
      var match = matchRes.unwrap();
      stageCountsByYear.incrementBy(year, match.stages.length);
    }
    var years = stageCountsByYear.keys.toList().sorted((a, b) => a.compareTo(b));
    for(var year in years) {
      console.print("${year}: ${stageCountsByYear[year]}");
    }
  }
}
