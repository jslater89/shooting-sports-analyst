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