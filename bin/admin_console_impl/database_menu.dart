import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";

import "context.dart";
import "database_commands.dart";
import "menu_helpers.dart";

Future<void> databaseMenuLoop(Console console, AdminConsoleContext ctx) async {
  await menuLoop(console, [
    ImportDeduplicationInfoCommand(ctx),
    ListRatingProjectsCommand(ctx),
    ListPredictionGamesCommand(ctx),
    DumpSessionsCommand(ctx),
    DumpGameDeltasCommand(ctx),
    SetRatingContextCommand(ctx),
    PrintDatabaseUsageStatsCommand(ctx),
    BackMenuCommand(),
  ],
    menuHeader: "Database Menu",
    commandSelected: (command) async {
      if(command.command is BackMenuCommand) {
        return false;
      }
      return true;
    },
  );
}
