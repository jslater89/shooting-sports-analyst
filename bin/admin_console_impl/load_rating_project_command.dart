import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";

import "base.dart";
import "rating_project_import.dart";

class LoadRatingProjectCommand extends AdminConsoleCommand {
  LoadRatingProjectCommand(super.ctx);

  @override
  final String key = "2";

  @override
  final String title = "Load Rating Project";

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(label: "project file", description: "File to load the rating project from", required: true),
    BoolMenuArgument(label: "overwrite", description: "Overwrite existing rating project", required: false, defaultValue: true),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var path = arguments[0].value as String;
    var overwrite = arguments[1].value as bool;

    final result = await importRatingProjectFromJsonFile(ctx.db, path, overwrite: overwrite);
    if(result.isErr()) {
      console.print(result.unwrapErr().message);
      return;
    }

    final project = result.unwrap();
    console.print("Imported ${project.name} at ${project.id} ${overwrite ? "(overwrote existing project)" : ""}");
    if(project.lastUsedMatches.isNotEmpty) {
      console.print("Retained ${project.lastUsedMatches.length} last-used matches");
    }
    if(project.completedFullCalculation) {
      console.print("Prior project completed full calculation, carrying over");
    }
  }
}
