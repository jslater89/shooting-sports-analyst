import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/future_match.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'base.dart';

class FixFutureMatchSportNamesCommand extends DbOneoffCommand {
  FixFutureMatchSportNamesCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "FFMSN";
  @override
  final String title = "Fix Future Match Sport Names";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var futureMatches = await db.getFutureMatches();
    for(var futureMatch in futureMatches) {
      var sport = SportRegistry().lookup(futureMatch.sportName, caseSensitive: false);
      if(sport == null) {
        console.print("Unknown sport in future match: ${futureMatch.sportName}");
      }
      else {
        futureMatch.sportName = sport.name;
        await db.saveFutureMatch(futureMatch);
      }
    }
  }
}