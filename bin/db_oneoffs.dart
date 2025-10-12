// ignore_for_file: unused_local_variable, unused_element
// ignore_for_file: unused_import

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:data/stats.dart' show WeibullDistribution;
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/standardized_maximum_scaler.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/classifier_import.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/icore_export_converter.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:shooting_sports_analyst/version.dart';

import 'db_oneoff_impl/prediction_percentages.dart';
import 'db_oneoff_impl/predictions_to_odds.dart';
import 'db_oneoff_impl/stacked_labeled_progress_bar_test.dart';
import 'db_oneoff_impl/stage_counts_by_year_command.dart';
import 'server.dart';
import 'db_oneoff_impl/base.dart';
import 'db_oneoff_impl/tom_castro_command.dart';
import 'db_oneoff_impl/match_bump_gms_command.dart';
import 'db_oneoff_impl/does_my_query_work_command.dart';
import 'db_oneoff_impl/lady_90_percent_finishes_command.dart';
import 'db_oneoff_impl/analyze_icore_dump_command.dart';
import 'db_oneoff_impl/import_icore_dump_command.dart';
import 'db_oneoff_impl/winning_points_by_date_command.dart';
import 'db_oneoff_impl/stage_size_analysis_command.dart';

late SSALogger _log = SSALogger("DbOneoffs");

Future<void> main() async {
  SSALogger.debugProvider = ServerDebugProvider();
  SSALogger.consoleOutput = false;
  SSALogger.fileOutput = true;
  await _log.ready;

  await ConfigLoader().readyFuture;
  var config = ConfigLoader().config;

  var db = await AnalystDatabase();
  await db.ready;

  var console = Console();
  await menuLoop(console, [
    TomCastroCommand(db),
    MatchBumpGmsCommand(db),
    DoesMyQueryWorkCommand(db),
    Lady90PercentFinishesCommand(db),
    AnalyzeIcoreDumpCommand(db),
    ImportIcoreDumpCommand(db),
    WinningPointsByDateCommand(db),
    StageSizeAnalysisCommand(db),
    StageCountsByYearCommand(db),
    PredictionsToOddsCommand(db),
    PredictionPercentagesCommand(db),
    QuitCommand(),
  ], menuHeader: "DB Oneoffs ${VersionInfo.version}", commandSelected: (command) async {
    switch(command.command?.runtimeType) {
      case QuitCommand:
        return false;
      default:
        return true;
    }
  });
}

class QuitCommand extends MenuCommand {
  @override
  final String key = "Q";
  @override
  final String title = "Quit";
}
