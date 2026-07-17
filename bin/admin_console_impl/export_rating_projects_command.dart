import "dart:convert";
import "dart:io";

import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/util.dart";

import "base.dart";

class ExportRatingProjectsCommand extends AdminConsoleCommand {
  ExportRatingProjectsCommand(super.ctx);

  @override
  final String key = "5";

  @override
  final String title = "Export Rating Projects";

  @override
  String? get description => "Export rating projects to JSON by name";

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(
      label: "project names",
      description: "Comma-separated project names to export",
      required: true,
    ),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    final raw = arguments[0].value as String;
    final names = raw.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    await runNames(console, names);
  }

  Future<bool> runNames(Console console, List<String> names) async {
    if(names.isEmpty) {
      console.print("Usage: dart bin/admin_console.dart ERP <project name> [...]");
      return false;
    }

    bool anyFailed = false;
    for(final name in names) {
      final project = await ctx.db.getRatingProjectByName(name);
      if(project == null) {
        console.print("Project not found: $name");
        anyFailed = true;
        continue;
      }

      project.settings;
      project.changedSettings();
      final filename = "${project.name.safeFilename()}.json";
      File(filename).writeAsStringSync(jsonEncode(project.toJson()));
      console.print("Exported ${project.name} to $filename");
    }

    return !anyFailed;
  }
}
