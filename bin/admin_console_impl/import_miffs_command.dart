import "dart:io";

import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/api/miff/impl/miff_importer.dart";
import "package:shooting_sports_analyst/console/labeled_progress_bar.dart";
import "package:shooting_sports_analyst/console/repl.dart";

import "base.dart";

class ImportMiffsCommand extends AdminConsoleCommand {
  ImportMiffsCommand(super.ctx);

  @override
  final String key = "1";

  @override
  final String title = "Import MIFFs";

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(label: "directory", description: "Directory to import the MIFFs from", required: true),
    BoolMenuArgument(label: "overwrite", description: "Overwrite existing matches", required: false, defaultValue: true),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var path = arguments[0].value;
    var overwrite = arguments[1].value;
    var directory = Directory(path);
    if(!directory.existsSync()) {
      console.print("Directory does not exist: ${directory.path}");
      return;
    }
    var miffs = directory.listSync().where((e) => e.path.endsWith(".miff.gz") || e.path.endsWith(".miff")).toList();
    var importer = MiffImporter();
    int filesConsidered = 0;
    int totalFiles = miffs.length;
    int importedMatches = 0;
    int savedMatches = 0;
    var progressBar = LabeledProgressBar(maxValue: totalFiles, canHaveErrors: true, initialLabel: "Importing MIFFs...");
    for(var miff in miffs) {
      filesConsidered++;
      progressBar.tick("Imported: $importedMatches Saved: $savedMatches ($filesConsidered of $totalFiles)");
      if(miff is! File) {
        continue;
      }
      var bytes = miff.readAsBytesSync();
      var importRes = importer.importMatch(bytes);
      if(importRes.isErr()) {
        progressBar.error("Error importing match ${miff.path}: ${importRes.unwrapErr().message}");
        continue;
      }
      var match = importRes.unwrap();
      importedMatches++;
      bool saved = false;
      if(match.sourceIds.isEmpty || match.sourceCode.isEmpty) {
        progressBar.error("No source info: ${match.name} ${match.sourceIds} ${match.sourceCode}");
        continue;
      }
      if(overwrite) {
        var saveRes = ctx.db.saveMatchSync(match);
        if(saveRes.isOk()) {
          saved = true;
          savedMatches++;
        }
      }
      else {
        var existingMatch = await ctx.db.hasMatchByAnySourceId(match.sourceIds);
        if(existingMatch) {
          progressBar.error("Match already exists: ${match.name}");
          miff.deleteSync();
          continue;
        }
        var saveRes = ctx.db.saveMatchSync(match);
        if(saveRes.isOk()) {
          saved = true;
          savedMatches++;
        }
      }

      if(saved) {
        miff.deleteSync();
      }
    }
    progressBar.complete();
  }
}
