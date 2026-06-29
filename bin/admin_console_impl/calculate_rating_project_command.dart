import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/project_loader.dart";

import "base.dart";
import "console_project_loader_host.dart";

class CalculateRatingProjectCommand extends AdminConsoleCommand {
  CalculateRatingProjectCommand(super.ctx);

  @override
  final String key = "3";

  @override
  final String title = "Calculate Rating Project";

  @override
  List<MenuArgument> get arguments => [
    IntMenuArgument(label: "project id", description: "Project ID to calculate", required: true),
    BoolMenuArgument(label: "full recalculation", description: "Force a full recalculation", required: false, defaultValue: false),
    BoolMenuArgument(label: "skip deduplication", description: "Skip deduplication", required: false, defaultValue: true),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    int projectId = arguments[0].value;
    bool fullRecalc = arguments[1].value;
    bool skipDeduplication = arguments[2].value;

    var project = await ctx.db.getRatingProjectById(projectId);
    if(project == null) {
      console.print("Project not found");
      return;
    }

    final success = await calculateProject(
      console,
      project,
      fullRecalc: fullRecalc,
      skipDeduplication: skipDeduplication,
    );
    if(!success) {
      return;
    }
  }

  Future<bool> calculateProject(
    Console console,
    DbRatingProject project, {
    required bool fullRecalc,
    required bool skipDeduplication,
  }) async {
    console.print("Loading ratings for project ${project.name}");
    var start = DateTime.now();

    var loader = RatingProjectLoader(project, consoleRatingProjectLoaderHost(console));
    console.print("Beginning project load with fullRecalc: $fullRecalc, skipDeduplication: $skipDeduplication");
    var result = await loader.calculateRatings(fullRecalc: fullRecalc, skipDeduplication: skipDeduplication);
    if(result.isErr()) {
      console.print("Error calculating ratings: ${result.unwrapErr().message}");
      return false;
    }
    console.print("Ratings calculated in ${DateTime.now().difference(start).inSeconds} seconds");
    return true;
  }
}
