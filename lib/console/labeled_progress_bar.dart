import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';

class LabeledProgressBar {
  late final ProgressBar _bar;
  late final Console _console;
  String _currentLabel = "";

  bool _hasError = false;
  bool canHaveErrors = false;

  LabeledProgressBar({
    required int maxValue,
    String initialLabel = "",
    Coordinate? startCoordinate,
    int? barWidth,
    bool showSpinner = true,
    this.canHaveErrors = false,
    List<String> tickCharacters = const <String>['-', '\\', '|', '/'],
  }) {
    _console = Console();
    _currentLabel = initialLabel;
    // current state:
    // <initial label>\n
    // <cursor position>
    _console.print(_currentLabel);
    if(canHaveErrors) {
      _console.print(""); // reserve a line for errors
      _console.moveUp(1);
      // current state:
      // <initial label>\n
      // <cursor position for progress bar>\n
      // <blank line for errors>
    }
    _bar = ProgressBar(maxValue: maxValue, startCoordinate: startCoordinate, barWidth: barWidth, showSpinner: showSpinner, tickCharacters: tickCharacters);
    _console.moveUp(1);
  }

  /// Tick the progress bar.
  ///
  /// If [newLabel] is provided, it will overwrite the current label.
  void tick([String? newLabel]) {
    if(newLabel != null) {
      _console.overwriteLine(newLabel);
      _currentLabel = newLabel;
    }
    _bar.tick();
  }

  /// Print an error/status message to the console, below the progress bar.
  ///
  /// If the progress bar was not created with [canHaveErrors] set to true, this will do nothing.
  void error(String message) {
    if(!canHaveErrors) {
      return;
    }
    _hasError = true;
    _console.moveDown(2);
    _console.overwriteLine(message);
    _console.moveUp(2);

  }

  /// Complete the progress bar, moving the cursor to the next clear line.
  void complete() {
    _bar.complete();
    _console.moveDown(_hasError ? 3 : 2);
  }
}
