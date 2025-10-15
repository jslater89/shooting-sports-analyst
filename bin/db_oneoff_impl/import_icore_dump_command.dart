import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/classifier_import.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/icore_export_converter.dart';

import 'base.dart';

class ImportIcoreDumpCommand extends DbOneoffCommand {
  ImportIcoreDumpCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "IID";
  @override
  final String title = "Import Icore Dump";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var path = arguments.first.value;
    var file = File(path);
    if(!file.existsSync()) {
      console.print("File does not exist: ${file.path}");
      return;
    }
    await _importIcoreDump(db, console, file);
  }

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(label: "file", description: "Path to an ICORE DB JSON dump to import", required: true),
  ];
}

Future<void> _importIcoreDump(AnalystDatabase db, Console console, File file) async {
  var masterScores = IcoreClassifierExport.fromFile(file);
  var analystScores = masterScores.toAnalystScores();

  await db.isar.writeTxn(() async {
    int deleted = await db.isar.dbShootingMatchs.filter()
      .eventNameStartsWith("ICORE Classifier Analysis")
      .deleteAll();
    console.print("Deleted ${deleted} matches");
  });

  var importer = ClassifierImporter(
    sport: icoreSport,
    duration: PseudoMatchDuration.month,
    minimumScoreCount: 4,
    matchNamePrefix: "ICORE Classifier Analysis",
  );
  var matchesResult = importer.import(analystScores);
  if(matchesResult.isErr()) {
    console.print("Error importing scores: ${matchesResult.unwrapErr()}");
    return;
  }
  var matches = matchesResult.unwrap();
  console.print("Imported ${matches.length} matches");
  int dbInserts = 0;
  for(var match in matches) {
    var saveResult = await db.saveMatch(match);
    if(saveResult.isOk()) {
      dbInserts++;
    }
    else {
      console.print("Error saving match: ${saveResult.unwrapErr()}");
    }
  }
  console.print("Saved ${dbInserts} matches to DB");
}
