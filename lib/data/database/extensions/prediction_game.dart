import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';

extension PredictionGameExtension on AnalystDatabase {
  Future<List<PredictionGame>> getPredictionGames() async {
    return isar.predictionGames.where().anyId().sortByCreatedDesc().findAll();
  }

  List<PredictionGame> getPredictionGamesSync() {
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
}