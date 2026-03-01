/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:isolate';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/cache/match/match_cache.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_cache.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_cache.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_key.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/prediction_game/audit_result.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/calculator.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/config.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/wager_data.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("PredictionGameManager");

class PredictionGameManager {
  PredictionGameManager({required this.predictionGame});

  final db = AnalystDatabase();
  PredictionGame predictionGame;

  // ======================
  // Match prep management
  // ======================

  /// Add a match prep to the prediction game.
  Future<void> addMatchPrep(MatchPrep matchPrep) async {
    predictionGame.matchPreps.add(matchPrep);
    await db.savePredictionGame(predictionGame, saveLinks: true);
    await loadPredictionGame();
  }

  void addMatchPrepSync(MatchPrep matchPrep) {
    predictionGame.matchPreps.add(matchPrep);
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  Future<void> removeMatchPrep(MatchPrep matchPrep) async {
    var wagers = await getWagers(matchPrep: matchPrep);
    for(var wager in wagers) {
      await removeWager(wager);
    }
    predictionGame.matchPreps.remove(matchPrep);
    await db.savePredictionGame(predictionGame, saveLinks: true);
    await loadPredictionGame();
  }

  void removeMatchPrepSync(MatchPrep matchPrep) {
    predictionGame.matchPreps.remove(matchPrep);
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  Future<void> enableMatchPrep(MatchPrep matchPrep) async {
    var matchPreps = predictionGame.disabledMatchPreps.toList();
    matchPreps.remove(matchPrep.id);
    predictionGame.disabledMatchPreps = matchPreps;
    await db.savePredictionGame(predictionGame);
    await loadPredictionGame();
  }

  void enableMatchPrepSync(MatchPrep matchPrep) {
    var matchPreps = predictionGame.disabledMatchPreps.toList();
    matchPreps.remove(matchPrep.id);
    predictionGame.disabledMatchPreps = matchPreps;
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  Future<void> disableMatchPrep(MatchPrep matchPrep) async {
    var matchPreps = predictionGame.disabledMatchPreps.toList();
    matchPreps.add(matchPrep.id);
    predictionGame.disabledMatchPreps = matchPreps;
    await db.savePredictionGame(predictionGame);
    await loadPredictionGame();
  }

  void disableMatchPrepSync(MatchPrep matchPrep) {
    var matchPreps = predictionGame.disabledMatchPreps.toList();
    matchPreps.add(matchPrep.id);
    predictionGame.disabledMatchPreps = matchPreps;
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  Future<List<MatchPrep>> getMatchPreps({bool futureOnly = true, bool hasPredictionsOnly = true, bool enabledOnly = false, bool reloadGameIfNeeded = true}) async {
    List<int> disabledMatchPreps = [];
    if(enabledOnly) {
      disabledMatchPreps = predictionGame.disabledMatchPreps.toList();
      if(reloadGameIfNeeded) {
        var queryResult = await db.getDisabledMatchPreps(predictionGame);
        if(queryResult != null) {
          disabledMatchPreps = queryResult;
        }
      }
    }

    var dbPreps = await db.getMatchPreps(predictionGame, futureOnly: futureOnly, hasPredictionsOnly: hasPredictionsOnly);
    if(enabledOnly) {
      return dbPreps.where((prep) => !disabledMatchPreps.contains(prep.id)).toList();
    }
    return dbPreps;
  }

  List<MatchPrep> getMatchPrepsSync({bool futureOnly = true, bool hasPredictionsOnly = true, bool enabledOnly = false, bool reloadGameIfNeeded = true}) {
    List<int> disabledMatchPreps = [];
    if(enabledOnly) {
      disabledMatchPreps = predictionGame.disabledMatchPreps.toList();
      if(reloadGameIfNeeded) {
        disabledMatchPreps = db.getDisabledMatchPrepsSync(predictionGame) ?? [];
      }
    }
    var dbPreps = db.getMatchPrepsSync(predictionGame, futureOnly: futureOnly, hasPredictionsOnly: hasPredictionsOnly);
    if(enabledOnly) {
      return dbPreps.where((prep) => !disabledMatchPreps.contains(prep.id)).toList();
    }
    return dbPreps;
  }

  Map<PredictionSet, List<RatingGroup>> availableRatingGroups(MatchPrep prep) {
    return predictionGame.availableRatingGroups(prep);
  }

  /// Gets the given match prep by its ID.
  ///
  /// This method does not verify that the match prep is part of the prediction game.
  Future<MatchPrep?> getMatchPrepById(int id) async {
    return db.getMatchPrepById(id);
  }

  /// Gets the given match prep by its ID.
  ///
  /// This method does not verify that the match prep is part of the prediction game.
  MatchPrep? getMatchPrepByIdSync(int id) {
    return db.getMatchPrepByIdSync(id);
  }

  Future<DbAlgorithmPrediction?> getAlgorithmPredictionForRating(ShooterRating rating, MatchPrep matchPrep, {PredictionSet? predictionSet}) async {
    return db.getAlgorithmPredictionForRating(rating, matchPrep, predictionSet: predictionSet);
  }

  DbAlgorithmPrediction? getAlgorithmPredictionForRatingSync(ShooterRating rating, MatchPrep matchPrep, {PredictionSet? predictionSet}) {
    return db.getAlgorithmPredictionForRatingSync(rating, matchPrep, predictionSet: predictionSet);
  }

  // ======================
  // Leaderboard
  // ======================

  /// Get the leaderboard for the prediction game.
  Future<List<PredictionLeaderboardEntry>> getLeaderboard(
    LeaderboardSortMode sortMode, {
    bool preload = false,
    List<DbWager>? preloadedWagers,
    List<PredictionGameTransaction>? preloadedTransactions,
  }) async {
    if(preload) {
      if(preloadedWagers == null) {
        preloadedWagers = await getWagers();
      }
      if(preloadedTransactions == null) {
        preloadedTransactions = await getTransactions();
      }
    }
    return db.getLeaderboard(predictionGame, sortMode, preloadedWagers: preloadedWagers, preloadedTransactions: preloadedTransactions);
  }

  // ======================
  // Player management
  // ======================

  Future<PredictionGamePlayer> savePlayer(PredictionGamePlayer player, {List<PredictionGameTransaction>? newTransactions}) async {
    await db.savePredictionGamePlayer(player, newTransactions: newTransactions, saveLinks: true);
    await loadPredictionGame();
    return player;
  }

  PredictionGamePlayer savePlayerSync(PredictionGamePlayer player) {
    db.savePredictionGamePlayerSync(player);
    loadPredictionGameSync();
    return player;
  }

  Future<void> deletePlayer(PredictionGamePlayer player) async {
    await db.deletePredictionGamePlayer(player);
    await loadPredictionGame();
  }

  void deletePlayerSync(PredictionGamePlayer player) {
    db.deletePredictionGamePlayerSync(player);
    loadPredictionGameSync();
  }

  // ======================
  // Wager management
  // ======================

  /// Add a wager to the prediction game.
  ///
  /// If [player] is provided, the wager will be added to that player.
  /// If [limits] is provided, the wager will be checked against the limits. Player must be provided if limits are provided.
  Future<AddWagerResult> addWager(DbWager wager, {PredictionGamePlayer? player, PredictionGamePlayerLimits? limits}) async {
    double? maximumWager;
    if(player != null) {
      if(player.balance < wager.amount) {
        return Result.err(AddWagerError.insufficientFunds);
      }
      maximumWager = player.balance;
    }
    if(limits != null) {
      if(limits.maxWager != null) {
        if(limits.maxWager! < wager.amount) {
          return Result.err(AddWagerError.exceededMaxWager);
        }
        maximumWager = min(maximumWager ?? double.infinity, limits.maxWager!);
      }

      var openWagers = player!.wagers.filter().statusEqualTo(DbWagerStatus.pending).countSync();
      if(limits.maxConcurrentWagers != null && limits.maxConcurrentWagers! < openWagers + 1) {
        return Result.err(AddWagerError.exceededMaxWagerCount);
      }
    }

    wager.maximumWager = maximumWager;

    // It's already backlinked to everything else, so we can just save it
    // and its links.
    try {
      await db.saveWager(wager, saveLinks: true, createWagerTransaction: true);
    }
    catch(e) {
      _log.e("Error adding wager: $e");
      return Result.err(AddWagerError.unknown);
    }
    await loadPredictionGame();
    return Result.ok(null);
  }

  /// Add a wager to the prediction game.
  ///
  /// If [player] is provided, the wager will be added to that player.
  /// If [limits] is provided, the wager will be checked against the limits. Player must be provided if limits are provided.
  AddWagerResult addWagerSync(DbWager wager, {PredictionGamePlayer? player, PredictionGamePlayerLimits? limits}) {
    double? maximumWager;
    if(player != null) {
      if(player.balance < wager.amount) {
        return Result.err(AddWagerError.insufficientFunds);
      }
      maximumWager = player.balance;
    }
    if(limits != null) {
      if(limits.maxWager != null) {
        if(limits.maxWager! < wager.amount) {
          return Result.err(AddWagerError.exceededMaxWager);
        }
        maximumWager = min(maximumWager ?? double.infinity, limits.maxWager!);
      }

      var openWagers = player!.wagers.filter().statusEqualTo(DbWagerStatus.pending).countSync();
      if(limits.maxConcurrentWagers != null && limits.maxConcurrentWagers! < openWagers + 1) {
        return Result.err(AddWagerError.exceededMaxWagerCount);
      }
    }

    wager.maximumWager = maximumWager;

    db.saveWagerSync(wager, createWagerTransaction: true);
    loadPredictionGameSync();
    return Result.ok(null);
  }

  /// Updates the odds of a [Wager] (i.e., the hydrated single-leg version which can either
  /// stand alone or serve as the legs of a [Parlay]) with the Bayesian odds shift math.
  ///
  /// [wager] is the [Wager] to update the odds of.
  ///
  /// [matchPrep] is the [MatchPrep] for which to find related wagers.
  ///
  /// [predictionSet] is the [PredictionSet] that was used to generate the [subjectMonteCarlo].
  ///
  /// [subjectMonteCarlo] is the Monte Carlo simulation results for the subject of the wager.
  ///
  /// If [wager.prediction] is a [PercentageSpreadPrediction], [spreadFavoriteMonteCarlo] and [spreadUnderdogMonteCarlo]
  /// are the Monte Carlo simulation results for the favorite and underdog of the spread prediction.
  /// Note that one of these will be [subjectMonteCarlo] (depending on whether the subject of the wager
  /// was the favorite or the underdog). They can be omitted for other prediction types.
  ///
  /// [cache] is an alternate cache to use for Monte Carlo simulation results. If not present, the
  /// default [MonteCarloCache] will be used. If neither is present, this method will run simulations
  /// on demand when decomposing spread wagers into percentage signals (as Monte Carlo samples are
  /// required for that process).
  Future<double> updateWagerWithBayesianOddsShift({
    required Wager wager,
    required MatchPrep matchPrep,
    required PredictionSet predictionSet,
    required Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
    required MonteCarloSimulationResult subjectMonteCarlo,
    MonteCarloSimulationResult? spreadFavoriteMonteCarlo,
    MonteCarloSimulationResult? spreadUnderdogMonteCarlo,
    MonteCarloSimulationCache? cache,
  }) async {
    final start = DateTime.now();
    final project = await matchPrep.ratingProject.value!;
    final algorithm = project.settings.algorithm;

    final matchId = matchPrep.futureMatch.value!.matchId;

    final prediction = wager.prediction;

    final subjectRating = prediction.shooter;

    int lengthInStages;
    if(algorithm is MultiplayerPercentEloRater) {
      lengthInStages = subjectRating.length;
    }
    else if(algorithm is Glicko2Rater) {
      lengthInStages = Glicko2Rating.getLengthInStages(subjectRating.wrappedRating);
    }
    else {
      throw ArgumentError("Unsupported algorithm: ${algorithm}");
    }

    DbPredictionType targetType = switch(prediction) {
      PlacePrediction() => DbPredictionType.place,
      PercentagePrediction() => DbPredictionType.percentage,
      PercentageSpreadPrediction() => DbPredictionType.spread,
      _ => throw ArgumentError("Unsupported prediction type: ${prediction.runtimeType}"),
    };

    final wagersForMatch = await getWagers(matchPrep: matchPrep);
    final wagersForSubject = wagersForMatch.where((w) =>
      w.legs.any((l) => l.type.isCompatibleWith(targetType)) &&
      w.subjectMemberNumbers.intersects(subjectRating.knownMemberNumbers)
    ).toList();

    List<BayesianOddsWager> priorSubjectWagers = [];
    List<BayesianOddsWager> priorUnderdogWagers = [];

    priorSubjectWagers = await _getPriorWagersForSubject(
      matchId: matchId,
      predictionSetId: predictionSet.id,
      project: project,
      wagers: wagersForSubject,
      targetType: targetType,
      subjectRating: subjectRating,
      subjectMonteCarlo: subjectMonteCarlo,
      cache: cache,
      shootersToPredictions: shootersToPredictions,
    );

    _log.v("${priorSubjectWagers.length} prior wagers for subject ${subjectRating.name}");
    for(var w in priorSubjectWagers) {
      _log.v("Prior: ${w.toString()}");
    }

    BayesianOddsConfig config = BayesianOddsConfig(
      baseWeight: 20,
      defaultConviction: 0.75,
    );

    double subjectDelta;
    double? underdogDelta;
    var result = await _nonclosureBayesianOddsShift(
      config: config,
      subjectHistoryLength: lengthInStages,
      wagers: priorSubjectWagers,
      subjectMonteCarlo: subjectMonteCarlo,
    );

    if(!result.success) {
      _log.e("Bayesian odds shift calculation failed: ${result.errorMessage}");
      return 0.0;
    }

    _log.v("Bayesian odds shift calculation result:");
    _log.v(result.log);

    subjectDelta = result.delta;

    if(prediction is PercentageSpreadPrediction) {
      final wagersForUnderdog = wagersForMatch.where((w) =>
        w.legs.any((l) => l.type.isCompatibleWith(DbPredictionType.spread)) &&
        w.subjectMemberNumbers.intersects(prediction.underdog.knownMemberNumbers)
      ).toList();
      priorUnderdogWagers = await _getPriorWagersForSubject(
        matchId: matchId,
        predictionSetId: predictionSet.id,
        project: project,
        wagers: wagersForUnderdog,
        targetType: DbPredictionType.spread,
        subjectRating: prediction.underdog,
        subjectMonteCarlo: spreadUnderdogMonteCarlo!,
        cache: cache,
        shootersToPredictions: shootersToPredictions,
      );
      _log.v("${priorUnderdogWagers.length} prior wagers for underdog ${prediction.underdog.name}");
      for(var w in priorUnderdogWagers) {
        _log.v("Prior: ${w.toString()}");
      }
      final result = await _nonclosureBayesianOddsShift(
        config: config,
        subjectHistoryLength: lengthInStages,
        wagers: priorUnderdogWagers,
        subjectMonteCarlo: spreadUnderdogMonteCarlo,
      );
      if(!result.success) {
        _log.e("Bayesian odds shift calculation failed: ${result.errorMessage}");
        return 0.0;
      }

      underdogDelta = result.delta;

      _log.v("Bayesian odds shift calculation result:");
      _log.v(result.log);
    }

    if(prediction is PlacePrediction) {
      _log.i("Bayesian odds shift from model for place prediction is ${subjectDelta.toStringAsFixed(2)}");
      final oldMoneyline = wager.probability.moneylineOdds;
      wager.recalculateProbabilityWithDelta(
        targetSimulation: subjectMonteCarlo,
        underdogSimulation: null,
        targetDelta: subjectDelta,
        underdogDelta: null,
        random: Random(matchPrep.futureMatch.value!.matchId.stableHash),
      );
      _log.i("${wager.prediction.descriptiveString} - $oldMoneyline -> ${wager.probability.moneylineOdds}");

    }
    else if(prediction is PercentagePrediction) {
      _log.i("Bayesian odds shift from model for percentage prediction is ${subjectDelta.asPercentage(decimals: 2, includePercent: true)}");
      final oldMoneyline = wager.probability.moneylineOdds;
      wager.recalculateProbabilityWithDelta(
        targetSimulation: subjectMonteCarlo,
        underdogSimulation: null,
        targetDelta: subjectDelta,
        underdogDelta: null,
        random: Random(matchPrep.futureMatch.value!.matchId.stableHash),
      );

      _log.i("${wager.prediction.descriptiveString} - $oldMoneyline -> ${wager.probability.moneylineOdds}");
    }
    else if(prediction is PercentageSpreadPrediction) {
      _log.i("Bayesian odds shift from model for percentage spread prediction is favorite: "
        "${subjectDelta.asPercentage(decimals: 2, includePercent: true)}, "
        "underdog: ${underdogDelta?.asPercentage(decimals: 2, includePercent: true)}");
      final oldMoneyline = wager.probability.moneylineOdds;
      wager.recalculateProbabilityWithDelta(
        targetSimulation: subjectMonteCarlo,
        underdogSimulation: spreadUnderdogMonteCarlo,
        targetDelta: subjectDelta,
        underdogDelta: underdogDelta,
        random: Random(matchPrep.futureMatch.value!.matchId.stableHash),
      );

      _log.i("${wager.prediction.descriptiveString} - $oldMoneyline -> ${wager.probability.moneylineOdds}");
    }
    else {
      _log.e("Unsupported prediction type: ${prediction.runtimeType}");
    }

    final end = DateTime.now();
    _log.i("Bayesian odds shift calculation took ${end.difference(start).inMilliseconds}ms");
    return subjectDelta;
  }

  /// Convert prior wagers for a given subject into Bayesian odds wagers,
  /// looking up data for any spread legs if needed.
  Future<List<BayesianOddsWager>> _getPriorWagersForSubject({
    required String matchId,
    required int predictionSetId,
    required DbRatingProject project,
    required List<DbWager> wagers,
    required DbPredictionType targetType,
    required ShooterRating subjectRating,
    required MonteCarloSimulationResult subjectMonteCarlo,
    IMonteCarloCache? cache,
    Map<ShooterRating, AlgorithmPrediction>? shootersToPredictions,
  }) async {
    List<BayesianOddsWager> priorWagers = [];
    final subject = DbPredictionTarget.fromShooterRating(subjectRating);
    for(var wager in wagers) {
      Map<DbPrediction, MonteCarloSimulationResult> spreadFavoriteMonteCarloResults = {};
      Map<DbPrediction, MonteCarloSimulationResult> spreadUnderdogMonteCarloResults = {};

      for(var leg in wager.legs) {
        if(!leg.type.isCompatibleWith(targetType)) {
          continue;
        }

        if(leg.type == DbPredictionType.spread) {
          bool needsFavorite;
          if(subject.isSameAs(leg.target)) {
            spreadFavoriteMonteCarloResults[leg] = subjectMonteCarlo;
            needsFavorite = false;
          }
          else if(subject.isSameAs(leg.underdog!)) {
            spreadUnderdogMonteCarloResults[leg] = subjectMonteCarlo;
            needsFavorite = true;
          }
          else {
            _log.w("Subject ${subject.name} is not a target or underdog of spread leg ${leg.descriptiveString}");
            continue;
          }

          final neededSubject = needsFavorite? leg.target : leg.underdog!;

          final neededSubjectKey = MonteCarloSimulationLruKey(
            predictionSetId: predictionSetId,
            memberNumber: neededSubject.memberNumber,
            trials: 12500,
          );
          MonteCarloSimulationResult? neededSubjectMonteCarlo;
          if(cache != null) {
            neededSubjectMonteCarlo = await cache.lookup(neededSubjectKey);
          }

          if(neededSubjectMonteCarlo == null) {
            _log.v("Cache miss for spread leg ${leg.descriptiveString} target ${neededSubject.name}");
            final neededSubjectRating = await neededSubject.getShooterRating(db);
            if(neededSubjectRating == null) {
              _log.w("Subject ${neededSubject.name} not found in database");
              continue;
            }
            var result = runOddsSimulation(
              shootersToPredictions: shootersToPredictions!,
              target: project.wrapDbRatingSync(neededSubjectRating),
              trials: 12500,
              random: Random(matchId.stableHash),
            );
            if(cache != null) {
              cache.cache(neededSubjectKey, result);
            }
            neededSubjectMonteCarlo = result;
          }

          if(needsFavorite) {
            spreadFavoriteMonteCarloResults[leg] = neededSubjectMonteCarlo;
          }
          else {
            spreadUnderdogMonteCarloResults[leg] = neededSubjectMonteCarlo;
          }
        }
      }

      final newPriors = await BayesianOddsWager.fromDbWager(
        subject: subject,
        gm: this,
        dbWager: wager,
        targetType: targetType,
        spreadFavoriteMonteCarloResults: spreadFavoriteMonteCarloResults,
        spreadUnderdogMonteCarloResults: spreadUnderdogMonteCarloResults,
        log: _log,
      );
      priorWagers.addAll(newPriors);
    }

    return priorWagers;
  }

  static Future<BayesianOddsResult> _nonclosureBayesianOddsShift({
    required BayesianOddsConfig config,
    required int subjectHistoryLength,
    required List<BayesianOddsWager> wagers,
    required MonteCarloSimulationResult subjectMonteCarlo,
  }) async {
    return Isolate.run(() => calculateBayesianOddsUpdate(
      config: config,
      subjectHistoryLength: subjectHistoryLength,
      wagers: wagers,
      subjectMonteCarlo: subjectMonteCarlo,
    ));
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

  // /// Process the wagers for a particular match prep.
  // Future<void> processWagersForMatch(MatchPrep matchPrep) async {
  //   var wagers = await getWagers(matchPrep: matchPrep);
  //   for(var wager in wagers) {
  //   }
  //   await db.savePredictionGame(predictionGame, saveLinks: true);
  //   await loadPredictionGame();
  // }

  // /// Process the wagers for a particular match prep.
  // void processWagersForMatchSync(MatchPrep matchPrep) {
  //   var wagers = predictionGame.wagers.where((wager) => wager.matchPrep.value!.id == matchPrep.id).toList();
  //   for(var wager in wagers) {
  //   }
  //   db.savePredictionGameSync(predictionGame);
  //   loadPredictionGameSync();
  // }

  /// Resolve a wager with the given status, creating a payout or refund transaction
  /// as necessary and updating the wager player's balance.
  Future<Result<DbWager, WagerResolutionError>> resolveWager(DbWager wager, DbWagerStatus status) async {
    if(wager.status.isResolved) {
      return Result.err(WagerResolutionError.alreadyResolved);
    }

    if(!wager.hasResolutionInformation) {
      return Result.err(WagerResolutionError.noResolutionInformation);
    }

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
    return Result.ok(wager);
  }

  /// Resolve a wager with the given status, creating a payout or refund transaction
  /// as necessary and updating the wager player's balance.
  Result<DbWager, WagerResolutionError> resolveWagerSync(DbWager wager, DbWagerStatus status) {
    if(wager.status.isResolved) {
      return Result.err(WagerResolutionError.alreadyResolved);
    }

    if(!wager.hasResolutionInformation) {
      return Result.err(WagerResolutionError.noResolutionInformation);
    }

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
    return Result.ok(wager);
  }

  // ======================
  // Transaction management
  // ======================

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

  /// Get relevant scores for a list of given wagers: scores for all of
  /// the shooters in the wager's legs, for both the match result and the result within the
  /// relevant prediction set.
  ///
  /// Any matches provided in [matches] will be used to calculate scores. Other matches will be
  /// loaded from the database as needed.
  Future<Map<DbWager, WagerScores>> getAllRelevantScores(List<DbWager> wagers, {Map<DbWager, ShootingMatch>? matches}) async {
    /// First load all matches we need, if not provided.
    if(matches == null) {
      matches = {};
    }
    for(var wager in wagers) {
      var match = matches[wager];
      if(match == null) {
        var dbMatch = wager.matchPrep.value?.futureMatch.value?.dbMatch.value;
        if(dbMatch != null) {
          var matchRes = await MatchCache.instance.get(dbMatch);
          if(matchRes.isOk()) {
            match = matchRes.unwrap();
          }
        }
      }
    }

    // Get lists of data we're interested in: rating groups, prediction sets, and shooters.
    Map<ShootingMatch, Set<RatingGroup>> matchesToGroups = {};
    Map<ShootingMatch, Set<PredictionSet>> matchesToPredictionSets = {};
    Map<ShootingMatch, List<DbShooterRating>> matchesToWageredShooters = {};
    for(var wager in wagers) {
      var match = matches[wager];

      if(match != null) {
        for(var leg in wager.legs) {
          var shooter = leg.target.getShooterRatingSync(db);
          var underdog = leg.underdog?.getShooterRatingSync(db);
          var shooters = [shooter, underdog].nonNulls.toList();
          for(var s in shooters) {
            matchesToWageredShooters.addToListIfMissingByEquality(match, s, (a, b) => a.equalsShooter(b));
          }
        }
        // Rating groups and prediction sets both implement DB equality
        matchesToGroups.addToSet(match, wager.ratingGroup.value!);
        matchesToPredictionSets.addToSet(match, wager.predictionSet.value!);
      }
    }

    Set<PredictionSet> predictionSetsToProcess = matchesToPredictionSets.values.flattenedToSet;
    Map<PredictionSet, List<Shooter>> predictionSetShooters = {};
    for(var predictionSet in predictionSetsToProcess) {
      predictionSetShooters[predictionSet] = predictionSet.algorithmPredictions.map((p) => p.asShooter(loadFromRating: false)).nonNulls.toList();
    }

    // Get the scores of interest.
    Set<ShootingMatch> matchesToProcess = matchesToGroups.keys.toSet();
    Map<ShootingMatch, Map<RatingGroup, Map<String, RelativeMatchScore>>> groupScores = {};
    Map<ShootingMatch, Map<RatingGroup, Map<PredictionSet, Map<String, RelativeMatchScore>>>> setScores = {};
    for(var match in matchesToProcess) {
      // For each match, we need to calculate scores for each rating group of interest, both
      // overall, and within each prediction set of interest.
      groupScores[match] = {};
      setScores[match] = {};
      for(var group in matchesToGroups[match]!) {
        var overallShooters = match.filterShooters(divisions: group.divisions);
        var overallScores = match.getScores(shooters: overallShooters);
        var filteredOverall = Map.fromEntries(
          overallScores.entries
            .where((element) => matchesToWageredShooters[match]!
              .any((s) => element.key.equalsShooter(s))
            )
          );

        Map<String, RelativeMatchScore> overallByNumber = {};
        for(var entry in filteredOverall.entries) {
          for(var number in entry.key.knownMemberNumbers) {
            overallByNumber[number] = entry.value;
          }
        }
        groupScores[match]![group] = overallByNumber;

        setScores[match]![group] = {};
        for(var predictionSet in matchesToPredictionSets[match]!) {
          var shooters = predictionSetShooters[predictionSet]!;
          var entries = match.getEntriesFor(shooters);
          var predictionSetScores = match.getScores(shooters: entries);
          var relevantScores = Map.fromEntries(
            predictionSetScores.entries
              .where((element) => matchesToWageredShooters[match]!
                .any((s) => element.key.equalsShooter(s))
              )
            );

          Map<String, RelativeMatchScore> predictionSetByNumber = {};
          for(var entry in relevantScores.entries) {
            for(var number in entry.key.knownMemberNumbers) {
              predictionSetByNumber[number] = entry.value;
            }
          }
          setScores[match]![group]![predictionSet] = predictionSetByNumber;
        }
      }
    }

    Map<DbWager, WagerScores> relevantScores = {};
    for(var wager in wagers) {
      var match = matches[wager];
      if(match != null) {
        var group = wager.ratingGroup.value!;
        var predictionSet = wager.predictionSet.value!;
        var scores = WagerScores(wager: wager);
        scores.scores = groupScores[match]![group]!;
        scores.predictionSetScores = setScores[match]![group]![predictionSet]!;
        relevantScores[wager] = scores;
      }
    }

    return relevantScores;
  }

  /// Get the relevant scores for a wager: scores for all of the shooters in the wager's legs,
  /// for both the match result and the result within the prediction set.
  ///
  /// If [match] is provided, it will be used to calculate the scores
  Future<WagerScores> getRelevantScores(DbWager wager, {ShootingMatch? match}) async {
    var scores = WagerScores(wager: wager);
    ShootingMatch? actualMatch;
    var dbMatch = wager.matchPrep.value?.futureMatch.value?.dbMatch.value;
    if(dbMatch == null) {
      return scores;
    }
    if(match == null) {
      var matchRes = await MatchCache.instance.get(dbMatch);
      if(matchRes.isOk()) {
        actualMatch = matchRes.unwrap();
      }
      else {
        _log.e("Error hydrating match: ${matchRes.unwrapErr().message}");
        return scores;
      }
    }
    else {
      actualMatch = match;
    }

    List<Shooter> shooters = [];
    for(var leg in wager.legs) {
      var shooter = leg.target.getShooterRatingSync(db);
      var underdog = leg.underdog?.getShooterRatingSync(db);
      if(shooter != null) {
        shooters.add(shooter);
      }
      if(underdog != null) {
        shooters.add(underdog);
      }
    }

    var group = wager.ratingGroup.value!;
    var predictionSet = wager.predictionSet.value;

    scores.scores = _getScoresForShooters(shooters, group, actualMatch, null);
    scores.predictionSetScores = _getScoresForShooters(shooters, group, actualMatch, predictionSet);

    return scores;

  }

  /// Audit the transactions for a player and update the balance if needed, returning
  /// the change in balance, or 0 if the balance was consistent.
  Future<PredictionGameAuditResult> auditUserBalance(PredictionGamePlayer player) async {
    double priorBalance = player.balance;
    bool auditPassed = db.auditPlayerTransactionsSync(player);
    double balanceChange = player.balance - priorBalance;
    if(!auditPassed) {
      await db.savePredictionGamePlayer(player, saveLinks: false);
      _log.w("Audit of player ${player.id} failed: balance changed from ${priorBalance.toStringAsFixed(2)} to ${player.balance.toStringAsFixed(2)}");
    }

    await loadPredictionGame();
    return PredictionGameAuditResult(balanceChange: balanceChange, linksChanged: !auditPassed && balanceChange == 0);
  }

  /// Audit the transactions for a player and update the balance if needed.
  PredictionGameAuditResult auditUserBalanceSync(PredictionGamePlayer player) {
    double priorBalance = player.balance;
    bool auditPassed = db.auditPlayerTransactionsSync(player);
    double balanceChange = player.balance - priorBalance;
    if(!auditPassed) {
      db.savePredictionGamePlayerSync(player);
      _log.w("Audit of player ${player.id} failed: balance changed from ${priorBalance.toStringAsFixed(2)} to ${player.balance.toStringAsFixed(2)}");
    }
    loadPredictionGameSync();
    return PredictionGameAuditResult(balanceChange: balanceChange, linksChanged: !auditPassed && balanceChange == 0);
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

  Map<String, RelativeMatchScore> _getScoresForShooters(List<Shooter> relevantShooters, RatingGroup group, ShootingMatch match, PredictionSet? predictionSet) {
    Map<String, RelativeMatchScore> scores = {};
    for(var shooter in relevantShooters) {
      RelativeMatchScore? score;
      if(predictionSet != null) {
        score = _getMatchScore(
          shooter: shooter,
          ratingGroup: group,
          match: match,
          predictionSet: predictionSet,
        );
      }
      else {
        score = _getMatchScore(
          shooter: shooter,
          ratingGroup: group,
          match: match,
        );
      }
      if(score != null) {
        scores[shooter.memberNumber] = score;
      }
    }
    return scores;
  }

  RelativeMatchScore? _getMatchScore({
    required Shooter shooter,
    required RatingGroup ratingGroup,
    required ShootingMatch match,
    PredictionSet? predictionSet,
  }) {
    // TODO: cache, maybe?
    // var memberNumber = shooter.memberNumber;
    // if(predictionSet != null) {
    //   var cachedScore = _predictionSetMemberNumberScoreCache[memberNumber];
    //   if(cachedScore != null) {
    //     return cachedScore;
    //   }
    // }
    // else {
    //   var cachedScore = _memberNumberScoreCache[memberNumber];
    //   if(cachedScore != null) {
    //     return cachedScore;
    //   }
    // }

    final divisions = ratingGroup.divisions;
    if(predictionSet != null) {
      List<Shooter> predictedShooters = predictionSet.algorithmPredictions.map((p) => p.asShooter(loadFromRating: false)).nonNulls.toList();
      var entries = match.getEntriesFor(predictedShooters, divisions: divisions);
      var scores = match.getScores(shooters: entries);
      var matchScores = scores;

      var score = matchScores.entries.firstWhereOrNull((element) => shooter.equalsShooter(element.key))?.value;
      if(score != null) {
        return score;
      }
      return null;
    }
    else {
      var entries = match.filterShooters(divisions: divisions);
      var scores = match.getScores(shooters: entries);
      var matchScores = scores;

      var score = matchScores.entries.firstWhereOrNull((element) => shooter.equalsShooter(element.key))?.value;
      if(score != null) {
        return score;
      }
      return null;
    }
  }
}

enum AddWagerError implements ResultErr {
  insufficientFunds,
  exceededMaxWager,
  exceededMaxWagerCount,
  matchAlreadyStarted,
  unknown;

  @override
  String get message => switch(this) {
    insufficientFunds => "Insufficient funds",
    exceededMaxWager => "Exceeded max wager",
    exceededMaxWagerCount => "Exceeded max wager count",
    matchAlreadyStarted => "Match already started",
    unknown => "Unknown error",
  };
}

typedef AddWagerResult = Result<void, AddWagerError>;

class WagerScores {
  DbWager wager;
  Map<String, RelativeMatchScore> scores = {};
  Map<String, RelativeMatchScore> predictionSetScores = {};

  WagerScores({required this.wager});
}

enum WagerResolutionError implements ResultErr {
  alreadyResolved,
  noResolutionInformation,
  unknown;

  @override
  String get message => switch(this) {
    alreadyResolved => "Wager already resolved",
    noResolutionInformation => "Wager has no resolution information",
    unknown => "Unknown error",
  };
}