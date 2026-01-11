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
  // Player management
  // ======================

  Future<void> addNewPlayer(PredictionGamePlayer player, {List<PredictionGameTransaction>? newTransactions}) async {
    await db.savePredictionGamePlayer(player, newTransactions: newTransactions, saveLinks: true);
    await loadPredictionGame();
  }

  void addNewPlayerSync(PredictionGamePlayer player) {
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
    await db.saveWager(wager, saveLinks: true);
    await loadPredictionGame();
  }

  void addWagerSync(DbWager wager) {
    db.saveWagerSync(wager);
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

  List<PredictionGameTransaction> getTransactionsSync({
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) {
    return db.getTransactionsSync(game: predictionGame, matchPrep: matchPrep, player: player);
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