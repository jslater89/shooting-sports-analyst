import 'package:collection/collection.dart';
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/user.dart';
import 'package:shooting_sports_analyst/data/prediction_game/prediction_utils.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/util.dart';

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

  Future<MatchPrep?> getMatchPrepById(int id) async {
    return isar.matchPreps.get(id);
  }

  MatchPrep? getMatchPrepByIdSync(int id) {
    return isar.matchPreps.getSync(id);
  }

  Future<List<MatchPrep>> getMatchPreps(PredictionGame game, {bool futureOnly = true, bool hasPredictionsOnly = true}) async {
    var query = game.matchPreps.filter();
    if(futureOnly) {
      query = query.futureMatch((q) => q.dateGreaterThan(DateTime.now()));
    }
    if(hasPredictionsOnly) {
      query = query.predictionSetsIsNotEmpty();
    }
    return query.sortByMatchDateDesc().findAll();
  }

  List<MatchPrep> getMatchPrepsSync(PredictionGame game, {bool futureOnly = true, bool hasPredictionsOnly = true}) {
    var query = game.matchPreps.filter();
    if(futureOnly) {
      query = query.futureMatch((q) => q.dateGreaterThan(DateTime.now()));
    }
    if(hasPredictionsOnly) {
      query = query.predictionSetsIsNotEmpty();
    }
    return query.sortByMatchDateDesc().findAllSync();
  }

  /// Get all prediction game players for a prediction game.
  Future<List<PredictionGamePlayer>> getAllPlayersForGame(PredictionGame game) async {
    return game.users.filter().findAll();
  }

  List<PredictionGamePlayer> getAllPlayersForGameSync(PredictionGame game) {
    return game.users.filter().findAllSync();
  }

  /// Get the prediction game player for a certain user and prediction game.
  Future<PredictionGamePlayer?> getPlayerForUserAndGame(User user, PredictionGame game) async {
    return game.users.filter().serverUser((q) => q.idEqualTo(user.id)).findFirst();
  }

  PredictionGamePlayer? getPlayerForUserAndGameSync(User user, PredictionGame game) {
    return game.users.filter().serverUser((q) => q.idEqualTo(user.id)).findFirstSync();
  }

  /// Get the algorithm prediction for a rating in a match prep, using the latest prediction set if none is provided.
  Future<DbAlgorithmPrediction?> getAlgorithmPredictionForRating(ShooterRating rating, MatchPrep matchPrep, {PredictionSet? predictionSet}) async {
    predictionSet ??= matchPrep.latestPredictionSet();
    return predictionSet?.algorithmPredictions
      .filter()
      .anyOf(rating.knownMemberNumbers, (query, number) => query.memberNumberEqualTo(number))
      .group((q) => q.uuidEqualTo(rating.group.uuid))
      .findFirst();
  }

  DbAlgorithmPrediction? getAlgorithmPredictionForRatingSync(ShooterRating rating, MatchPrep matchPrep, {PredictionSet? predictionSet}) {
    predictionSet ??= matchPrep.latestPredictionSet();
    return predictionSet?.algorithmPredictions
      .filter()
      .anyOf(rating.knownMemberNumbers, (query, number) => query.memberNumberEqualTo(number))
      .group((q) => q.uuidEqualTo(rating.group.uuid))
      .findFirstSync();
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

  /// Save a prediction game transaction to the database.
  ///
  /// If [saveLinks] is true, the transaction's links will be saved.
  Future<PredictionGameTransaction> savePredictionGameTransaction(PredictionGameTransaction transaction, {bool saveLinks = true}) async {
    await isar.writeTxn(() async {
      await isar.predictionGameTransactions.put(transaction);
      if(saveLinks) {
        await transaction.game.save();
        await transaction.user.save();
        await transaction.wager.save();
      }
    });
    return transaction;
  }

  /// Save a prediction game transaction to the database synchronously.
  PredictionGameTransaction savePredictionGameTransactionSync(PredictionGameTransaction transaction) {
    isar.writeTxnSync(() {
      isar.predictionGameTransactions.putSync(transaction);
    });
    return transaction;
  }

  /// Delete prediction game transactions from the database synchronously.
  void deletePredictionGameTransactionsSync(List<PredictionGameTransaction> transactions) {
    isar.writeTxnSync(() {
      isar.predictionGameTransactions.deleteAllSync(transactions.map((t) => t.id).toList());
    });
  }

  /// Save a wager to the database.
  ///
  /// If [saveLinks] is true, the wager's links will be saved, and if this wager
  /// is already saved to the database, any of its transactions that are not yet
  /// saved will be saved first. (If they are already saved, they will not be saved again.)
  ///
  /// If [createWagerTransaction] is true, a wager transaction will be created.
  Future<DbWager> saveWager(DbWager wager, {bool saveLinks = false, bool createWagerTransaction = true}) async {
    if(wager.user.value == null) {
      throw ArgumentError("Wager has no user");
    }

    bool alreadySaved = wager.id != Isar.autoIncrement;
    if(alreadySaved) {
      var transactionsToSave = <PredictionGameTransaction>[];
      if(wager.wagerTransaction.value?.id == Isar.autoIncrement) {
        transactionsToSave.add(wager.wagerTransaction.value!);
      }
      if(wager.payoutTransaction.value?.id == Isar.autoIncrement) {
        transactionsToSave.add(wager.payoutTransaction.value!);
      }
      if(wager.refundTransaction.value?.id == Isar.autoIncrement) {
        transactionsToSave.add(wager.refundTransaction.value!);
      }
      await isar.writeTxn(() async {
        for(var transaction in transactionsToSave) {
          await savePredictionGameTransaction(transaction);
        }
      });
    }

    await isar.writeTxn(() async {
      await isar.dbWagers.put(wager);
      if(saveLinks) {
        await wager.matchPrep.save();
        await wager.game.save();
        await wager.user.save();
        await wager.ratingGroup.save();
        await wager.wagerTransaction.save();
        await wager.payoutTransaction.save();
        await wager.refundTransaction.save();
        await wager.predictionSet.save();
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
    var refundTransaction = wager.refundTransaction.value;
    var netAmount = -(wagerTransaction?.amount ?? 0) + (payoutTransaction?.amount ?? 0) + (refundTransaction?.amount ?? 0);
    var player = wager.user.value;
    await isar.writeTxn(() async {
      if(wagerTransaction != null) {
        await isar.predictionGameTransactions.delete(wagerTransaction.id);
      }

      if(payoutTransaction != null) {
        await isar.predictionGameTransactions.delete(payoutTransaction.id);
      }

      if(refundTransaction != null) {
        await isar.predictionGameTransactions.delete(refundTransaction.id);
      }

      // Everything else is backlinked.
      await isar.dbWagers.delete(wager.id);
    });
    await updatePlayerBalance(player!, -netAmount); // netAmount is negative because we're deleting the wager
  }

  /// Fully deletes a wager from the database, also deleting
  /// associated transactions.
  void deleteWagerSync(DbWager wager) {
    var wagerTransaction = wager.wagerTransaction.value;
    var payoutTransaction = wager.payoutTransaction.value;
    var refundTransaction = wager.refundTransaction.value;
    var netAmount = -(wagerTransaction?.amount ?? 0) + (payoutTransaction?.amount ?? 0) + (refundTransaction?.amount ?? 0);
    var player = wager.user.value;
    isar.writeTxnSync(() {
      if(wagerTransaction != null) {
        isar.predictionGameTransactions.deleteSync(wagerTransaction.id);
      }
      if(payoutTransaction != null) {
        isar.predictionGameTransactions.deleteSync(payoutTransaction.id);
      }
      if(refundTransaction != null) {
        isar.predictionGameTransactions.deleteSync(refundTransaction.id);
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

  /// Get the wagers for a prediction game with various filters.
  Future<List<DbWager>> getWagers({
    required PredictionGame game,
    bool openOnly = false,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) async {
    if(player != null) {
      var query = player.wagers.filter();
      if(openOnly) {
        query = query.statusEqualTo(DbWagerStatus.pending);
      }
      if(matchPrep != null) {
        query = query.matchPrep((q) => q.idEqualTo(matchPrep.id));
      }
      return query.sortByCreatedDesc().findAll();
    }
    else {
      var query = game.wagers.filter();
      if(openOnly) {
        query = query.statusEqualTo(DbWagerStatus.pending);
      }
      if(matchPrep != null) {
        query = query.matchPrep((q) => q.idEqualTo(matchPrep.id));
      }
      return query.sortByCreatedDesc().findAll();
    }
  }

  List<DbWager> getWagersSync({
    required PredictionGame game,
    bool openOnly = false,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) {
    if(player != null) {
      var query = player.wagers.filter();
      if(openOnly) {
        query = query.statusEqualTo(DbWagerStatus.pending);
      }
      if(matchPrep != null) {
        query = query.matchPrep((q) => q.idEqualTo(matchPrep.id));
      }
      return query.sortByCreatedDesc().findAllSync();
    }
    else {
      var query = game.wagers.filter();
      if(openOnly) {
        query = query.statusEqualTo(DbWagerStatus.pending);
      }
      if(matchPrep != null) {
        query = query.matchPrep((q) => q.idEqualTo(matchPrep.id));
      }
      return query.sortByCreatedDesc().findAllSync();
    }
  }

  /// Get the transactions for a prediction game with various filters.
  Future<List<PredictionGameTransaction>> getTransactions({
    required PredictionGame game,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) async {
    var query = game.transactions.filter();
    if(matchPrep != null) {
      query = query.wager((w) => w.matchPrep((q) => q.idEqualTo(matchPrep.id)));
    }
    if(player != null) {
      query = query.user((q) => q.idEqualTo(player.id));
    }
    return query.sortByCreatedDesc().findAll();
  }

  /// Get the transactions for a prediction game with various filters.
  List<PredictionGameTransaction> getTransactionsSync({
    required PredictionGame game,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) {
    var query = game.transactions.filter();
    if(matchPrep != null) {
      query = query.wager((w) => w.matchPrep((q) => q.idEqualTo(matchPrep.id)));
    }
    if(player != null) {
      query = query.user((q) => q.idEqualTo(player.id));
    }
    return query.sortByCreatedDesc().findAllSync();
  }

  /// Audit the transactions for a player, both for total amount and validity (i.e.,
  /// transactions requiring a wager must have a wager).
  ///
  /// Returns true if the audit passes (i.e., the balance is consistent with the transactions).
  ///
  /// If [updateBalance] is true, the player's balance will be updated to the new balance.
  /// If [save] is true, the player will be updated with the new balance and any invalid
  /// transactions will be deleted.
  bool auditPlayerTransactionsSync(PredictionGamePlayer player, {bool updateBalance = true, bool save = true}) {
    var totalDebit = 0.0;
    var totalCredit = 0.0;
    var transactionsToRemove = <PredictionGameTransaction>[];
    for(var transaction in player.transactions) {
      if(transaction.type.shouldHaveWager && transaction.wager.value == null) {
        transactionsToRemove.add(transaction);
        continue;
      }
      if(transaction.type.isDebit) {
        totalDebit += transaction.amount;
      }
      else {
        totalCredit += transaction.amount;
      }
    }
    var newBalance = totalCredit - totalDebit;
    var isConsistent = (newBalance - player.balance).abs() < 0.0001;
    if(updateBalance && !isConsistent) {
      player.balance = newBalance;
    }
    if(save) {
      deletePredictionGameTransactionsSync(transactionsToRemove);
      savePredictionGamePlayerSync(player);
    }
    return isConsistent;
  }

  /// Get the full leaderboard for a prediction game.
  Future<List<PredictionLeaderboardEntry>> getLeaderboard(PredictionGame game, LeaderboardSortMode sortMode) async {
    List<PredictionLeaderboardEntry> entries = [];
    for(var player in game.users) {
      if(player.wagers.isEmpty) {
        // Players with no wagers don't appear on the leaderboard
        continue;
      }
      var leaderboardEntry = PredictionLeaderboardEntry.fromPlayer(player, sortMode);
      entries.add(leaderboardEntry);
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    for(var i = 0; i < entries.length; i++) {
      entries[i].rank = i + 1;
    }
    return entries;
  }

  /// TODO: calculate/store leaderboard ahead of time
}

class PredictionLeaderboardEntry {
  int rank;
  PredictionGamePlayer player;
  double value;

  PredictionLeaderboardEntry.fromPlayer(this.player, LeaderboardSortMode sortMode) : value = calculateValue(player, sortMode), rank = -1;

  static double calculateValue(PredictionGamePlayer player, LeaderboardSortMode sortMode) {
    switch(sortMode) {
      case LeaderboardSortMode.rawBalance:
        return player.balance;
      case LeaderboardSortMode.balancePlusOpenWagers:
        return player.balance + player.wagers.filter().statusEqualTo(DbWagerStatus.pending).findAllSync().map((w) => w.amount).sum;
      case LeaderboardSortMode.balancePlusOpenWagersNetOfTopups:
        return player.balance
          + player.wagers.filter().statusEqualTo(DbWagerStatus.pending).findAllSync().map((w) => w.amount).sum
          - player.transactions.filter().typeEqualTo(PredictionGameTransactionType.topUp).findAllSync().map((t) => t.amount).sum;
      case LeaderboardSortMode.accuracy:
        List<DbWager> closedWagers = player.wagers.filter().statusEqualTo(DbWagerStatus.won).or().statusEqualTo(DbWagerStatus.lost).findAllSync();
        List<DbWager> wonWagers = closedWagers.where((w) => w.status == DbWagerStatus.won).toList();
        if(closedWagers.isEmpty) {
          return 0.0;
        }
        return wonWagers.length / closedWagers.length;
      case LeaderboardSortMode.profitRatio:
        PredictionGameTransaction? initialTopUp = player.transactions.filter().typeEqualTo(PredictionGameTransactionType.topUp).sortByCreated().findFirstSync();
        if(initialTopUp == null) {
          return 0.0;
        }
        var bankroll = player.balance + player.wagers.filter().statusEqualTo(DbWagerStatus.pending).findAllSync().map((w) => w.amount).sum;
        return bankroll / initialTopUp.amount;
      case LeaderboardSortMode.averageOdds:
        var wagers = player.wagers.filter().not().statusEqualTo(DbWagerStatus.voided).findAllSync();
        if(wagers.isEmpty) {
          return 0.0;
        }
        List<double> roundedOdds = [];
        List<double> amounts = [];

        for(var wager in wagers) {
          var decimalOdds = wager.wagerProbability.decimalOdds;
          var rounded = roundDecimalOddsToMoneyline(decimalOdds);
          roundedOdds.add(rounded);
          amounts.add(wager.amount);
        }
        return roundedOdds.weightedAverage(amounts);
    }
  }
}

/// The mode to sort the leaderboard by.
enum LeaderboardSortMode {
  /// The raw balance of the player.
  ///
  /// This is slightly distorted, in that players who consistently miss wagers
  /// will end up getting topped up to their top-up balance.
  rawBalance,

  /// The balance plus the total amount of open wagers.
  balancePlusOpenWagers,

  /// The balance plus the total amount of open wagers, minus the total amount of top-ups.
  ///
  /// This is the most accurate balance measure, as it dings people who are only still in the
  /// game because of top-ups.
  balancePlusOpenWagersNetOfTopups,

  /// The ratio of successful closed wagers to total closed wagers (except voided wagers).
  accuracy,

  /// The player's profit ratio, defined as the multiple of the player's initial balance that
  /// they have earned from wagers.
  profitRatio,

  /// The average odds of all of the player's non-voided wagers.
  averageOdds;

  String formatValue(double value) {
    switch(this) {
      case LeaderboardSortMode.rawBalance:
        return value.toStringAsFixed(2);
      case LeaderboardSortMode.balancePlusOpenWagers:
        return value.toStringAsFixed(2);
      case LeaderboardSortMode.balancePlusOpenWagersNetOfTopups:
        return value.toStringAsFixed(2);
      case LeaderboardSortMode.accuracy:
        return value.asPercentage(decimals: 1, includePercent: true);
      case LeaderboardSortMode.profitRatio:
        return value.toStringAsFixed(3);
      case LeaderboardSortMode.averageOdds:
        return PredictionProbability.fromDecimalOdds(value).moneylineOdds;
    }
  }
}