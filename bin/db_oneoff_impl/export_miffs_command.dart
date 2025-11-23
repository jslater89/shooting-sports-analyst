import 'dart:io';

import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/api/miff/miff.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class ExportMiffsCommand extends DbOneoffCommand {
  ExportMiffsCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "EMF";
  @override
  final String title = "Export MIFFs";

  @override
  String? get description => "Export matches as MIFFs to the given directory.";

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(label: "directory", description: "Directory to export the MIFFs to", required: true),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var path = arguments[0].value as String;
    var directory = Directory(path);
    if(!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    else {
      // Remove all files in the directory
      for(var file in directory.listSync()) {
        if(file is File && file.path.endsWith(".miff.gz")) {
          file.deleteSync();
        }
      }
    }

    var allMatches = await db.getAllMatches();
    var exporter = MiffExporter();
    for(var match in allMatches) {
      var hydratedRes = match.hydrate();
      if(hydratedRes.isErr()) {
        console.print("Error hydrating match ${match.id}: ${hydratedRes.unwrapErr().message}");
        continue;
      }
      var hydrated = hydratedRes.unwrap();
      var miffRes = await exporter.exportMatch(hydrated);
      if(miffRes.isErr()) {
        console.print("Error exporting match ${match.id}: ${miffRes.unwrapErr().message}");
        continue;
      }
      var miff = miffRes.unwrap();
      var file = File("${directory.path}/${match.eventName.safeFilename(replacement: "_")}-${match.sourceIds.first}.miff.gz");
      await file.writeAsBytes(miff);
      console.print("Exported match ${match.eventName} to ${file.path}");
    }
    console.print("Exported ${allMatches.length} matches to ${directory.path}");
  }
}