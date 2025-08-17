import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';

/// Render a menu with the given commands, returning a selected command (to be fed to the next call to renderMenu)
/// or null, if the user has pressed Ctrl-C or EOF/Ctrl-D and wishes to exit the application.
///
/// If the user has entered an unknown command, this will return an ExecutedCommand with a null command.
Future<ExecutedCommand?> _renderMenu(
  Console console,
  List<MenuCommand> commands, {
  ExecutedCommand? executedCommand,
  String? menuHeader,
}) async {
  console.clearScreen();
  if(executedCommand != null && executedCommand.command != null) {
    console.write("\n");
    await executedCommand.command!.execute?.call(console, executedCommand.arguments);
  }
  else if(executedCommand != null && executedCommand.command == null) {
    if(executedCommand.arguments.isNotEmpty) {
      var errorArgument = executedCommand.arguments.first;
      console.write("${errorArgument.argument.label}: ${errorArgument.value}\n");
    }
    else {
      console.write("Command execution error\n");
    }
  }
  var longestKey = commands.map((c) => c.key.length).reduce((a, b) => a > b ? a : b);
  var longestTitle = commands.map((c) => c.title.length).reduce((a, b) => a > b ? a : b);
  var keyAlignment = longestKey + 2; // 1 for the dot, 1 for the space
  var titleAlignment = max(36, longestTitle + 2);
  console.write("\n");
  if(menuHeader != null) {
    console.write(menuHeader);
    console.write("\n");
  }
  console.write("Key".padRight(keyAlignment));
  console.writeAligned("Operation", titleAlignment, TextAlignment.right);
  console.write("\n");
  console.write("-" * (keyAlignment + titleAlignment) + "\n");
  for(var command in commands) {
    MenuCommand.render(console, command, keyAlignment, titleAlignment);
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
      return ExecutedCommand(command: null, arguments: [
        MenuArgumentValue<String>(argument: StringMenuArgument(label: "Unknown command"), value: commandName)
      ]);
    }

    var argumentStrings = parts.sublist(1);
    var argumentValues = <MenuArgumentValue>[];
    for(var i = 0; i < command.arguments.length; i++) {
      var argument = command.arguments[i];
      if(argumentStrings.isEmpty) {
        var label = "Argument count mismatch: ${command.key} requires ${command.arguments.length} arguments, but got ${parts.length - 1}";
        var errorString = "\n${MenuCommand.getUsage(console, command)}";
        return ExecutedCommand(command: null, arguments: [
          MenuArgumentValue<String>(argument: StringMenuArgument(label: label), value: errorString)
        ]);
      }
      var string = argumentStrings.removeAt(0);
      var value = argument.parseInput(string);
      if(value == null) {
        console.write("Invalid argument: $string\n");
        var errorString = "\n${MenuCommand.getUsage(console, command)}";
        return ExecutedCommand(command: null, arguments: [
          MenuArgumentValue<String>(argument: StringMenuArgument(label: "Invalid argument"), value: errorString)
        ]);
      }
      argumentValues.add(value);
    }
    return ExecutedCommand(command: command, arguments: argumentValues);
  }
}

/// Run a menu loop with the given commands. The commandSelected callback is called with the command selected,
/// or null if no command was selected. The callback should return true if the loop should continue (i.e., stay
/// in the current menu), or false if the loop should exit (i.e., go up to the previous menu).
Future<void> menuLoop(Console console, List<MenuCommand> commands, {
  required Future<bool> Function(ExecutedCommand) commandSelected,
  String? menuHeader,
}) async {
  ExecutedCommand? executedCommand;
  commandLoop:while(true) {
    executedCommand = await _renderMenu(console, commands, menuHeader: menuHeader, executedCommand: executedCommand);
    if(executedCommand == null) {
      exit(0);
    }
    var continueLoop = await commandSelected(executedCommand);
    if(!continueLoop) {
      break commandLoop;
    }
  }
}

/// Convenience methods for printing to the console.
extension PrintExtension on Console {
  /// Print a line of text to the console, with a trailing newline.
  ///
  /// [Console.writeLine] seems to put an extra newline in, for me.
  void print(String text) => write("$text\n");

