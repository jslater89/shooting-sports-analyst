import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/cache/ratings/rating_cache.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";

import "base.dart";
import "calculate_rating_project_command.dart";
import "rating_project_import.dart";

class ImportCalculateProjectsCommand extends AdminConsoleCommand {
  ImportCalculateProjectsCommand(super.ctx);

  @override
  final String key = "IPC";

  @override
  final String title = "Import and Calculate Rating Projects";

  @override
  String? get description => "Import project JSON files and run partial rating calculation";

  @override
  List<MenuArgument> get arguments => const [];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    console.print("Use CLI: dart run bin/admin_console.dart IPC <project.json> [...]");
  }

  Future<bool> runFiles(
    Console console,
    List<String> projectFiles, {
    bool fullRecalc = false,
    bool skipDeduplication = true,
    bool overwrite = true,
  }) async {
    if(projectFiles.isEmpty) {
      console.print("Usage: dart run bin/admin_console.dart IPC [--full-recalc] [--dedup] <project.json> [...]");
      return false;
    }

    final calculateCommand = CalculateRatingProjectCommand(ctx);
    bool anyFailed = false;

    for(final path in projectFiles) {
      console.print("Importing project from $path");
      final importResult = await importRatingProjectFromJsonFile(ctx.db, path, overwrite: overwrite);
      if(importResult.isErr()) {
        console.print("Import failed for $path: ${importResult.unwrapErr().message}");
        anyFailed = true;
        continue;
      }

      final imported = importResult.unwrap();
      console.print("Imported ${imported.name} at ${imported.id}");
      if(imported.lastUsedMatches.isNotEmpty) {
        console.print("Retained ${imported.lastUsedMatches.length} last-used matches");
      }
      if(imported.completedFullCalculation) {
        console.print("Prior project completed full calculation, carrying over");
      }

      final project = await ctx.db.getRatingProjectById(imported.id);
      if(project == null) {
        console.print("Project not found after import: ${imported.name}");
        anyFailed = true;
        continue;
      }

      final calcOk = await calculateCommand.calculateProject(
        console,
        project,
        fullRecalc: fullRecalc,
        skipDeduplication: skipDeduplication,
      );
      if(!calcOk) {
        anyFailed = true;
      }

      // Between each project, clear the ratings cache: otherwise full calculations of several projects can OOM the
      // server by keeping too many unnecessary ratings in memory.
      RatingCache.instance.clear();
    }

    return !anyFailed;
  }
}
