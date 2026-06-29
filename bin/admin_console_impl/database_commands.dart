import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/db_statistics.dart";
import "package:shooting_sports_analyst/data/database/extensions/bayesian_delta.dart";
import "package:shooting_sports_analyst/data/database/extensions/prediction_game.dart";
import "package:shooting_sports_analyst/data/database/extensions/server_auth.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/prediction_game/prediction_game_manager.dart";
import "package:shooting_sports_analyst/util.dart";

import "base.dart";

class ImportDeduplicationInfoCommand extends AdminConsoleCommand {
  ImportDeduplicationInfoCommand(super.ctx);

  @override
  final String key = "1";

  @override
  final String title = "Import Deduplication Info";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await notYetImplementedExecutor(console, arguments);
  }
}

class ListRatingProjectsCommand extends AdminConsoleCommand {
  ListRatingProjectsCommand(super.ctx);

  @override
  final String key = "2";

  @override
  final String title = "List Rating Projects";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var projects = await ctx.db.getAllRatingProjects();
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
}

class ListPredictionGamesCommand extends AdminConsoleCommand {
  ListPredictionGamesCommand(super.ctx);

  @override
  final String key = "3";

  @override
  final String title = "List Prediction Games";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var games = await ctx.db.getAllPredictionGames();
    console.write("Prediction Games\n");
    var gamesTable = Table();
    gamesTable.insertColumn(header: "ID");
    gamesTable.insertColumn(header: "Name");
    gamesTable.insertColumn(header: "Start");
    gamesTable.insertColumn(header: "End");
    for(var game in games) {
      gamesTable.insertRow([
        game.id,
        game.name,
        game.start != null ? programmerYmdFormat.format(game.start!) : "n/a",
        game.end != null ? programmerYmdFormat.format(game.end!) : "n/a"
      ]);
    }
    console.write(gamesTable.render());
  }
}

class DumpSessionsCommand extends AdminConsoleCommand {
  DumpSessionsCommand(super.ctx);

  @override
  final String key = "4";

  @override
  final String title = "Dump Sessions";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var sessions = await ctx.db.getActiveSessions();
    var sessionsTable = Table();
    sessionsTable.insertColumn(header: "Display Name");
    sessionsTable.insertColumn(header: "Username");
    sessionsTable.insertColumn(header: "Auth Method");
    sessionsTable.insertColumn(header: "Created");
    sessionsTable.insertColumn(header: "Expires");
    sessionsTable.insertColumn(header: "Has Refresh?");
    for(var session in sessions) {
      final user = session.user.value;
      sessionsTable.insertRow([
        user?.guaranteedDisplayName ?? "n/a",
        user?.username ?? "n/a",
        session.authMethod.name,
        programmerYmdHmFormat.format(session.created),
        programmerYmdHmFormat.format(session.expires),
        session.refreshToken != null ? "Yes" : "No"
      ]);
    }
    console.write(sessionsTable.render());
  }
}

class DumpGameDeltasCommand extends AdminConsoleCommand {
  DumpGameDeltasCommand(super.ctx);

  @override
  final String key = "5";

  @override
  final String title = "Dump Game Deltas";

  @override
  List<MenuArgument> get arguments => [
    IntMenuArgument(label: "Game ID", required: true),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    if(arguments.isEmpty) {
      console.print("Game ID is required");
      return;
    }
    var gameIdArg = arguments[0] as MenuArgumentValue<int>;
    final gameId = gameIdArg.value;
    final game = await ctx.db.getPredictionGame(gameId);
    if(game == null) {
      console.print("Game not found");
      return;
    }

    final gm = PredictionGameManager(predictionGame: game);
    final matchPreps = await gm.getMatchPreps(futureOnly: false, hasPredictionsOnly: true);
    final targetDate = DateTime.now().subtract(const Duration(days: 5));
    final matchPrepsOfInterest = matchPreps.where((matchPrep) => matchPrep.matchDate.isAfter(targetDate)).toList();

    for(var matchPrep in matchPrepsOfInterest) {
      console.print("Match Prep: ${matchPrep.futureMatch.value!.eventName} ${matchPrep.matchDate}");

      final deltas = await ctx.db.getBayesianDeltasForMatch(gameId, matchPrep);
      DbShooterRating? lastRating;
      for(var delta in deltas) {
        final buf = StringBuffer();
        final rating = delta.getShooterRatingSync(ctx.db);
        if(lastRating?.id != rating?.id) {
          lastRating = rating;
          buf.write("\t");
          buf.write(rating?.name);
          buf.write(" - ");
          buf.write(delta.group.value!.name);
          buf.write(" - ");
          buf.write(rating?.memberNumber);
          buf.write("\n");
        }
        final predictionSetIdHash = delta.predictionSetId.toRadixString(16).substring(0, 8);
        buf.write("\t\t");
        buf.write(predictionSetIdHash);
        buf.write(" - ");
        buf.write(delta.type.name);
        buf.write(" - ");
        if(delta.type == DbPredictionType.percentage) {
          buf.write(delta.delta.asPercentage(decimals: 2, includePercent: true));
        }
        else if(delta.type == DbPredictionType.place) {
          buf.write(delta.delta.toStringAsFixed(2));
        }
        else if(delta.type == DbPredictionType.spread) {
          buf.write("${delta.delta.asPercentage(decimals: 2, includePercent: true)}");
        }
        buf.write(" - ");
        buf.write(programmerYmdHmFormat.format(delta.computedAt));
        buf.write(" - ");
        buf.write(delta.contributingWagerIds.length);
        buf.write(" wagers");
        console.print(buf.toString());
      }
      console.print("");
    }
  }
}

class SetRatingContextCommand extends AdminConsoleCommand {
  SetRatingContextCommand(super.ctx);

  @override
  final String key = "6";

  @override
  final String title = "Set Rating Context";

  @override
  List<MenuArgument> get arguments => [
    IntMenuArgument(label: "Project ID"),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var projectId = arguments.first.value;
    var project = await ctx.db.getRatingProjectById(projectId);
    if(project == null) {
      console.write("Project not found\n");
      return;
    }
    ctx.ratingContext = project;
    var config = ConfigLoader().config;
    config.ratingsContextProjectId = projectId;
    await ConfigLoader().save();
    console.write("Rating context set to ${project.name}\n");
  }
}

class PrintDatabaseUsageStatsCommand extends AdminConsoleCommand {
  PrintDatabaseUsageStatsCommand(super.ctx);

  @override
  final String key = "7";

  @override
  final String title = "Print Usage Stats";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var basicStats = await ctx.db.getBasicDatabaseStatistics();
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
}
