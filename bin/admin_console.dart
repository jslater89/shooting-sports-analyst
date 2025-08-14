import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
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
  await ConfigLoader().ready;
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

typedef _CommandExecutor = Future<void> Function(Console, List<_MenuArgumentValue>);

abstract class _MenuArgument<T> {
  final String label;
  final bool isRequired;

  _MenuArgumentValue<T>? parseInput(String value);

  const _MenuArgument({required this.isRequired, required this.label});
}

class StringMenuArgument extends _MenuArgument<String> {
  @override
  _MenuArgumentValue<String>? parseInput(String value) => _MenuArgumentValue(argument: this, value: value);

  const StringMenuArgument({required super.label, super.isRequired = false});
}

class IntMenuArgument extends _MenuArgument<int> {
  @override
  _MenuArgumentValue<int>? parseInput(String value) {
    var intValue = int.tryParse(value);
    if(intValue == null) {
      return null;
    }
    return _MenuArgumentValue(argument: this, value: intValue);
  }

  const IntMenuArgument({required super.label, super.isRequired = false});
}


class _MenuArgumentValue<T> {
  final _MenuArgument<T> argument;
  final T value;

  const _MenuArgumentValue({required this.argument, required this.value});
}

class _ExecutedCommand {
  final _MenuCommand? command;
  final List<_MenuArgumentValue> arguments;

  const _ExecutedCommand({required this.command, required this.arguments});
}

abstract interface class _MenuCommand {
  String get key;
  String get title;

  /// For data commands, this is called with the console and arguments.
  _CommandExecutor? get execute;

  /// The arguments required by the command.
  List<_MenuArgument> get arguments;

  /// Render a menu with the given commands, returning a selected command (to be fed to the next call to renderMenu)
  /// or null, if the user has pressed Ctrl-C or EOF/Ctrl-D and wishes to exit the application.
  ///
  /// If the user has entered an unknown command, this will return an ExecutedCommand with a null command.
  static Future<_ExecutedCommand?> renderMenu(
    Console console,
    List<_MenuCommand> commands, {
    _ExecutedCommand? executedCommand,
    String? menuHeader,
  }) async {
    console.clearScreen();
    if(executedCommand != null && executedCommand.command != null) {
      console.write("\n");
      await executedCommand.command!.execute?.call(console, executedCommand.arguments);
    }

    var longestTitle = commands.map((c) => c.title.length).reduce((a, b) => a > b ? a : b);
    var alignment = max(36, longestTitle + 2);
    console.write("\n");
    if(menuHeader != null) {
      console.write(menuHeader);
      console.write("\n");
    }
    console.write("Key");
    console.writeAligned("Operation", alignment, TextAlignment.right);
    console.write("\n");
    console.write("---------------------------------------\n");
    for(var command in commands) {
      renderCommand(console, command);
    }

    console.write("> ");
    var commandString = console.readLine(cancelOnBreak: true, cancelOnEOF: true);
    if(commandString == null) {
      exit(0);
    }
    else {
      console.write("\n");

      var parts = commandString.split(" ");
      var commandName = parts[0];
      commandName = commandName.replaceAll(".", "");
      var command = commands.firstWhereOrNull((c) => c.key == commandName.toUpperCase());

      if(command == null) {
        console.write("Unknown command: $commandName\n");
        return null;
      }

      var argumentStrings = parts.sublist(1);
      var argumentValues = <_MenuArgumentValue>[];
      for(var i = 0; i < command.arguments.length; i++) {
        var argument = command.arguments[i];
        var string = argumentStrings.removeAt(0);
        var value = argument.parseInput(string);
        if(value == null) {
          console.write("Invalid argument: $string\n");
          return null;
        }
        argumentValues.add(value);
      }
      return _ExecutedCommand(command: command, arguments: argumentValues);
    }
  }

  static void renderCommand(Console console, _MenuCommand command) {
    console.write("${command.key}. ");
    console.writeAligned(command.title, 36, TextAlignment.right);
    console.write("\n");
  }
}

