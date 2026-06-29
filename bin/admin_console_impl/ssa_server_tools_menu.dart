import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";

import "calculate_rating_project_command.dart";
import "clear_bayesian_odds_cache_command.dart";
import "context.dart";
import "import_miffs_command.dart";
import "load_rating_project_command.dart";
import "menu_helpers.dart";

Future<void> ssaServerToolsMenuLoop(Console console, AdminConsoleContext ctx) async {
  await menuLoop(console, [
    ImportMiffsCommand(ctx),
    LoadRatingProjectCommand(ctx),
    CalculateRatingProjectCommand(ctx),
    ClearBayesianOddsCacheCommand(ctx),
    BackMenuCommand(),
  ],
    menuHeader: "SSA Server Tools",
    commandSelected: (command) async {
      if(command.command is BackMenuCommand) {
        return false;
      }
      return true;
    },
  );
}
