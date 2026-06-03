/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/migrations/migration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/migration.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("BackfillWagerScoringGroups");

/// Restores [DbWager.scoringGroup] links lost when the Isar link was renamed from
/// `ratingGroup` to `scoringGroup`.
///
/// Infers the scoring group from the wager's linked [DbWager.predictionSet] when
/// possible, then falls back to the leg target's stored [DbPredictionTarget.groupUuid].
class BackfillWagerScoringGroups extends Migration {
  @override
  Future<void> doMigration(AnalystDatabase db) async {
    var wagers = await db.isar.dbWagers.where().findAll();
    var backfilled = 0;
    var skipped = 0;
    var failed = 0;

    for(var wager in wagers) {
      await wager.scoringGroup.load();
      if(wager.scoringGroup.value != null) {
        skipped++;
        continue;
      }

      var scoringGroup = await _inferScoringGroup(db, wager);
      if(scoringGroup == null) {
        failed++;
        _log.w("Could not infer scoring group for wager ${wager.id}");
        continue;
      }

      wager.scoringGroup.value = scoringGroup;
      await db.saveWager(wager, saveLinks: true, createWagerTransaction: false);
      backfilled++;
    }

    _log.i("Backfilled scoring group on $backfilled wagers ($skipped already set, $failed unresolved)");
  }

  Future<RatingGroup?> _inferScoringGroup(AnalystDatabase db, DbWager wager) async {
    await wager.predictionSet.load();
    var predictionSet = wager.predictionSet.value;
    if(predictionSet != null) {
      var fromSet = await _inferFromPredictionSet(wager, predictionSet);
      if(fromSet != null) {
        return fromSet;
      }
    }

    return _inferFromLegTarget(db, wager.legs.first.target);
  }

  Future<RatingGroup?> _inferFromPredictionSet(DbWager wager, PredictionSet predictionSet) async {
    var memberNumbers = _memberNumbersForWager(wager);
    if(memberNumbers.isEmpty) {
      return null;
    }

    await predictionSet.algorithmPredictions.load();
    var target = wager.legs.first.target;
    var predictions = predictionSet.algorithmPredictions.where((prediction) {
      if(!memberNumbers.contains(prediction.memberNumber)) {
        return false;
      }
      if(target.groupUuid.isNotEmpty && prediction.groupUuid != target.groupUuid) {
        return false;
      }
      return true;
    }).toList();

    if(predictions.isEmpty) {
      return null;
    }

    if(predictions.length > 1) {
      _log.w(
        "Wager ${wager.id} matched ${predictions.length} predictions in set ${predictionSet.id}; "
        "using first match",
      );
    }

    return predictions.first.effectiveScoringGroup;
  }

  Future<RatingGroup?> _inferFromLegTarget(AnalystDatabase db, DbPredictionTarget target) async {
    if(target.groupUuid.isNotEmpty) {
      var group = await db.isar.ratingGroups.filter().uuidEqualTo(target.groupUuid).findFirst();
      if(group != null) {
        return group;
      }
    }

    var rating = await target.getShooterRating(db);
    return rating?.group.value;
  }

  Set<String> _memberNumbersForWager(DbWager wager) {
    return wager.legs
      .map((leg) => leg.target)
      .expand((target) => target.knownMemberNumbers.isNotEmpty ? target.knownMemberNumbers : [target.memberNumber])
      .where((number) => number.isNotEmpty)
      .toSet();
  }

  @override
  MigrationRecord get record => MigrationRecord(
    name: 'backfill_wager_scoring_groups',
    applied: DateTime.now(),
  );
}
