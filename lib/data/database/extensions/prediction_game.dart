/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

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
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

// ignore: unused_element
final _log = SSALogger("PredictionGameDb");

/// Whether [prediction] is the algorithm row for [rating] scored on [scoringContext].
///
/// Override rows ([DbAlgorithmPrediction.scoringGroupUuid] set) match [scoringContext] via that
/// field. Legacy rows (no explicit scoring group) match when [DbAlgorithmPrediction.groupUuid]
/// equals [scoringContext].
bool _algorithmPredictionMatchesRatingAndScoringContext({
  required DbAlgorithmPrediction prediction,
  required ShooterRating rating,
  required RatingGroup scoringContext,
}) {
  if(!rating.knownMemberNumbers.contains(prediction.memberNumber)) {
    return false;
  }
  final ratingGroupUuid = prediction.groupUuid ?? prediction.group.value?.uuid;
  if(ratingGroupUuid != rating.group.uuid) {
    return false;
  }
  if(prediction.scoringGroupUuid != null) {
    return prediction.scoringGroupUuid == scoringContext.uuid;
  }
  return ratingGroupUuid == scoringContext.uuid;
}

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

  Future<List<PredictionGame>> getPredictionGamesForMatchPrep(MatchPrep matchPrep) async {
    // Find all prediction games that reference the given match prep.
    return isar.predictionGames.where().filter()
      .matchPreps((q) => q.idEqualTo(matchPrep.id))
      .findAll();
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

  Future<void> deletePredictionGame(PredictionGame predictionGame) async {
    await isar.writeTxn(() async {
      await predictionGame.users.filter().deleteAll();
      await predictionGame.wagers.filter().deleteAll();
      await predictionGame.transactions.filter().deleteAll();
      await isar.predictionGames.delete(predictionGame.id);
    });
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

  Future<List<PredictionSet>> getPredictionSetsForMatchPrep(MatchPrep matchPrep) async {
    return matchPrep.predictionSets.filter().sortByCreatedDesc().findAll();
  }

  List<PredictionSet> getPredictionSetsForMatchPrepSync(MatchPrep matchPrep) {
    return matchPrep.predictionSets.filter().sortByCreatedDesc().findAllSync();
  }

  /// Get all prediction game players for a user.
  Future<List<PredictionGamePlayer>> getAllPlayersForUser(User user, {bool onlyActiveGames = true}) async {
    return user.predictionGamePlayers.filter().findAll();
  }

  /// Get all prediction game players for a user synchronously.
  List<PredictionGamePlayer> getAllPlayersForUserSync(User user, {bool onlyActiveGames = true}) {
    return user.predictionGamePlayers.filter().findAllSync();
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

  Future<PredictionGamePlayer?> getPlayerForIdAndGame(int playerId, PredictionGame game) async {
    return game.users.filter().idEqualTo(playerId).findFirst();
  }

  PredictionGamePlayer? getPlayerForIdAndGameSync(int playerId, PredictionGame game) {
    return game.users.filter().idEqualTo(playerId).findFirstSync();
  }

  /// Get the algorithm prediction for a rating in a match prep, using the latest prediction set if none is provided.
  ///
  /// [scoringContext] is the group the prediction should be scored against (e.g. the wager's
  /// scoring group or the active UI tab). It may differ from [ShooterRating.group] when predictions
  /// use a combined rating source (LO/CO) for a division-specific tab (CO).
  Future<DbAlgorithmPrediction?> getAlgorithmPredictionForRating(ShooterRating rating, MatchPrep matchPrep, RatingGroup scoringContext, {PredictionSet? predictionSet}) async {
    predictionSet ??= matchPrep.latestPredictionSet();
    if(predictionSet == null) {
      return null;
    }
    await predictionSet.algorithmPredictions.load();
    return predictionSet.algorithmPredictions.firstWhereOrNull((prediction) =>
      _algorithmPredictionMatchesRatingAndScoringContext(
        prediction: prediction,
        rating: rating,
        scoringContext: scoringContext,
      ));
  }

  /// Synchronous variant of [getAlgorithmPredictionForRating].
  DbAlgorithmPrediction? getAlgorithmPredictionForRatingSync(ShooterRating rating, MatchPrep matchPrep, RatingGroup scoringContext, {PredictionSet? predictionSet}) {
    predictionSet ??= matchPrep.latestPredictionSet();
    if(predictionSet == null) {
      return null;
    }
    predictionSet.algorithmPredictions.loadSync();
    return predictionSet.algorithmPredictions.firstWhereOrNull((prediction) =>
      _algorithmPredictionMatchesRatingAndScoringContext(
        prediction: prediction,
        rating: rating,
        scoringContext: scoringContext,
      ));
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
        for(var transaction in newTransactions) {
          await transaction.game.save();
          await transaction.wager.save();
        }
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
        await wager.scoringGroup.save();
        await wager.wagerTransaction.save();
        await wager.payoutTransaction.save();
        await wager.refundTransaction.save();
        await wager.predictionSet.save();
      }
    });

    if(createWagerTransaction && wager.wagerTransaction.value == null) {
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
    if(createWagerTransaction && wager.wagerTransaction.value == null) {
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
    DbShooterRating? subject,
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
      if(subject != null) {
        query = query.anyOf(subject.knownMemberNumbers, (q, number) => q.subjectMemberNumbersElementEqualTo(number));
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
      if(subject != null) {
        query = query.anyOf(subject.knownMemberNumbers, (q, number) => q.subjectMemberNumbersElementEqualTo(number));
      }
      return query.sortByCreatedDesc().findAll();
    }
  }

  List<DbWager> getWagersSync({
    required PredictionGame game,
    bool openOnly = false,
    DbShooterRating? subject,
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
      if(subject != null) {
        query = query.anyOf(subject.knownMemberNumbers, (q, number) => q.subjectMemberNumbersElementEqualTo(number));
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
      if(subject != null) {
        query = query.anyOf(subject.knownMemberNumbers, (q, number) => q.subjectMemberNumbersElementEqualTo(number));
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
  /// Returns true if the audit passes (i.e., the balance is consistent with the transactions
  /// and all transactions are properly linked to the player and game).
  ///
  /// If [updateBalance] is true, the player's balance will be updated to the new balance.
  /// If [save] is true, the player will be updated with the new balance, any invalid transactions
  /// will be deleted, and any transactions without proper links will be linked.
  bool auditPlayerTransactionsSync(PredictionGamePlayer player, {bool updateBalance = true, bool save = true}) {
    var totalDebit = 0.0;
    var totalCredit = 0.0;
    var transactionsToRemove = <PredictionGameTransaction>[];
    var transactionsToSave = <PredictionGameTransaction>[];
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

      bool needsSave = false;
      if(transaction.user.value?.id != player.id) {
        transaction.user.value = player;
        needsSave = true;
      }
      if(transaction.game.value?.id != player.game.value?.id) {
        transaction.game.value = player.game.value;
        needsSave = true;
      }
      if(needsSave) {
        transactionsToSave.add(transaction);
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
      for(var transaction in transactionsToSave) {
        savePredictionGameTransactionSync(transaction);
      }
    }
    return isConsistent && transactionsToSave.isEmpty;
  }

  /// Get the full leaderboard for a prediction game.
  Future<List<PredictionLeaderboardEntry>> getLeaderboard(
    PredictionGame game,
    LeaderboardSortMode sortMode,
    {
      List<DbWager>? preloadedWagers,
      List<PredictionGameTransaction>? preloadedTransactions,
    }
  ) async {
    List<PredictionLeaderboardEntry> entries = [];
    var players = await getAllPlayersForGame(game);
    for(var player in players) {
      var playerWagerCount = await player.wagers.count();
      if(playerWagerCount == 0) {
        // Players with no wagers don't appear on the leaderboard
        continue;
      }
      List<DbWager>? playerWagers = preloadedWagers?.where((w) => w.user.value?.id == player.id).toList();
      List<PredictionGameTransaction>? playerTransactions = preloadedTransactions?.where((t) => t.user.value?.id == player.id).toList();
      if(playerWagers != null && playerWagers.isEmpty) {
        // Players with no wagers don't appear on the leaderboard
        continue;
      }
      var leaderboardEntry = PredictionLeaderboardEntry.fromPlayer(player, sortMode, preloadedWagers: playerWagers, preloadedTransactions: playerTransactions);
      entries.add(leaderboardEntry);
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    for(var i = 0; i < entries.length; i++) {
      entries[i].rank = i + 1;
    }
    return entries;
  }

  /// TODO: calculate/store leaderboard ahead of time


  /// Get the list of disabled match preps for a prediction game.
  Future<List<int>?> getDisabledMatchPreps(PredictionGame game) async {
    return isar.predictionGames.where().idEqualTo(game.id).disabledMatchPrepsProperty().findFirst();
  }

  /// Get the list of disabled match preps for a prediction game synchronously.
  List<int>? getDisabledMatchPrepsSync(PredictionGame game) {
    return isar.predictionGames.where().idEqualTo(game.id).disabledMatchPrepsProperty().findFirstSync();
  }
}

class PredictionLeaderboardEntry {
  int rank;
  PredictionGamePlayer player;
  double value;

  PredictionLeaderboardEntry.fromPlayer(
    this.player,
    LeaderboardSortMode sortMode,
    {
      List<DbWager>? preloadedWagers,
      List<PredictionGameTransaction>? preloadedTransactions,
    }
  ) : value = calculateValue(player, sortMode, preloadedWagers: preloadedWagers, preloadedTransactions: preloadedTransactions), rank = -1;

  /// Calculate the value of a player for a given sort mode.
  ///
  /// If [preloadedWagers] is provided, it will be used to calculate the value
  /// instead of querying the database. It must contain only the player's wagers.
  static double calculateValue(
    PredictionGamePlayer player,
    LeaderboardSortMode sortMode,
    {
      List<DbWager>? preloadedWagers,
      List<PredictionGameTransaction>? preloadedTransactions,
    }
  ) {
    switch(sortMode) {
      case LeaderboardSortMode.rawBalance:
        return player.balance;
      case LeaderboardSortMode.balancePlusOpenWagers:
        List<DbWager> openWagers;
        if(preloadedWagers != null) {
          openWagers = preloadedWagers.where((w) => w.status == DbWagerStatus.pending).toList();
        }
        else {
          openWagers = player.wagers.filter().statusEqualTo(DbWagerStatus.pending).findAllSync();
        }
        return player.balance + openWagers.map((w) => w.amount).sum;
      case LeaderboardSortMode.balancePlusOpenWagersNetOfTopups:
        List<DbWager> pendingWagers;
        if(preloadedWagers != null) {
          pendingWagers = preloadedWagers.where((w) => w.status == DbWagerStatus.pending).toList();
        }
        else {
          pendingWagers = player.wagers.filter().statusEqualTo(DbWagerStatus.pending).findAllSync();
        }

        List<PredictionGameTransaction> topUpTransactions;
        if(preloadedTransactions != null) {
          topUpTransactions = preloadedTransactions.where((t) => t.type == PredictionGameTransactionType.topUp).toList();
        }
        else {
          topUpTransactions = player.transactions.filter().typeEqualTo(PredictionGameTransactionType.topUp).findAllSync();
        }
        // _log.v("player.balance: ${player.balance}");
        // _log.v("pendingWagers.map((w) => w.amount).sum: ${pendingWagers.map((w) => w.amount).sum}");
        // _log.v("topUpTransactions.map((t) => t.amount).sum: ${topUpTransactions.map((t) => t.amount).sum}");
        return player.balance
          + pendingWagers.map((w) => w.amount).sum
          - topUpTransactions.map((t) => t.amount).sum;
      case LeaderboardSortMode.accuracy:
        List<DbWager> closedWagers;
        if(preloadedWagers != null) {
          closedWagers = preloadedWagers.where((w) => w.status == DbWagerStatus.won || w.status == DbWagerStatus.lost).toList();
        }
        else {
          closedWagers = player.wagers.filter().statusEqualTo(DbWagerStatus.won).or().statusEqualTo(DbWagerStatus.lost).findAllSync();
        }
        List<DbWager> wonWagers = closedWagers.where((w) => w.status == DbWagerStatus.won).toList();
        if(closedWagers.isEmpty) {
          return 0.0;
        }
        return wonWagers.length / closedWagers.length;
      case LeaderboardSortMode.profitRatio:
        List<DbWager> wagersOfInterest;
        if(preloadedWagers != null) {
          wagersOfInterest = preloadedWagers
            .where((w) => w.status == DbWagerStatus.won || w.status == DbWagerStatus.lost).toList();
        }
        else {
          wagersOfInterest = player.wagers
            .filter()
            .statusEqualTo(DbWagerStatus.won)
            .or()
            .statusEqualTo(DbWagerStatus.lost)
            .findAllSync();
        }
        if(wagersOfInterest.isEmpty) {
          return 0.0;
        }
        double wonAmount = 0.0;
        double totalStake = 0.0;
        for(var wager in wagersOfInterest) {
          if(wager.status == DbWagerStatus.won) {
            wonAmount += wager.payout();
          }
          totalStake += wager.amount;
        }
        return wonAmount / totalStake;

      case LeaderboardSortMode.sharpness:
        List<DbWager> closedWagers;
        if(preloadedWagers != null) {
          closedWagers = preloadedWagers.where((w) => w.status == DbWagerStatus.won || w.status == DbWagerStatus.lost).toList();
        }
        else {
          closedWagers = player.wagers.filter().statusEqualTo(DbWagerStatus.won).or().statusEqualTo(DbWagerStatus.lost).findAllSync();
        }
        List<DbWager> wonWagers = closedWagers.where((w) => w.status == DbWagerStatus.won).toList();
        if(closedWagers.isEmpty) {
          return 0.0;
        }
        final actualAccuracy = wonWagers.length;
        final expectedAccuracy = closedWagers.map((w) => w.wagerProbability.rawProbability).sum;
        return actualAccuracy / expectedAccuracy;

      case LeaderboardSortMode.averageOdds:
        List<DbWager> wagers;
        if(preloadedWagers != null) {
          wagers = preloadedWagers.where((w) => w.status != DbWagerStatus.voided).toList();
        }
        else {
          wagers = player.wagers.filter().not().statusEqualTo(DbWagerStatus.voided).findAllSync();
        }
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

  /// The sharpness of the player, expressed as their raw accuracy successful_closed / total_closed,
  /// divided by the expected number of hits (the average implied probability of all closed wagers).
  sharpness,

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
      case LeaderboardSortMode.sharpness:
        return value.toStringAsFixed(3);
      case LeaderboardSortMode.profitRatio:
        return value.toStringAsFixed(3);
      case LeaderboardSortMode.averageOdds:
        if(value == 0.0) {
          return "n/a";
        }
        return PredictionProbability.fromDecimalOdds(value, houseEdge: 0.0).moneylineOdds;
    }
  }
}