import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("PredictionGameManager");

class PredictionGameManager {
  PredictionGameManager({required this.predictionGame});

  final db = AnalystDatabase();
  PredictionGame predictionGame;

    /// Add a match prep to the prediction game.
  Future<void> addMatchPrep(MatchPrep matchPrep) async {
    predictionGame.matchPreps.add(matchPrep);
    await db.savePredictionGame(predictionGame, saveLinks: true);
    await loadPredictionGame();
  }

  // ======================
  // Leaderboard
  // ======================

  /// Get the leaderboard for the prediction game.
  Future<List<PredictionLeaderboardEntry>> getLeaderboard(LeaderboardSortMode sortMode) async {
    return db.getLeaderboard(predictionGame, sortMode);
  }

  // ======================
  // Player management
  // ======================

  Future<void> savePlayer(PredictionGamePlayer player, {List<PredictionGameTransaction>? newTransactions}) async {
    await db.savePredictionGamePlayer(player, newTransactions: newTransactions, saveLinks: true);
    await loadPredictionGame();
  }

  void savePlayerSync(PredictionGamePlayer player) {
    db.savePredictionGamePlayerSync(player);
    loadPredictionGameSync();
  }

  Future<void> deletePlayer(PredictionGamePlayer player) async {
    await db.deletePredictionGamePlayer(player);
    await loadPredictionGame();
  }

  void deletePlayerSync(PredictionGamePlayer player) {
    db.deletePredictionGamePlayerSync(player);
    loadPredictionGameSync();
  }

  Future<void> addWager(DbWager wager) async {
    // It's already backlinked to everything else, so we can just save it
    // and its links.
    await db.saveWager(wager, saveLinks: true, createWagerTransaction: true);
    await loadPredictionGame();
  }

  void addWagerSync(DbWager wager) {
    db.saveWagerSync(wager, createWagerTransaction: true);
    loadPredictionGameSync();
  }

  /// Fully deletes a wager from the database, also deleting
  /// associated transactions.
  Future<void> removeWager(DbWager wager) async {
    await db.deleteWager(wager);
    await loadPredictionGame();
  }

