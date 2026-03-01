import 'dart:isolate';
import 'dart:math';

import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_cache.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_key.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
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
  }) : _config = config ?? BayesianOddsConfig(
    baseWeight: 15,
    convictionFloor: 0.25,
    defaultConviction: 0.33,
  );

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
    required PredictionGameManager gm,
    required Wager wager,
    required MatchPrep matchPrep,
    required PredictionSet predictionSet,
    required Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
    required MonteCarloSimulationResult subjectMonteCarlo,
    MonteCarloSimulationResult? spreadFavoriteMonteCarlo,
    MonteCarloSimulationResult? spreadUnderdogMonteCarlo,
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
    final wagersForSubject = wagersForMatch.where((w) =>
      w.legs.any((l) => l.type.isCompatibleWith(targetType)) &&
      w.subjectMemberNumbers.intersects(subjectRating.knownMemberNumbers)
    ).toList();

    List<BayesianOddsWager> priorSubjectWagers = [];
    List<BayesianOddsWager> priorUnderdogWagers = [];

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

    double subjectDelta;
    double? underdogDelta;
    var result = await _nonclosureBayesianOddsShift(
      config: _config,
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
        gm: gm,
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
        config: _config,
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