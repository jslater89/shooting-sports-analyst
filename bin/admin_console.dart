
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/api/miff/impl/miff_importer.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/db_statistics.dart';
import 'package:shooting_sports_analyst/data/database/extensions/bayesian_delta.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/project_loader.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/fantasy/cli/calculate_annual_stats.dart';
import 'package:shooting_sports_analyst/server/fantasy/cli/lookup_competitor_scores.dart';
import 'package:shooting_sports_analyst/server/fantasy/cli/show_fantasy_leaders.dart';
import 'package:shooting_sports_analyst/server/fantasy/cli/show_valid_groups.dart';
import 'package:shooting_sports_analyst/server/providers.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:shooting_sports_analyst/version.dart';

DbRatingProject? _ratingContext;
late final AnalystDatabase _database;

Future<void> main() async {
  final serverDebugProvider = ServerDebugProvider(isMultiIsolate: false);
  FlutterOrNative.debugModeProvider = serverDebugProvider;
  FlutterOrNative.isolateModeProvider = serverDebugProvider;
  SSALogger.consoleOutput = false;

  var console = Console();
  await ConfigLoader().readyFuture;
  var config = ConfigLoader().config;

  _database = AnalystDatabase();
  await _database.ready;
  var context = await _database.getRatingProjectById(config.ratingsContextProjectId ?? -1);
  if(context != null) {
    _ratingContext = context;
    console.print("Using ratings context: ${context.name}");
  }
  else if(config.ratingsContextProjectId != null) {
    console.print("No ratings context found for id ${config.ratingsContextProjectId}");
  }

  await _mainMenuLoop(console);
  console.write("Goodbye!\n");
}

enum _MainMenuCommand implements MenuCommand {
  fantasy("1", "Fantasy"),
  database("2", "Database Information"),
  ssaServerTools("3", "SSA Server Tools"),
  quit("Q", "Quit");

  final String key;
  final String title;
  final List<MenuArgument> arguments;

  @override
  final CommandExecutor? execute;

  // ignore: unused_element_parameter
  const _MainMenuCommand(this.key, this.title, {this.execute = null, this.arguments = const []});

  @override
  String? get description => "";
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
        case _MainMenuCommand.ssaServerTools:
          await _ssaServerToolsMenuLoop(console);
          return true;
        case _MainMenuCommand.quit:
          return false;
        default:
          return true;
      }
    }
  );
}

int _getRatingContextId() => _ratingContext?.id ?? -1;
enum _FantasyMenuCommand implements MenuCommand {
  usageStats("1", "Usage Stats", execute: notYetImplementedExecutor),
  calculateStatsForYear("2", "Calculate Stats for Year",
    execute: calculateAnnualStats,
    arguments: [
      IntMenuArgument(label: "Year", required: true),
      IntMenuArgument(label: "Ratings Context", defaultValueFactory: _getRatingContextId)
    ]
  ),
  showGroups("3", "Show Valid Groups", execute: showValidGroupsForFantasyProject),
  showLeaders("4", "Show Fantasy Scoring Leaders",
    execute: showFantasyScoringLeaders,
    arguments: [
      StringMenuArgument(label: "Group", required: true),
      IntMenuArgument(label: "Year", required: true),
      StringMenuArgument(label: "Month", description: "A numeric month, or 'all' to print monthly stats for the full year"),
    ],
  ),
  lookupCompetitorScors("5", "Lookup Competitor Scores",
    execute: lookupCompetitorScores,
    arguments: [
      StringMenuArgument(label: "Group", required: true),
      StringMenuArgument(label: "Name", required: true),
    ],
  ),
  back("B", "Back");

  final String key;
  final String title;
  final List<MenuArgument> arguments;

  @override
  final CommandExecutor? execute;

  const _FantasyMenuCommand(this.key, this.title, {this.execute = null, this.arguments = const []});

  @override
  String? get description => "";
}