  /// Fully deletes a wager from the database, also deleting
  /// associated transactions.
  void removeWagerSync(DbWager wager) {
    db.deleteWagerSync(wager);
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  /// Get the wagers from the prediction game with various filters.
  Future<List<DbWager>> getWagers({
    bool openOnly = false,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) async {
    return db.getWagers(game: predictionGame, openOnly: openOnly, matchPrep: matchPrep, player: player);
  }

  /// Get the wagers from the prediction game with various filters.
  List<DbWager> getWagersSync({
    bool openOnly = false,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) {
    return db.getWagersSync(game: predictionGame, openOnly: openOnly, matchPrep: matchPrep, player: player);
  }

  /// Process the wagers for a particular match prep.
  Future<void> processWagersForMatch(MatchPrep matchPrep) async {
    var wagers = await getWagers(matchPrep: matchPrep);
    for(var wager in wagers) {

    }
  }

  /// Process the wagers for a particular match prep.
  void processWagersForMatchSync(MatchPrep matchPrep) {
    var wagers = predictionGame.wagers.where((wager) => wager.matchPrep.value!.id == matchPrep.id).toList();
    for(var wager in wagers) {
      db.deleteWagerSync(wager);
    }
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  /// Get the transactions from the prediction game with various filters.
  Future<List<PredictionGameTransaction>> getTransactions({
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) async {
    return db.getTransactions(game: predictionGame, matchPrep: matchPrep, player: player);
  }

  /// Get the transactions from the prediction game with various filters.
  List<PredictionGameTransaction> getTransactionsSync({
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) {
    return db.getTransactionsSync(game: predictionGame, matchPrep: matchPrep, player: player);
  }

  /// Resolve a wager with the given status, creating a payout or refund transaction
  /// as necessary and updating the wager player's balance.
  Future<void> resolveWager(DbWager wager, DbWagerStatus status) async {
    wager.status = status;

    double playerBalanceChange = 0;

    if(status == DbWagerStatus.won) {
      if(wager.payoutTransaction.value == null) {
        playerBalanceChange = wager.payout();
        var payoutTransaction = PredictionGameTransaction(
          type: PredictionGameTransactionType.payout,
          amount: playerBalanceChange,
          created: DateTime.now(),
        );
        payoutTransaction.game.value = wager.game.value;
        payoutTransaction.user.value = wager.user.value;
        payoutTransaction.wager.value = wager;

        var savedTxn = await db.savePredictionGameTransaction(payoutTransaction);
        wager.payoutTransaction.value = savedTxn;
      }
      else {
        _log.w("Wager ${wager.id} was already resolved as won, but is being resolved again");
      }
    }
    else if(status == DbWagerStatus.voided) {
      if(wager.refundTransaction.value == null) {
        playerBalanceChange = wager.amount;

        // If we're voiding a wager that was already paid out for some reason,
        // we need to refund the player the amount they were paid.
        if(wager.payoutTransaction.value != null) {
          playerBalanceChange -= wager.payoutTransaction.value!.amount;
        }
        var refundTransaction = PredictionGameTransaction(
          type: PredictionGameTransactionType.refund,
          amount: playerBalanceChange,
          created: DateTime.now(),
        );
        refundTransaction.game.value = wager.game.value;
        refundTransaction.user.value = wager.user.value;
        refundTransaction.wager.value = wager;

        var savedTxn = await db.savePredictionGameTransaction(refundTransaction);
        wager.refundTransaction.value = savedTxn;
      }
      else {
        _log.w("Wager ${wager.id} was already resolved as voided, but is being resolved again");
      }
    }

    if(playerBalanceChange != 0) {
      await db.updatePlayerBalance(wager.user.value!, playerBalanceChange);
    }
    await db.saveWager(wager, saveLinks: true, createWagerTransaction: false);
    await loadPredictionGame();
  }

  /// Resolve a wager with the given status, creating a payout or refund transaction
  /// as necessary and updating the wager player's balance.
  void resolveWagerSync(DbWager wager, DbWagerStatus status) {
    wager.status = status;
    double playerBalanceChange = 0;
    if(status == DbWagerStatus.won) {
      playerBalanceChange = wager.payout();
      var payoutTransaction = PredictionGameTransaction(
        type: PredictionGameTransactionType.payout,
        amount: playerBalanceChange,
        created: DateTime.now(),
      );
      payoutTransaction.game.value = wager.game.value;
      payoutTransaction.user.value = wager.user.value;
      payoutTransaction.wager.value = wager;
      wager.payoutTransaction.value = payoutTransaction;
    }
    else if(status == DbWagerStatus.voided) {
      playerBalanceChange = wager.amount;
      var refundTransaction = PredictionGameTransaction(
        type: PredictionGameTransactionType.refund,
        amount: playerBalanceChange,
        created: DateTime.now(),
      );
      refundTransaction.game.value = wager.game.value;
      refundTransaction.user.value = wager.user.value;
      refundTransaction.wager.value = wager;
      wager.refundTransaction.value = refundTransaction;
    }

    if(playerBalanceChange != 0) {
      db.updatePlayerBalanceSync(wager.user.value!, playerBalanceChange);
    }
    db.saveWagerSync(wager, createWagerTransaction: false);
    loadPredictionGameSync();
  }

  /// Audit the transactions for a player and update the balance if needed.
  Future<void> auditUserBalance(PredictionGamePlayer player) async {
    double priorBalance = player.balance;
    bool isConsistent = db.auditPlayerTransactionsSync(player);
    if(!isConsistent) {
      await db.savePredictionGamePlayer(player, saveLinks: false);
      _log.w("Audit of player ${player.id} failed: balance changed from ${priorBalance.toStringAsFixed(2)} to ${player.balance.toStringAsFixed(2)}");
    }

    await loadPredictionGame();
  }

  /// Audit the transactions for a player and update the balance if needed.
  void auditUserBalanceSync(PredictionGamePlayer player) {
    double priorBalance = player.balance;
    bool isConsistent = db.auditPlayerTransactionsSync(player);
    if(!isConsistent) {
      db.savePredictionGamePlayerSync(player);
      _log.w("Audit of player ${player.id} failed: balance changed from ${priorBalance.toStringAsFixed(2)} to ${player.balance.toStringAsFixed(2)}");
    }
    loadPredictionGameSync();
  }

  // ======================
  // Internal utilities
  // ======================

  Future<void> loadPredictionGame() async {
    var game = await db.getPredictionGame(predictionGame.id);
    if(game != null) {
      predictionGame = game;
    }
    else {
      _log.w("Prediction game not found: ${predictionGame.id}");
    }
  }

  void loadPredictionGameSync({bool notify = false}) {
    var game = db.getPredictionGameSync(predictionGame.id);
    if(game != null) {
      predictionGame = game;
    }
    else {
      _log.w("Prediction game not found: ${predictionGame.id}");
    }
  }
}
