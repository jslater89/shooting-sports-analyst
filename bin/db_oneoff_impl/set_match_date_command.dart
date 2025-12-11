/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/


import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/classifier_import.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class SetMatchDatesCommand extends DbOneoffCommand {
  SetMatchDatesCommand(AnalystDatabase db) : super(db);

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    DateTime commandRunTime = DateTime.now();
    var matches = await db.getAllMatches();
    int updated = 0;
    var progressBar = LabeledProgressBar(maxValue: matches.length, initialLabel: "Updating matches...", canHaveErrors: false);
    for(var match in matches) {
      DateTime? latestTime = null;
      List<DbMatchEntryBase> shooters = [];
      if(match.shootersStoredSeparately) {
        shooters = match.shooterLinks.toList();
      }
      else {
        shooters = match.shooters.toList();
      }

      for(var shooter in shooters) {
        for(var score in shooter.scores) {
          if(latestTime == null || score.modified!.isAfter(latestTime)) {
            latestTime = score.modified;
          }
        }
      }
      if(match.sourceCode != ClassifierImporter.sourceCode) {
        latestTime ??= commandRunTime;
      }
      else {
        latestTime = practicalShootingZeroDate;
      }
      match.sourceLastUpdated = latestTime;
      await db.isar.writeTxn(() async {
        await db.isar.dbShootingMatchs.put(match);
      });
      updated++;
      progressBar.tick("Updated $updated matches of ${matches.length} total");
    }
    progressBar.complete();
    console.writeLine("Updated $updated matches of ${matches.length} total");
  }

  @override
  String get key => "SMD";

  @override
  String get title => "Set Match Dates";
}