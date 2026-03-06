import 'dart:isolate';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_cache.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_key.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/bayesian_delta.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/bayesian_delta.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/calculator.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/config.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/wager_data.dart';
import 'package:shooting_sports_analyst/data/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("BayesianWagerUpdater");

class BayesianWagerUpdater {
  final db = AnalystDatabase();

  BayesianOddsConfig _config;

  BayesianWagerUpdater({
    BayesianOddsConfig? config,
  }) : _config = config ?? BayesianOddsConfig();

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
  ///
  /// [bestPossibleOdds] and [worstPossibleOdds] are the best and worst possible odds for the wager,
  /// respectively. If not present, the default values of 1.0001 and 10000.0 will be used.
  Future<double> updateWagerWithBayesianOddsShift({
    required PredictionGameManager gm,
    required Wager wager,
    required MatchPrep matchPrep,
    required PredictionSet predictionSet,
    required Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
    required MonteCarloSimulationResult subjectMonteCarlo,
    MonteCarloSimulationResult? spreadFavoriteMonteCarlo,
    MonteCarloSimulationResult? spreadUnderdogMonteCarlo,
    double? bestPossibleOdds,
    double? worstPossibleOdds,
    IMonteCarloCache? cache,
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

    final wagersForMatch = await gm.getWagers(matchPrep: matchPrep);

    double subjectDelta;
    double? underdogDelta;

    subjectDelta = await _calculateDeltaForSubject(
      gm: gm,
      matchId: matchId,
      predictionSet: predictionSet,
      project: project,
      wagersForMatch: wagersForMatch,
      targetType: targetType,
      subjectRating: subjectRating,
      subjectMonteCarlo: subjectMonteCarlo,
      cache: cache,
      shootersToPredictions: shootersToPredictions,
      subjectStageHistoryLength: lengthInStages,
    );

    if(prediction is PercentageSpreadPrediction) {
      final underdogRating = prediction.underdog;
      underdogDelta = await _calculateDeltaForSubject(
        gm: gm,
        matchId: matchId,
        predictionSet: predictionSet,
        project: project,
        wagersForMatch: wagersForMatch,
        targetType: targetType,
        subjectRating: underdogRating,
        subjectMonteCarlo: spreadUnderdogMonteCarlo!,
        cache: cache,
        shootersToPredictions: shootersToPredictions,
        subjectStageHistoryLength: lengthInStages,
      );
    }

    if(prediction is PlacePrediction) {
      _log.i("Bayesian odds shift from model for place prediction is ${subjectDelta.toStringAsFixed(2)}");
      final oldMoneyline = wager.probability.moneylineOdds;
      wager.recalculateProbabilityWithDelta(
        targetSimulation: subjectMonteCarlo,
        underdogSimulation: null,
        targetDelta: subjectDelta,
        underdogDelta: null,
        bestPossibleOdds: bestPossibleOdds,
        worstPossibleOdds: worstPossibleOdds,
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
        bestPossibleOdds: bestPossibleOdds,
        worstPossibleOdds: worstPossibleOdds,
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
        bestPossibleOdds: bestPossibleOdds,
        worstPossibleOdds: worstPossibleOdds,
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

  /// Get the Bayesian delta for a given subject rating, checking the database cache first.
  Future<double> _calculateDeltaForSubject({
    required PredictionGameManager gm,
    required String matchId,
    required PredictionSet predictionSet,
    required DbRatingProject project,
    required List<DbWager> wagersForMatch,
    required DbPredictionType targetType,
    required ShooterRating subjectRating,
    required MonteCarloSimulationResult subjectMonteCarlo,
    required IMonteCarloCache? cache,
    required Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
    required int subjectStageHistoryLength,
  }) async {
    final wagersForSubject = wagersForMatch.where((w) =>
      w.legs.any((l) => l.type.isCompatibleWith(targetType)) &&
      w.subjectMemberNumbers.intersects(subjectRating.knownMemberNumbers) &&
      w.status != DbWagerStatus.voided
    ).toList();

    if(wagersForSubject.isEmpty) {
      return 0.0;
    }

    var dates = wagersForSubject.map((w) => w.created).sorted((a, b) => b.compareTo(a));
    var latestBetTimestamp = dates.first;

    final cachedDelta = await db.getBayesianDelta(
      gameId: gm.predictionGame.id,
      memberNumber: subjectRating.memberNumber,
      predictionSetId: predictionSet.id,
      type: targetType,
      validAfter: latestBetTimestamp,
      configHash: _config.configHash,
    );

    if(cachedDelta != null) {
      return cachedDelta.delta;
    }

    List<BayesianOddsWager> priorSubjectWagers = [];

    priorSubjectWagers = await _getPriorWagersForSubject(
      gm: gm,
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

    var result = await _nonclosureBayesianOddsShift(
      config: _config,
      subjectHistoryLength: subjectStageHistoryLength,
      wagers: priorSubjectWagers,
      subjectMonteCarlo: subjectMonteCarlo,
    );

    if(!result.success) {
      _log.e("Bayesian odds shift calculation failed: ${result.errorMessage}");
      return 0.0;
    }

    _log.v("Bayesian odds shift calculation result:");
    _log.v(result.log);

    await db.saveBayesianDelta(BayesianDelta.create(
      game: gm.predictionGame,
      memberNumber: subjectRating.memberNumber,
      project: project,
      rating: subjectRating.wrappedRating,
      group: subjectRating.group,
      delta: result.delta,
      type: targetType,
      contributingWagers: wagersForSubject,
      lastBetTimestamp: latestBetTimestamp,
      computedAt: DateTime.now(),
      predictionSet: predictionSet,
      config: _config,
    ));

    return result.delta;
  }

  /// Convert prior wagers for a given subject into Bayesian odds wagers,
  /// looking up data for any spread legs if needed.
  Future<List<BayesianOddsWager>> _getPriorWagersForSubject({
    required PredictionGameManager gm,
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
        gm: gm,
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
}