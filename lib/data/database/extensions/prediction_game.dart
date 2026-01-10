import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';

extension PredictionGameExtension on AnalystDatabase {
  /// Get a prediction game by its ID.
  Future<PredictionGame?> getPredictionGame(int id) async {
    return isar.predictionGames.where().idEqualTo(id).findFirst();
  }

  /// Get a prediction game by its ID synchronously.
  PredictionGame? getPredictionGameSync(int id) {
    return isar.predictionGames.where().idEqualTo(id).findFirstSync();
  }

  /// Get all prediction games.
  Future<List<PredictionGame>> getAllPredictionGames() async {
    return isar.predictionGames.where().anyId().sortByCreatedDesc().findAll();
  }

  /// Get all prediction games synchronously.
  List<PredictionGame> getAllPredictionGamesSync() {
    return isar.predictionGames.where().anyId().sortByCreatedDesc().findAllSync();
  }

  Future<PredictionGame> savePredictionGame(PredictionGame predictionGame, {bool saveLinks = false}) async {
    await isar.writeTxn(() async {
      await isar.predictionGames.put(predictionGame);
      if(saveLinks) {
        await predictionGame.matchPreps.save();
        await predictionGame.users.save();
        await predictionGame.wagers.save();
      }
    });

    return predictionGame;
  }

  PredictionGame savePredictionGameSync(PredictionGame predictionGame) {
    isar.writeTxnSync(() {
      isar.predictionGames.putSync(predictionGame);
    });
    return predictionGame;
  }

  /// Save a prediction game player to the database.
  ///
  /// If [newTransactions] is provided, they will be saved to the database and added
  /// to the player's transactions. Transactions not currently in the database must be
  /// provided in [newTransactions]. (Or use [savePredictionGamePlayerSync] instead to
  /// save the object hierarchy in one call.)
  ///
  /// If [saveLinks] is true, the player's DB links will be saved. Non-null [newTransactions]
  /// forces [saveLinks] to be true.
  Future<PredictionGamePlayer> savePredictionGamePlayer(PredictionGamePlayer player, {
    List<PredictionGameTransaction>? newTransactions,
    bool saveLinks = true,
  }) async {
    if(newTransactions != null) {
      await isar.writeTxn(() async {
        await isar.predictionGameTransactions.putAll(newTransactions);
      });
      player.transactions.addAll(newTransactions);
      saveLinks = true;
    }
    await isar.writeTxn(() async {
      await isar.predictionGamePlayers.put(player);
      if(saveLinks) {
        await player.game.save();
        await player.serverUser.save();
        await player.wagers.save();
        await player.transactions.save();
      }
    });
    return player;
  }

  /// Save a prediction game player to the database synchronously, along with its linked objects.
  PredictionGamePlayer savePredictionGamePlayerSync(PredictionGamePlayer player) {
    isar.writeTxnSync(() {
      isar.predictionGamePlayers.putSync(player);
    });
    return player;
  }

  /// Delete a player and all its owned objects (wagers and transactions) from the database.
  Future<void> deletePredictionGamePlayer(PredictionGamePlayer player) async {
    await isar.writeTxn(() async {
      await player.transactions.filter().deleteAll();
      await player.wagers.filter().deleteAll();
      await isar.predictionGamePlayers.delete(player.id);
    });
  }

  /// Delete a player and all its owned objects (wagers and transactions) from the database synchronously.
  void deletePredictionGamePlayerSync(PredictionGamePlayer player) {
    isar.writeTxnSync(() {
      player.transactions.filter().deleteAllSync();
      player.wagers.filter().deleteAllSync();
      isar.predictionGamePlayers.deleteSync(player.id);
    });
  }

