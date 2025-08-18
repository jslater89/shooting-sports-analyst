import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';

import 'base.dart';

class Lady90PercentFinishesCommand extends DbOneoffCommand {
  Lady90PercentFinishesCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "L90";
  @override
  final String title = "Lady 90% Finishes";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _lady90PercentFinishes(db, console);
  }
}

Future<void> _lady90PercentFinishes(AnalystDatabase db, Console console) async {
  var startTime = DateTime.now();
  console.print("Loading matches...");
  var matches = await db.isar.dbShootingMatchs
    .filter()
    .shootersElement((q) =>
      q.femaleEqualTo(true)
      .and()
      .precalculatedScore((q) => q.percentageGreaterThan(90, include: true))
    )
    .sortByDate()
    .findAll();

  console.print("Found ${matches.length} matches, processing...");

  var matchProgressBar = LabeledProgressBar(maxValue: matches.length);
  var buf = StringBuffer();
  for(var match in matches) {
    for(var shooter in match.shooters) {
      if(shooter.female && (shooter.precalculatedScore?.percentage ?? 0) >= 90) {
        var competitorCount = match.shooters.where((e) => e.divisionName == shooter.divisionName).length;
        buf.writeln('${match.date},${match.eventName.replaceAll(',', ' ')},${match.matchLevelName},${shooter.firstName},${shooter.lastName},${shooter.divisionName},${shooter.precalculatedScore?.percentage},${shooter.precalculatedScore?.place},${competitorCount}');
      }
    }
    matchProgressBar.tick("${match.eventName}");
  }
  matchProgressBar.complete();

  console.print("Writing to file...");
  File f = File("/tmp/lady_90_percent.csv");
  f.writeAsString(buf.toString());
  console.print("Analysis complete: wrote ${f.path} in ${DateTime.now().difference(startTime).inMilliseconds}ms");
}
