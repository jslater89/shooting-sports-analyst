import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';

import 'base.dart';

class FindMiffTestMatchesCommand extends DbOneoffCommand {
  FindMiffTestMatchesCommand(super.db);

  @override
  final String key = "FMT";
  @override
  final String title = "Find MIFF Test Matches";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var icoreMatches = await db.queryMatches(name: "Analyst ICORE");
    for(var match in icoreMatches) {
      console.print("${match.eventName} ${match.sourceIds}");
    }

    icoreMatches = await db.queryMatches(name: "Central States Regional");
    for(var match in icoreMatches) {
      console.print("${match.eventName} ${match.sourceIds}");
    }

    var idpaNationals2025 = await db.queryMatches(name: "2025 IDPA National Championship");
    for(var match in idpaNationals2025) {
      console.print("${match.eventName} ${match.sourceIds}");
    }

    var uspsaNationals2025 = await db.queryMatches(name: "2025 Sig Sauer Factory Gun National");
    for(var match in uspsaNationals2025) {
      console.print("${match.eventName} ${match.sourceIds}");
    }

    var handgunWorldShoot2025 = await db.queryMatches(name: "2025 IPSC Handgun World Shoot");
    for(var match in handgunWorldShoot2025) {
      console.print("${match.eventName} ${match.sourceIds}");
    }
  }
}