  Future<DbWager> saveWager(DbWager wager, {bool saveLinks = false, bool createWagerTransaction = true}) async {
    if(wager.user.value == null) {
      throw ArgumentError("Wager has no user");
    }
    await isar.writeTxn(() async {
      await isar.dbWagers.put(wager);
      if(saveLinks) {
        await wager.matchPrep.save();
        await wager.game.save();
        await wager.user.save();
        await wager.ratingGroup.save();
      }
    });

    if(createWagerTransaction) {
      var transaction = PredictionGameTransaction(
        type: PredictionGameTransactionType.wager,
        amount: wager.amount,
        created: DateTime.now(),
      );
      transaction.game.value = wager.game.value;
      transaction.user.value = wager.user.value;
      transaction.wager.value = wager;

      wager.wagerTransaction.value = transaction;
      await isar.writeTxn(() async {
        await isar.predictionGameTransactions.put(transaction);
        await transaction.game.save();
        await transaction.user.save();
        await transaction.wager.save();
        await wager.wagerTransaction.save();
      });
      updatePlayerBalance(wager.user.value!, -wager.amount);
    }
    return wager;
  }

  DbWager saveWagerSync(DbWager wager, {bool createWagerTransaction = true}) {
    if(wager.user.value == null) {
      throw ArgumentError("Wager has no user");
    }
    if(createWagerTransaction) {
      var transaction = PredictionGameTransaction(
        type: PredictionGameTransactionType.wager,
        amount: wager.amount,
        created: DateTime.now(),
      );
      transaction.game.value = wager.game.value;
      transaction.user.value = wager.user.value;
      transaction.wager.value = wager;
      wager.wagerTransaction.value = transaction;
      updatePlayerBalanceSync(wager.user.value!, -wager.amount);
    }
    isar.writeTxnSync(() {
      isar.dbWagers.putSync(wager);
    });
    return wager;
  }

  /// Fully deletes a wager from the database, also deleting
  /// associated transactions.
  Future<void> deleteWager(DbWager wager) async {
    var wagerTransaction = wager.wagerTransaction.value;
    var payoutTransaction = wager.payoutTransaction.value;
    var netAmount = -(wagerTransaction?.amount ?? 0) + (payoutTransaction?.amount ?? 0);
    var player = wager.user.value;
    await isar.writeTxn(() async {
      if(wagerTransaction != null) {
        await isar.predictionGameTransactions.delete(wagerTransaction.id);
      }

      // Payout transaction link is used for both payout and refund transactions.
      if(payoutTransaction != null) {
        await isar.predictionGameTransactions.delete(payoutTransaction.id);
      }

      // Everything else is backlinked.
      await isar.dbWagers.delete(wager.id);
    });
    updatePlayerBalance(player!, -netAmount); // netAmount is negative because we're deleting the wager
  }

  /// Fully deletes a wager from the database, also deleting
  /// associated transactions.
  void deleteWagerSync(DbWager wager) {
    var wagerTransaction = wager.wagerTransaction.value;
    var payoutTransaction = wager.payoutTransaction.value;
    var netAmount = -(wagerTransaction?.amount ?? 0) + (payoutTransaction?.amount ?? 0);
    var player = wager.user.value;
    isar.writeTxnSync(() {
      if(wager.wagerTransaction.value != null) {
        isar.predictionGameTransactions.deleteSync(wager.wagerTransaction.value!.id);
      }
      if(wager.payoutTransaction.value != null) {
        isar.predictionGameTransactions.deleteSync(wager.payoutTransaction.value!.id);
      }
      isar.dbWagers.deleteSync(wager.id);
    });
    updatePlayerBalanceSync(player!, -netAmount); // netAmount is negative because we're deleting the wager
  }

  Future<PredictionGamePlayer> updatePlayerBalance(PredictionGamePlayer player, double amount) async {
    player.balance += amount;
    return savePredictionGamePlayer(player);
  }

  PredictionGamePlayer updatePlayerBalanceSync(PredictionGamePlayer player, double amount) {
    player.balance += amount;
    return savePredictionGamePlayerSync(player);
  }
}