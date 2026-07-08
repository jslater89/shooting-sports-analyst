/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/migrations/migration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/migration.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("ResavePrecalculatedScoresMigration");

class ResavePrecalculatedScoresMigration extends Migration {
  @override
  MigrationRecord get record => MigrationRecord(name: "resave_precalculated_scores", applied: DateTime.now());

  @override
  Future<void> doMigration(AnalystDatabase db) async {
    var matchIds = await db.isar.dbShootingMatchs.where().anyId().idProperty().findAll();

    for(var (i, matchId) in matchIds.indexed) {
      var match = await db.isar.dbShootingMatchs.get(matchId);
      if(match == null) {
        _log.w("Match $matchId not found");
        continue;
      }
      var hydratedRes = await match.hydrate();
      if(hydratedRes.isErr()) {
        _log.e("Error hydrating match $matchId", error: hydratedRes.unwrapErr());
        continue;
      }

      var hydrated = hydratedRes.unwrap();
      try {
        await db.saveMatch(hydrated);
      }
      catch(e, stackTrace) {
        _log.e("Error saving match $matchId", error: e, stackTrace: stackTrace);
        _log.e("Failed source IDs: ${match.eventName} (${match.sport.name}): ${match.sourceCode}/${match.sourceIds}");
        continue;
      }
      _log.i("Saved $i/${matchIds.length} matches - ${match.eventName}");
    }
  }
}