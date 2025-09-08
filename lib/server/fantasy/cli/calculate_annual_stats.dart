import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';

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
}
