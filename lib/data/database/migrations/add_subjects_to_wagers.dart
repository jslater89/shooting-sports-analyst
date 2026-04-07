/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/migrations/migration.dart';
import 'package:shooting_sports_analyst/data/database/schema/migration.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("SubjectWagerMigration");

class AddSubjectsToWagers extends Migration {
  @override
  Future<void> doMigration(AnalystDatabase db) async {
    // resave all wagers to pick up the subject member numbers
    var wagers = await db.isar.dbWagers.where().findAll();
    for(var wager in wagers) {
      for(var leg in wager.legs) {
        var targetRating = await leg.target.getShooterRating(db);
        var underdogRating = await leg.underdog?.getShooterRating(db);

        if(targetRating != null) {
          leg.target.knownMemberNumbers = [...targetRating.knownMemberNumbers];
        }
        if(underdogRating != null) {
          leg.underdog!.knownMemberNumbers = [...underdogRating.knownMemberNumbers];
        }
      }

      await db.isar.dbWagers.put(wager);
    }
  }

  @override
  MigrationRecord get record => MigrationRecord(
    name: 'add_subjects_to_wagers',
    applied: DateTime.now(),
  );
}

/// The migration above created new wager transactions for every wager.
///
/// For each wager: query all stake transactions, pick the earliest one to
/// set on the wager, and delete the extras.
class FixWagerTransactions extends Migration {
  @override
  Future<void> doMigration(AnalystDatabase db) async {
    var wagers = await db.isar.dbWagers.where().findAll();
    for(var wager in wagers) {
      var transactions = await db.isar
        .predictionGameTransactions
        .filter()
        .typeEqualTo(PredictionGameTransactionType.wager)
        .wager((w) => w.idEqualTo(wager.id))
        .sortByCreated()
        .findAll();
      if(transactions.length > 1) {
        _log.v("Wager ${wager.id} has ${transactions.length} stake transactions");
        _log.v("Setting wager transaction to ${transactions.first.id} (${transactions.first.created})");
        _log.v("Deleting ${transactions.length - 1} extra transactions");
        wager.wagerTransaction.value = transactions.first;
        await db.isar.writeTxn(() async {
          await wager.wagerTransaction.save();
        });
        await db.isar.writeTxn(() async {
          for(var i = 1; i < transactions.length; i++) {
            await db.isar.predictionGameTransactions.delete(transactions[i].id);
          }
        });
      }
    }

    var predictionGames = await db.isar.predictionGames.where().findAll();
    for(var game in predictionGames) {
      var manager = PredictionGameManager(predictionGame: game);
      for(var player in game.users) {
        var auditResult = await manager.auditUserBalance(player);
        if(auditResult.balanceChange != 0 || auditResult.linksChanged) {
          _log.i("Player ${player.id} balance change: ${auditResult.balanceChange.toStringAsFixed(2)}");
        }
      }
    }
  }

  @override
  MigrationRecord get record => MigrationRecord(
    name: 'fix_wager_transactions',
    applied: DateTime.now(),
  );
}