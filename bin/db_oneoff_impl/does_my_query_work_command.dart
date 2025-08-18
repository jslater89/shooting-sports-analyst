import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';

import 'base.dart';

class DoesMyQueryWorkCommand extends DbOneoffCommand {
  DoesMyQueryWorkCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "DMQ";
  @override
  final String title = "Does My Query Work?";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _doesMyQueryWork(db, console);
  }
}

Future<void> _doesMyQueryWork(AnalystDatabase db, Console console) async {
  var startTime = DateTime.now();
  var matches = await db.queryMatchesByCompetitorMemberNumbers(["A102675", "TY102675", "FY102675"], pageSize: 5);
  var timeTaken = DateTime.now().difference(startTime).inMilliseconds;
  for(var match in matches) {
    console.print("${match}");
  }
  console.print("${matches.length} matches found in ${timeTaken}ms");
}
