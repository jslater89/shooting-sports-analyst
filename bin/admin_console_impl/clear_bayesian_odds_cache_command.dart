import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/extensions/bayesian_delta.dart";

import "base.dart";

class ClearBayesianOddsCacheCommand extends AdminConsoleCommand {
  ClearBayesianOddsCacheCommand(super.ctx);

  @override
  final String key = "4";

  @override
  final String title = "Clear Bayesian Odds Cache";

  @override
  List<MenuArgument> get arguments => [
    IntMenuArgument(label: "game id", description: "Game ID to clear the Bayesian odds cache for", required: true),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var gameId = arguments[0].value;
    if(gameId <= 0) {
      console.print("Delete Bayesian odds cache for all games? (y/n)");
      var answer = console.readLine()?.trim();
      if(answer != null && answer.toLowerCase() == "y") {
        gameId = -1;
      }
      else {
        return;
      }
    }

    if(gameId == -1) {
      console.print("Deleting Bayesian odds cache for all games");
      await ctx.db.clearAllBayesianDeltas();
    }
    else {
      console.print("Deleting Bayesian odds cache for game $gameId");
      await ctx.db.clearBayesianDeltasForGame(gameId);
    }
  }
}
