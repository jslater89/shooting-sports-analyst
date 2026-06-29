import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/version.dart";

import "context.dart";
import "database_menu.dart";
import "fantasy_menu.dart";
import "menu_helpers.dart";
import "ssa_server_tools_menu.dart";

Future<void> mainMenuLoop(Console console, AdminConsoleContext ctx) async {
  await menuLoop(console, [
    SubMenuCommand(key: "1", title: "Fantasy"),
    SubMenuCommand(key: "2", title: "Database Information"),
    SubMenuCommand(key: "3", title: "SSA Server Tools"),
    QuitMenuCommand(),
  ],
    menuHeader: "Shooting Sports Analyst Admin Console ${VersionInfo.version}",
    commandSelected: (command) async {
      switch(command.command) {
        case SubMenuCommand(key: "1", title: _):
          await fantasyMenuLoop(console, ctx);
          return true;
        case SubMenuCommand(key: "2", title: _):
          await databaseMenuLoop(console, ctx);
          return true;
        case SubMenuCommand(key: "3", title: _):
          await ssaServerToolsMenuLoop(console, ctx);
          return true;
        case QuitMenuCommand():
          return false;
        default:
          return true;
      }
    },
  );
}
