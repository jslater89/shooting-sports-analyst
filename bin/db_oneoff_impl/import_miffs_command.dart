import 'dart:io';

import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/api/miff/impl/miff_importer.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';

import 'base.dart';

class ImportMiffsCommand extends DbOneoffCommand {
  ImportMiffsCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "IMF";
  @override
  final String title = "Import MIFFs";

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(label: "directory", description: "Directory to import the MIFFs from", required: true),
    StringMenuArgument(label: "sourceOverride", description: "Override the source code for the matches", required: false),
    BoolMenuArgument(label: "dryrun", description: "Import matches but do not save them to the database", required: false, defaultValue: true),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var path = arguments[0].value!;
    var sourceOverride = arguments[1].value as String?;
    var dryrun = arguments[2].value!;
    var directory = Directory(path);
    if(!directory.existsSync()) {
      console.print("Directory does not exist: ${directory.path}");
      return;
    }
    var importer = MiffImporter();
    int importedMatches = 0;
    int savedMatches = 0;
    for(var file in directory.listSync()) {
      if(file is File && file.path.endsWith(".miff.gz")) {
        var bytes = file.readAsBytesSync();
        var importRes = importer.importMatch(bytes);
        if(importRes.isErr()) {
          console.print("Error importing match ${file.path}: ${importRes.unwrapErr().message}");
          continue;
        }
        var match = importRes.unwrap();
        if(sourceOverride != null) {
          match.sourceCode = sourceOverride;
        }
        importedMatches++;
        console.print("Imported match ${match.name} from ${file.path}");
        if(!dryrun) {
          var saveRes = await db.saveMatch(match);
          if(saveRes.isOk()) {
            console.print("Saved match ${match.name} to the database");
            savedMatches++;
          }
          else {
            console.print("Error saving match ${match.name}: ${saveRes.unwrapErr().message}");
          }
        }
      }
    }
    console.print("Imported ${importedMatches} matches from ${directory.path}");
    console.print("Saved ${savedMatches} matches to the database");
  }
}