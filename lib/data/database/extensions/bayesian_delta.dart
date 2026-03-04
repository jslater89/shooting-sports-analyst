import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/bayesian_delta.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/wager_data.dart';

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
}