enum _MainMenuCommand implements _MenuCommand {
  fantasy("1", "Fantasy"),
  database("2", "Database Information"),
  quit("Q", "Quit");

  final String key;
  final String title;
  final List<_MenuArgument> arguments = const [];

  @override
  final _CommandExecutor? execute = null;

  const _MainMenuCommand(this.key, this.title);
}

/// Run a menu loop with the given commands. The commandSelected callback is called with the command selected,
/// or null if no command was selected. The callback should return true if the loop should continue (i.e., stay
/// in the current menu), or false if the loop should exit (i.e., go up to the previous menu).
Future<void> _menuLoop(Console console, List<_MenuCommand> commands, {
  required Future<bool> Function(_ExecutedCommand) commandSelected,
  String? menuHeader,
}) async {
  _ExecutedCommand? executedCommand;
  commandLoop:while(true) {
    executedCommand = await _MenuCommand.renderMenu(console, commands, menuHeader: menuHeader, executedCommand: executedCommand);
    if(executedCommand == null) {
      exit(0);
    }
    var continueLoop = await commandSelected(executedCommand);
    if(!continueLoop) {
      break commandLoop;
    }
  }
}

Future<void> _mainMenuLoop(Console console) async {
  await _menuLoop(console, _MainMenuCommand.values,
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

enum _FantasyMenuCommand implements _MenuCommand {
  usageStats("1", "Usage Stats"),
  back("B", "Back");

  final String key;
  final String title;
  final List<_MenuArgument> arguments = const [];

  @override
  final _CommandExecutor? execute = null;

  const _FantasyMenuCommand(this.key, this.title);
}

Future<void> _fantasyMenuLoop(Console console) async {
  await _menuLoop(console, _FantasyMenuCommand.values,
    menuHeader: "Fantasy Menu",
    commandSelected: (command) async {
      switch(command.command) {
        case _FantasyMenuCommand.usageStats:
          console.write("Not yet implemented\n");
          return true;
        case _FantasyMenuCommand.back:
          return false;
        default:
          return true;
      }
    }
  );
}

enum _DatabaseMenuCommand implements _MenuCommand {
  importDeduplicationInfo("1", "Import Deduplication Info"),
  listRatingProjects("2", "List Rating Projects", execute: _printRatingProjectList),
  setRatingContext("3", "Set Rating Context",
    execute: _setRatingContext,
    arguments: [IntMenuArgument(label: "Project ID")]
  ),
  printUsageStats("4", "Print Usage Stats", execute: _printDatabaseUsageStats),
  back("B", "Back");

  final String key;
  final String title;
  final List<_MenuArgument> arguments;

  @override
  final _CommandExecutor? execute;

  const _DatabaseMenuCommand(this.key, this.title, {this.execute = null, this.arguments = const []});
}

Future<void> _databaseMenuLoop(Console console) async {
  await _menuLoop(console, _DatabaseMenuCommand.values,
    menuHeader: "Database Menu",
    commandSelected: (command) async {
      switch(command.command) {
        case _DatabaseMenuCommand.importDeduplicationInfo:
          console.write("Not yet implemented\n");
          return true;
        case _DatabaseMenuCommand.setRatingContext:
          console.write("Not yet implemented\n");
          return true;
        case _DatabaseMenuCommand.printUsageStats:
          await _printDatabaseUsageStats(console, command.arguments);
          return true;
        case _DatabaseMenuCommand.back:
          return false;
        default:
          return true;
      }
    }
  );
}

Future<void> _printDatabaseUsageStats(Console console, List<_MenuArgumentValue> arguments) async {
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

Future<void> _printRatingProjectList(Console console, List<_MenuArgumentValue> arguments) async {
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

Future<void> _setRatingContext(Console console, List<_MenuArgumentValue> arguments) async {
  var projectId = arguments.first.value;
  var project = await _database.getRatingProjectById(projectId);
  if(project == null) {
    console.write("Project not found\n");
    return;
  }
  // _ratingContext = project;
  console.write("Rating context set to ${project.name}\n");
}
