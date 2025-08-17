import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';

class LabeledProgressBar {
  late final ProgressBar _bar;
  late final Console _console;
  String _currentLabel = "";

  LabeledProgressBar({
    required int maxValue,
    String initialLabel = "",
    Coordinate? startCoordinate,
    int? barWidth,
    bool showSpinner = true,
    List<String> tickCharacters = const <String>['-', '\\', '|', '/'],
  }) {
    _console = Console();
    _currentLabel = initialLabel;
    _console.print(_currentLabel);
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

  /// Complete the progress bar, moving the cursor to the next clear line.
  void complete() {
    _bar.complete();
    _console.moveDown(2);
  }
}