  /// Print a line of text to the console, without a trailing newline.
  void printNoBreak(String text) => write(text);

  /// Overwrite the current line of text with the given text.
  void overwriteLine(String text) {
    var position = cursorPosition;
    cursorPosition = Coordinate(position?.row ?? 0, 0);
    eraseLine();
    write(text);
    cursorPosition = position;
  }

  /// Move the cursor up by the given number of lines.
  void moveUp(int count, {bool carriageReturn = false, bool clearLine = false}) {
    var position = cursorPosition;
    var currentRow = position?.row ?? 0;
    var currentCol = position?.col ?? 0;

    var newRow = currentRow - count;
    var newCol = currentCol;
    if(newRow < 0) {
      newRow = 0;
    }

    if(carriageReturn) {
      newCol = 0;
    }

    if(clearLine) {
      eraseLine();
    }

    cursorPosition = Coordinate(newRow, newCol);
  }

  void moveDown(int count, {bool carriageReturn = false, bool clearLine = false}) {
    moveUp(-count, carriageReturn: carriageReturn, clearLine: clearLine);
  }
}

/// The signature of a command executor, which accepts a console and a list of arguments
/// and prints the output for a command.
typedef CommandExecutor = Future<void> Function(Console, List<MenuArgumentValue>);

/// A default implementation of a command executor that prints "Not yet implemented".
Future<void> notYetImplementedExecutor(Console console, List<MenuArgumentValue> arguments) async {
  console.writeLine("Not yet implemented");
}

/// A base class for menu arguments, which are used to parse input from the user.
///
/// [T] is the type of the argument value.
abstract class MenuArgument<T> {
  final String label;
  final bool required;
  final String? description;
  MenuArgumentValue<T>? parseInput(String value);

  const MenuArgument({required this.required, required this.label, this.description});
}

/// A string menu argument, which performs no additional validation
class StringMenuArgument extends MenuArgument<String> {
  @override
  MenuArgumentValue<String>? parseInput(String value) => MenuArgumentValue(argument: this, value: value);

  const StringMenuArgument({required super.label, super.required = false, super.description});
}

class IntMenuArgument extends MenuArgument<int> {
  @override
  MenuArgumentValue<int>? parseInput(String value) {
    var intValue = int.tryParse(value);
    if(intValue == null) {
      return null;
    }
    return MenuArgumentValue(argument: this, value: intValue);
  }

  const IntMenuArgument({required super.label, super.required = false, super.description});
}


class MenuArgumentValue<T> {
  final MenuArgument<T> argument;
  final T value;

  const MenuArgumentValue({required this.argument, required this.value});
}

class ExecutedCommand {
  final MenuCommand? command;
  final List<MenuArgumentValue> arguments;

  const ExecutedCommand({required this.command, required this.arguments});
}

abstract class MenuCommand {
  String get key;
  String get title;

  /// For data commands, this is called with the console and arguments.
  CommandExecutor? get execute => null;

  /// The arguments required by the command.
  List<MenuArgument> get arguments => const [];

  static void render(Console console, MenuCommand command, int keyAlignment, int titleAlignment) {
    console.write("${command.key}. ".padRight(keyAlignment));
    console.writeAligned(command.title, titleAlignment, TextAlignment.right);
    console.write("\n");
  }

  /// Print usage information for the command.
  static String getUsage(Console console, MenuCommand command) {
    StringBuffer buffer = StringBuffer();
    String firstLine = "Usage: ${command.key}";
    if(command.arguments.isNotEmpty) {
      for(var arg in command.arguments) {
        if(arg.required) {
          firstLine += " <${arg.label}>";
        }
        else {
          firstLine += " [${arg.label}]";
        }
      }
    }
    buffer.write(firstLine);
    buffer.write("\n");
    for(var arg in command.arguments) {
      buffer.write("  ${arg.label}: ${arg.required ? "required" : "optional"}\n");
      if(arg.description != null) {
        buffer.write("    ${arg.description}\n");
      }
    }
    return buffer.toString();
  }
}

abstract class MenuCommandClass extends MenuCommand {
  Future<void> executor(Console console, List<MenuArgumentValue> arguments);

  @override
  CommandExecutor? get execute => executor;
}