Future<void> _fantasyMenuLoop(Console console) async {
  await menuLoop(console, _FantasyMenuCommand.values,
    menuHeader: "Fantasy Menu",
    commandSelected: (command) async {
      switch(command.command) {
        case _FantasyMenuCommand.usageStats:
          return true;
        case _FantasyMenuCommand.calculateStatsForYear:
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
  listPredictionGames("3", "List Prediction Games", execute: _printPredictionGames),
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

  @override
  String? get description => "";
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

Future<void> _printPredictionGames(Console console, List<MenuArgumentValue> arguments) async {
  var games = await _database.getAllPredictionGames();
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

Future<void> _setRatingContext(Console console, List<MenuArgumentValue> arguments) async {
  var projectId = arguments.first.value;
  var project = await _database.getRatingProjectById(projectId);
  if(project == null) {
    console.write("Project not found\n");
    return;
  }
  _ratingContext = project;
  var config = ConfigLoader().config;
  config.ratingsContextProjectId = projectId;
  await ConfigLoader().save();
  console.write("Rating context set to ${project.name}\n");
}

enum _SSAMenuCommand implements MenuCommand {
  importMiffs("1", "Import MIFFs", execute: _importMiffs, arguments: [
    StringMenuArgument(label: "directory", description: "Directory to import the MIFFs from", required: true),
    BoolMenuArgument(label: "overwrite", description: "Overwrite existing matches", required: false, defaultValue: true),
  ]),
  loadRatingProject("2", "Load Rating Project", execute: _loadRatingProject, arguments: [
    StringMenuArgument(label: "project file", description: "File to load the rating project from", required: true),
    BoolMenuArgument(label: "overwrite", description: "Overwrite existing rating project", required: false, defaultValue: true),
  ]),
  calculateRatingProject("3", "Calculate Rating Project", execute: _calculateRatingProject, arguments: [
    IntMenuArgument(label: "project id", description: "Project ID to calculate", required: true),
    BoolMenuArgument(label: "full recalculation", description: "Force a full recalculation", required: false, defaultValue: false),
    BoolMenuArgument(label: "skip deduplication", description: "Skip deduplication", required: false, defaultValue: true),
  ]),
  clearBayesianOddsCache("4", "Clear Bayesian Odds Cache", execute: _clearBayesianOddsCache, arguments: [
    IntMenuArgument(label: "game id", description: "Game ID to clear the Bayesian odds cache for", required: true),
  ]),
  back("B", "Back");

  final String key;
  final String title;
  final List<MenuArgument> arguments;

  @override
  final CommandExecutor? execute;

  const _SSAMenuCommand(this.key, this.title, {this.execute = null, this.arguments = const []});

  @override
  String? get description => "";
}

Future<void> _importMiffs(Console console, List<MenuArgumentValue> arguments) async {
  var path = arguments[0].value;
  var overwrite = arguments[1].value;
  var directory = Directory(path);
  if(!directory.existsSync()) {
    console.print("Directory does not exist: ${directory.path}");
    return;
  }
  var miffs = directory.listSync().where((e) => e.path.endsWith(".miff.gz") || e.path.endsWith(".miff")).toList();
  var importer = MiffImporter();
  int filesConsidered = 0;
  int totalFiles = miffs.length;
  int importedMatches = 0;
  int savedMatches = 0;
  var progressBar = LabeledProgressBar(maxValue: totalFiles, canHaveErrors: true, initialLabel: "Importing MIFFs...");
  for(var miff in miffs) {
    filesConsidered++;
    progressBar.tick("Imported: $importedMatches Saved: $savedMatches ($filesConsidered of $totalFiles)");
    if(miff is! File) {
      continue;
    }
    var bytes = miff.readAsBytesSync();
    var importRes = importer.importMatch(bytes);
    if(importRes.isErr()) {
      progressBar.error("Error importing match ${miff.path}: ${importRes.unwrapErr().message}");
      continue;
    }
    var match = importRes.unwrap();
    importedMatches++;
    bool saved = false;
    if(match.sourceIds.isEmpty || match.sourceCode.isEmpty) {
      progressBar.error("No source info: ${match.name} ${match.sourceIds} ${match.sourceCode}");
      continue;
    }
    if(overwrite) {
      var saveRes = _database.saveMatchSync(match);
      if(saveRes.isOk()) {
        saved = true;
        savedMatches++;
      }
    }
    else {
      var existingMatch = await _database.hasMatchByAnySourceId(match.sourceIds);
      if(existingMatch) {
        progressBar.error("Match already exists: ${match.name}");
        miff.deleteSync();
        continue;
      }
      var saveRes = _database.saveMatchSync(match);
      if(saveRes.isOk()) {
        saved = true;
        savedMatches++;
      }
    }

    if(saved) {
      miff.deleteSync();
    }
  }
  progressBar.complete();
}

Future<void> _loadRatingProject(Console console, List<MenuArgumentValue> arguments) async {
  var path = arguments[0].value as String;
  var overwrite = arguments[1].value as bool;

  var imported = jsonDecode(File(path).readAsStringSync());
  if(imported is Map<String, dynamic>) {
    DbRatingProject project;
    try {
      project = DbRatingProject.fromJson(imported);
    }
    catch(e, st) {
      console.print("Invalid project file, root is: ${imported.runtimeType}, error: ${e.toString()}, stackTrace: ${st.toString()}");
      return;
    }
    var existingProject = await AnalystDatabase().getRatingProjectByName(project.name);
    if(existingProject != null && !overwrite) {
      console.print("Project already exists: ${project.name}");
      return;
    }
    if(existingProject != null) {
      // If we're overwriting an existing project, keep the list of last-used matches to avoid recalculating in full
      // when we import an update to a project we already calculated.
      List<MatchPointer> usedMatches = [];
      var sortedMatches = project.matchesToUse().sorted((a, b) => a.date!.compareTo(b.date!));
      for(var match in sortedMatches) {
        if(existingProject.matchPointers.contains(match)) {
          usedMatches.add(match);
        }
      }
      project.lastUsedMatches = usedMatches;
      project.completedFullCalculation = existingProject.completedFullCalculation;
    }
    await AnalystDatabase().saveRatingProject(project);
    console.print("Imported ${project.name} at ${project.id} ${overwrite ? "(overwrote existing project)" : ""}");
    if(project.lastUsedMatches.isNotEmpty) {
      console.print("Retained ${project.lastUsedMatches.length} last-used matches");
    }
    if(project.completedFullCalculation) {
      console.print("Prior project completed full calculation, carrying over");
    }
  }
  else {
    console.print("Invalid project file, root is: ${imported.runtimeType}");
  }
}

Future<void> _calculateRatingProject(Console console, List<MenuArgumentValue> arguments) async {
  int projectId = arguments[0].value;
  bool fullRecalc = arguments[1].value;
  bool skipDeduplication = arguments[2].value;
  var project = await _database.getRatingProjectById(projectId);
  if(project == null) {
    console.print("Project not found");
    return;
  }
  console.print("Loading ratings for project ${project.name}");
  var start = DateTime.now();

  int lastProgress = -1;
  int lastMaxProgress = -1;
  int tickAccumulator = 0;
  var loader = RatingProjectLoader(project, RatingProjectLoaderHost(
    progressCallback: ({
      required int progress,
      required int total,
      required LoadingState state,
      String? eventName,
      String? groupName,
      int? subProgress,
      int? subTotal,
    }) async {
      if(progress < 0 || total < 0) {
        return;
      }

      String subtotalString = "";
      if(subProgress != null && subTotal != null) {
        subtotalString = " sub: $subProgress of $subTotal";
      }

      // If we've never seen any positive progress, set the last progress to the current progress.
      if(lastMaxProgress < 0) {
        lastMaxProgress = total;
        lastProgress = progress;
        tickAccumulator = 0;
        console.print("State: ${state.label} ${progress} of ${total} $subtotalString ${groupName ?? ""} ${eventName ?? ""} ");
      }

      // If we go backward, we need a new progress bar.
      if(progress < lastProgress) {
        tickAccumulator = 0;
        console.print("State: ${state.label} ${progress} of ${total} $subtotalString ${groupName ?? ""} ${eventName ?? ""} ");
      }

      lastProgress = progress;
      lastMaxProgress = total;

      tickAccumulator++;
      if(tickAccumulator % 10 == 0) {
        console.print("State: ${state.label} ${progress} of ${total} $subtotalString ${groupName ?? ""} ${eventName ?? ""} ");
      }
    },
    deduplicationCallback: (group, deduplicationResult) async {
      console.print("Detected deduplication, ignoring");
      for(var collision in deduplicationResult) {
        console.print("Collision: ${collision.deduplicatorName}, ${collision.memberNumbers.keys.join(", ")}");
        console.print("Causes: ${collision.causes.map((e) => e.runtimeType).join(", ")}");
        console.print("Proposed Actions: ${collision.proposedActions.map((e) => e.runtimeType).join(", ")}");
        console.print("");
      }
      return Result.ok([]);
    },
    unableToAppendCallback: (lastUsedMatches, newMatches) async {
      console.print("Unable to append, recalculating");
      return true;
    },
    fullRecalculationRequiredCallback: () async {
      console.print("Full recalculation required, recalculating");
      return true;
    },
  ));
  console.print("Beginning project load with fullRecalc: $fullRecalc, skipDeduplication: $skipDeduplication");
  var result = await loader.calculateRatings(fullRecalc: fullRecalc, skipDeduplication: skipDeduplication);
  if(result.isErr()) {
    console.print("Error calculating ratings: ${result.unwrapErr().message}");
    return;
  }
  console.print("Ratings calculated in ${DateTime.now().difference(start).inSeconds} seconds");
}

Future<void> _clearBayesianOddsCache(Console console, List<MenuArgumentValue> arguments) async {
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
    await _database.clearAllBayesianDeltas();
  }
  else {
    console.print("Deleting Bayesian odds cache for game $gameId");
    await _database.clearBayesianDeltasForGame(gameId);
  }
}

Future<void> _ssaServerToolsMenuLoop(Console console) async {
  await menuLoop(console, _SSAMenuCommand.values,
    menuHeader: "SSA Server Tools",
    commandSelected: (command) async {
      switch(command.command) {
        case _SSAMenuCommand.back:
          return false;
        default:
          return true;
      }
    }
  );
}