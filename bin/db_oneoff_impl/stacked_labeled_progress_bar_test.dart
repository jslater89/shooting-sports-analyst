import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';

class StackedLabeledProgressBarTest extends MenuCommandClass {
  StackedLabeledProgressBarTest() : super();

  @override
  final String key = "SLPB";
  @override
  final String title = "Stacked Labeled Progress Bar Test";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    console.print("Starting test...");
    for(int i = 0; i < 24; i++) {
      console.print("Filling console, line $i...");
    }
    for(var i = 0; i < 5; i++) {
      console.print("Starting iteration $i...");
      var progressBar = LabeledProgressBar(maxValue: 100, canHaveErrors: false, initialLabel: "Iteration $i start");
      for(int j = 0; j < 100; j++) {
        progressBar.tick("Iteration $i, tick $j");
        if(j % 20 == 0) {
          progressBar.error("Error");
        }
        await Future.delayed(const Duration(milliseconds: 10));
      }
      progressBar.complete();
      console.print("Iteration $i complete.");
    }
    console.print("Test complete.");
  }
}
