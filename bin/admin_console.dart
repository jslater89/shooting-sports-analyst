
import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/db_statistics.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:shooting_sports_analyst/version.dart';

import 'server.dart';

DbRatingProject? _ratingContext;
late final AnalystDatabase _database;

Future<void> main() async {
  SSALogger.debugProvider = ServerDebugProvider();
  SSALogger.consoleOutput = false;

  var console = Console();
  await ConfigLoader().readyFuture;
  var config = ConfigLoader().config;

  _database = AnalystDatabase();
  await _database.ready;
  var context = await _database.getRatingProjectById(config.ratingsContextProjectId ?? -1);
  if(context != null) {
    _ratingContext = context;
  }

  await _mainMenuLoop(console);
  console.write("Goodbye!\n");
}

enum _MainMenuCommand implements MenuCommand {
  fantasy("1", "Fantasy"),
  database("2", "Database Information"),
  quit("Q", "Quit");

  final String key;
  final String title;
  final List<MenuArgument> arguments;

  @override
  final CommandExecutor? execute;

  const _MainMenuCommand(this.key, this.title, {this.execute = null, this.arguments = const []});
}


Future<void> _mainMenuLoop(Console console) async {
  await menuLoop(console, _MainMenuCommand.values,
    menuHeader: "Shooting Sports Analyst Admin Console ${VersionInfo.version}",
    commandSelected: (command) async {
      switch(command.command) {
        case _MainMenuCommand.fantasy:
          await _fantasyMenuLoop(console);
          return true;
        case _MainMenuCommand.database:
          await _databaseMenuLoop(console);
          return true;
        case _MainMenuCommand.quit:
          return false;
        default:
          return true;
      }
    }
  );
}

enum _FantasyMenuCommand implements MenuCommand {
  usageStats("1", "Usage Stats", execute: notYetImplementedExecutor),
  back("B", "Back");

  final String key;
  final String title;
  final List<MenuArgument> arguments;

  @override
  final CommandExecutor? execute;

  const _FantasyMenuCommand(this.key, this.title, {this.execute = null, this.arguments = const []});
}

Future<void> _fantasyMenuLoop(Console console) async {
  await menuLoop(console, _FantasyMenuCommand.values,
    menuHeader: "Fantasy Menu",
    commandSelected: (command) async {
      switch(command.command) {
        case _FantasyMenuCommand.usageStats:
          return true;
        case _FantasyMenuCommand.back:
          return false;
        default:
          return true;
      }
    }
  );
}

enum _DatabaseMenuCommand implements MenuCommand {
  importDeduplicationInfo("1", "Import Deduplication Info", execute: notYetImplementedExecutor),
  listRatingProjects("2", "List Rating Projects", execute: _printRatingProjectList),
  setRatingContext("3", "Set Rating Context",
    execute: _setRatingContext,
    arguments: [IntMenuArgument(label: "Project ID")]
  ),
  printUsageStats("4", "Print Usage Stats", execute: _printDatabaseUsageStats),
  back("B", "Back");

  final String key;
  final String title;
  final List<MenuArgument> arguments;

  @override
  final CommandExecutor? execute;

  const _DatabaseMenuCommand(this.key, this.title, {this.execute = null, this.arguments = const []});
}

Future<void> _databaseMenuLoop(Console console) async {
  await menuLoop(console, _DatabaseMenuCommand.values,
    menuHeader: "Database Menu",
    commandSelected: (command) async {
      switch(command.command) {
        case _DatabaseMenuCommand.importDeduplicationInfo:
          return true;
        case _DatabaseMenuCommand.setRatingContext:
          return true;
        case _DatabaseMenuCommand.printUsageStats:
          return true;
        case _DatabaseMenuCommand.back:
          return false;
        default:
          return true;
      }
    }
  );
}

Future<void> _printDatabaseUsageStats(Console console, List<MenuArgumentValue> arguments) async {
  var basicStats = await _database.getBasicDatabaseStatistics();
  console.write("Database Usage Stats\n");
  var statsTable = Table();
  statsTable.insertColumn(header: "Metric");
  statsTable.insertColumn(header: "Value");
  statsTable.insertRow(["Matches", basicStats.matchCount]);
  statsTable.insertRow(["Projects", basicStats.ratingProjectCount]);
  statsTable.insertRow(["Ratings", basicStats.ratingCount]);
  statsTable.insertRow(["Events", basicStats.eventCount]);

  console.write(statsTable.render());
}

Future<void> _printRatingProjectList(Console console, List<MenuArgumentValue> arguments) async {
  var projects = await _database.getAllRatingProjects();
  projects.sort((a, b) => a.updated.compareTo(b.updated));
  console.write("Rating Projects\n");
  var projectsTable = Table();
  projectsTable.insertColumn(header: "ID");
  projectsTable.insertColumn(header: "Name");
  projectsTable.insertColumn(header: "Updated");
  for(var project in projects) {
    projectsTable.insertRow([project.id, project.name, programmerYmdFormat.format(project.updated)]);
  }
  console.write(projectsTable.render());
}

Future<void> _setRatingContext(Console console, List<MenuArgumentValue> arguments) async {
  var projectId = arguments.first.value;
  var project = await _database.getRatingProjectById(projectId);
  if(project == null) {
    console.write("Project not found\n");
    return;
  }
  // _ratingContext = project;
  console.write("Rating context set to ${project.name}\n");
}
