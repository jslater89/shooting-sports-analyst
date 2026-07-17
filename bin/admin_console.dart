import "dart:io";

import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/config/serialized_config.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/server/providers.dart";

import "admin_console_impl/context.dart";
import "admin_console_impl/export_rating_projects_command.dart";
import "admin_console_impl/import_calculate_projects_command.dart";
import "admin_console_impl/main_menu.dart";

Future<void> main(List<String> args) async {
  final serverDebugProvider = ServerDebugProvider(isMultiIsolate: false);
  FlutterOrNative.debugModeProvider = serverDebugProvider;
  FlutterOrNative.isolateModeProvider = serverDebugProvider;
  SSALogger.consoleOutput = false;

  var console = Console();
  await ConfigLoader().readyFuture;
  var config = ConfigLoader().config;

  final db = AnalystDatabase();
  await db.ready;
  final ctx = AdminConsoleContext(db);

  var ratingContext = await db.getRatingProjectById(config.ratingsContextProjectId ?? -1);
  if(ratingContext != null) {
    ctx.ratingContext = ratingContext;
    console.print("Using ratings context: ${ratingContext.name}");
  }
  else if(config.ratingsContextProjectId != null) {
    console.print("No ratings context found for id ${config.ratingsContextProjectId}");
  }

  if(args.isNotEmpty && args[0] == "IPC") {
    bool fullRecalc = false;
    bool skipDeduplication = true;
    final projectFiles = <String>[];
    for(var i = 1; i < args.length; i++) {
      if(args[i] == "--full-recalc") {
        fullRecalc = true;
      }
      else if(args[i] == "--dedup") {
        skipDeduplication = false;
      }
      else {
        projectFiles.add(args[i]);
      }
    }

    final ok = await ImportCalculateProjectsCommand(ctx).runFiles(
      console,
      projectFiles,
      fullRecalc: fullRecalc,
      skipDeduplication: skipDeduplication,
    );
    exit(ok ? 0 : 1);
  }
  else if(args.isNotEmpty && args[0] == "ERP") {
    final names = args.skip(1).toList();
    final ok = await ExportRatingProjectsCommand(ctx).runNames(console, names);
    exit(ok ? 0 : 1);
  }

  await mainMenuLoop(console, ctx);
  console.write("Goodbye!\n");
}
