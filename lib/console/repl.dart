/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';

/// Render a menu with the given commands, returning a selected command (to be fed to the next call to renderMenu)
/// or null, if the user has pressed Ctrl-C or EOF/Ctrl-D and wishes to exit the application.
///
/// If the user has entered an unknown command, this will return an ExecutedCommand with a null command. If the
/// returned ExecutedCommand has a StringMenuArgument, this will be printed to the console.
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
      if(commandName.isNotEmpty) {
        return ExecutedCommand(command: null, arguments: [
          MenuArgumentValue<String>(argument: StringMenuArgument(label: "Unknown command"), value: commandName)
        ]);
      }
      else {
        return ExecutedCommand(command: null, arguments: []);
      }
    }

    var argumentStrings = parts.sublist(1);
    var argumentValues = <MenuArgumentValue>[];
    for(var i = 0; i < command.arguments.length; i++) {
      var argument = command.arguments[i];
      if(argumentStrings.isEmpty && !argument.hasDefaultValue && argument.required) {
        var label = "Argument count mismatch: ${command.key} requires ${command.arguments.where((e) => e.required).length} arguments, but got ${parts.length - 1}";
        var errorString = "\n${MenuCommand.getUsage(console, command)}";
        return ExecutedCommand(command: null, arguments: [
          MenuArgumentValue<String>(argument: StringMenuArgument(label: label), value: errorString)
        ]);
      }
      String? argString;
      if(argumentStrings.isNotEmpty) {
        argString = argumentStrings.removeAt(0);
      }
      MenuArgumentValue? value;
      if(argString == null) {
        value = argument.getDefaultValue();
      }
      else {
        value = argument.parseInput(argString);
      }
      if(value == null && argString != null) {
        console.write("Invalid argument for ${argument.label}: $argString\n");
        var errorString = "\n${MenuCommand.getUsage(console, command)}";
        return ExecutedCommand(command: null, arguments: [
          MenuArgumentValue<String>(argument: StringMenuArgument(label: "Invalid argument"), value: errorString)
        ]);
      }
      else if(value == null && argString == null && argument.required) {
        console.write("Missing argument: ${argument.label}\n");
        var errorString = "\n${MenuCommand.getUsage(console, command)}";
        return ExecutedCommand(command: null, arguments: [
          MenuArgumentValue<String>(argument: StringMenuArgument(label: "Missing argument"), value: errorString)
        ]);
      }
      else if(value != null) {
        argumentValues.add(value);
      }
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

  /// Ensure that there are at least [count] lines of available to write below the
  /// current cursor position, writing blank lines as needed.
  ///
  /// Return the cursor to the previous position when done.
  void ensureLines(int count) {
    var currentPosition = cursorPosition;
    if((currentPosition?.col ?? 0) > 0) {
      // Extra newline if we're on a line that has content:
      // e.g. ensureLines(1) with the cursor at 'c'
      //    abc (\n: 1)
      //    <desired blank line> (\n: 2)
      count += 1;
    }
    var desiredRow = currentPosition?.row ?? 0 + count;
    int restoreCol = currentPosition?.col ?? 0;
    int totalLines = count;

    if(desiredRow >= windowHeight) {
      // In the move-down case, we may need more rows to fit the desired downward move.
      cursorPosition = Coordinate(windowHeight - 1, 0);
      var neededRows = desiredRow - windowHeight + 1;
      for(var i = 0; i < neededRows; i++) {
        write("\n");
      }

      // Move back up to the previous position, which is now at a different
      // console coordinate, so we have to do a relative move.
      moveUp(totalLines);
    }
    cursorPosition = Coordinate(currentPosition?.row ?? 0, restoreCol);
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

    if(newRow >= windowHeight) {
      // In the move-down case, we may need more rows to fit the desired downward move.
      cursorPosition = Coordinate(windowHeight - 1, 0);
      var neededRows = newRow - windowHeight + 1;
      for(var i = 0; i < neededRows; i++) {
        write("\n");
      }
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
///
/// [required] is true if the argument is required.
///
/// [defaultValue] is the default value for the argument.
/// [defaultValueFactory] is a factory function that returns the default value for the argument,
/// if the default is unergonomic in some way.
///
/// Arguments with default values will provide [MenuArgumentValue]s with the default value to
/// executors.
///
/// [description] is the description of the argument.
abstract class MenuArgument<T> {
  final String label;
  final bool required;
  final T? defaultValue;
  final T Function()? defaultValueFactory;
  final String? description;
  MenuArgumentValue<T>? parseInput(String value);
  T? getDefault() => defaultValue ?? defaultValueFactory?.call();
  MenuArgumentValue<T>? getDefaultValue() => getDefault() != null ? MenuArgumentValue(argument: this, value: getDefault()!) : null;

  bool get hasDefaultValue => defaultValue != null || defaultValueFactory != null;

  const MenuArgument({required this.required, required this.label, this.description, this.defaultValue, this.defaultValueFactory});
}

/// A string menu argument, which performs no additional validation
class StringMenuArgument extends MenuArgument<String> {
  @override
  MenuArgumentValue<String>? parseInput(String value) => MenuArgumentValue(argument: this, value: value);

  const StringMenuArgument({required super.label, super.required = false, super.description, super.defaultValue, super.defaultValueFactory});
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

  const IntMenuArgument({required super.label, super.required = false, super.description, super.defaultValue, super.defaultValueFactory});
}


class MenuArgumentValue<T> {
  final MenuArgument<T> argument;
  final T value;

  bool canGetAs<T>() => value is T;
  T getAs<T>() => value as T;

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

  /// The description of the command to be shown in help output.
  String? get description => null;

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
    if(command.description != null) {
      buffer.write("${command.description}\nArgs:\n");
    }
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
