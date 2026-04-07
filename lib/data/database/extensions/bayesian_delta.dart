/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/bayesian_delta.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/wager_data.dart';
import 'package:shooting_sports_analyst/util.dart';

extension BayesianDeltaDatabase on AnalystDatabase {
  Future<BayesianDelta?> getBayesianDelta({
    required String memberNumber,
    required int gameId,
    required int predictionSetId,
    required DbPredictionType type,
    required DateTime validAfter,
    required int configHash,
  }) async {
    int? oldConfigHash;
    // Try the fast index first on exact member number.
    final compatibleTypes = type.compatibleTypes;
    var delta = await isar.bayesianDeltas.where()
      .memberNumberPredictionSetIdEqualTo(memberNumber, predictionSetId)
      .filter()
      .gameIdEqualTo(gameId)
      .anyOf(compatibleTypes, (q, type) => q.typeEqualTo(type))
      .lastBetTimestampGreaterThan(validAfter, include: true)
      .findFirst();

    if(delta != null) {
      if(delta.configHash != configHash) {
        oldConfigHash = delta.configHash;
      }
      else {
        return delta;
      }
    }

    // If not found, use the prediction set index to find all deltas for the set and filter on
    // the other properties.
    delta = await isar.bayesianDeltas.where()
      .predictionSetIdEqualTo(predictionSetId)
      .filter()
      .knownMemberNumbersElementEqualTo(memberNumber)
      .anyOf(compatibleTypes, (q, type) => q.typeEqualTo(type))
      .lastBetTimestampGreaterThan(validAfter, include: true)
      .findFirst();

    if(delta != null) {
      if(delta.configHash != configHash) {
        oldConfigHash = delta.configHash;
      }
      else {
        return delta;
      }
    }

    if(oldConfigHash != null) {
      await _clearDeltasWithConfigHash(oldConfigHash);
    }

    return null;
  }

  /// Get all Bayesian deltas for a match prep, sorted by group, then member number, then type, then last bet timestamp,
  /// for
  Future<List<BayesianDelta>> getBayesianDeltasForMatch(int predictionGameId, MatchPrep matchPrep) async {
    final predictionSets = await getPredictionSetsForMatchPrep(matchPrep);
    final deltas = <BayesianDelta>[];

    for(var predictionSet in predictionSets) {
      final setDeltas = await isar.bayesianDeltas.where()
        .predictionSetIdEqualTo(predictionSet.id)
        .filter()
        .gameIdEqualTo(predictionGameId)
        .findAll();

      deltas.addAll(setDeltas);
    }

    // Sort deltas by group, then member number, then type, then last bet timestamp.
    deltas.sort((a, b) {
      if(a.group.value?.uuid != b.group.value?.uuid) {
        return a.group.value?.uuid.compareTo(b.group.value?.uuid ?? "") ?? 0;
      }

      if(a.memberNumber != b.memberNumber) {
        return a.memberNumber.compareTo(b.memberNumber);
      }

      if(a.type != b.type) {
        var types = [a.type, b.type];
        if(!types.every((t) => t == DbPredictionType.percentage || t == DbPredictionType.spread)) {
          return a.type.index.compareTo(b.type.index);
        }
      }

      if(a.predictionSet.value != b.predictionSet.value) {
        return a.predictionSet.value?.created.compareTo(b.predictionSet.value?.created ?? practicalShootingZeroDate) ?? 0;
      }

      return a.computedAt.compareTo(b.computedAt);
    });

    return deltas;
  }

  Future<void> _clearDeltasWithConfigHash(int configHash) async {
    await isar.writeTxn(() async {
      await isar.bayesianDeltas.filter().configHashEqualTo(configHash).deleteAll();
    });
  }

  Future<void> saveBayesianDelta(BayesianDelta delta) async {
    await isar.writeTxn(() async {
      await isar.bayesianDeltas.put(delta);

      delta.game.save();
      delta.group.save();
      delta.project.save();
      delta.rating.save();
      delta.predictionSet.save();
      delta.contributingWagers.save();
    });
  }

  Future<void> clearBayesianDeltasForGame(int gameId) async {
    await isar.writeTxn(() async {
      await isar.bayesianDeltas.where().gameIdEqualTo(gameId).deleteAll();
    });
  }

  Future<void> clearAllBayesianDeltas() async {
    await isar.writeTxn(() async {
      await isar.bayesianDeltas.where().anyId().deleteAll();
    });
  }
}