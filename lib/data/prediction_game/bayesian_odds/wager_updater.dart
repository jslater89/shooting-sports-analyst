/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

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
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
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
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("BayesianWagerUpdater");

/// Whether to exclude wagers that are similar to the incoming wager.
///
/// Should always be true for release builds.
const _excludeWagers = true;

/// Whether to use the cache for Bayesian delta calculations.
///
/// Should always be true for release builds.
const _useCache = true;

class BayesianWagerUpdater {
  final db = AnalystDatabase();

  BayesianOddsConfig _config;

  BayesianWagerUpdater({
    BayesianOddsConfig? config,
  }) : _config = config ?? BayesianOddsConfig();

  /// Updates the odds of a [Wager] (i.e., the hydrated single-leg version which can either
  /// stand alone or serve as the legs of a [Parlay]) with the Bayesian odds shift math.
  ///
  /// [wager] is the [Wager] to update the odds of, and [bettor] is the [PredictionGamePlayer]
  /// requesting odds.
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
  ///
  /// [houseEdge] is a house edge to apply to the wager. If not present, the default value of 0.05 will be used.
  Future<double> updateWagerWithBayesianOddsShift({
    required PredictionGameManager gm,
    required PredictionGamePlayer bettor,
    required Wager wager,
    required MatchPrep matchPrep,
    required PredictionSet predictionSet,
    required Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
    required MonteCarloSimulationResult subjectMonteCarlo,
    MonteCarloSimulationResult? spreadFavoriteMonteCarlo,
    MonteCarloSimulationResult? spreadUnderdogMonteCarlo,
    double? bestPossibleOdds,
    double? worstPossibleOdds,
    double? houseEdge,
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
    else if(algorithm is LatentLogRater) {
      lengthInStages = LatentLogRating.getLengthInStages(subjectRating.wrappedRating);
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
    List<double> subjectBetWeights = [];
    List<double> underdogBetWeights = [];

    var subjectDeltaResult = await _calculateDeltaForSubject(
      gm: gm,
      bettor: bettor,
      config: _config,
      incomingWager: wager,
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
    subjectDelta = subjectDeltaResult.delta;
    subjectBetWeights = subjectDeltaResult.betWeights;

    if(prediction is PercentageSpreadPrediction) {
      final underdogRating = prediction.underdog;
      var underdogDeltaResult = await _calculateDeltaForSubject(
        gm: gm,
        bettor: bettor,
        config: _config,
        incomingWager: wager,
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
      underdogDelta = underdogDeltaResult.delta;
      underdogBetWeights = underdogDeltaResult.betWeights;
    }

    double totalBetWeight = 0.0;
    double subjectBetWeight = subjectBetWeights.sum;
    if(underdogBetWeights.isNotEmpty) {
      double underdogBetWeight = underdogBetWeights.sum;

      totalBetWeight = (subjectBetWeight + underdogBetWeight) / 2.0;
    }
    else {
      totalBetWeight = subjectBetWeight;
    }


    double actualWorstOdds = worstPossibleOdds ?? PredictionProbability.worstPossibleOddsDefault;
    double actualBestOdds = bestPossibleOdds ?? PredictionProbability.bestPossibleOddsDefault;
    double maxLogitShift = _config.maxLogitShift;
    if(_config.maxLogitShift > 0.0) {
      if(_config.clampEvidenceTau > 0.0) {
        final tau = _config.clampEvidenceTau;
        final maxMult = _config.clampMaxMultiplier;
        double multiplier = 1.0 + (maxMult - 1.0) * (1.0 - exp(-totalBetWeight / tau));
        _log.v("Base max logit shift: ${_config.maxLogitShift.toStringAsFixed(2)}");
        _log.v("Logit multiplier calculation: 1.0 + (${maxMult.toStringAsFixed(2)} - 1) × (1 - exp(-${totalBetWeight.toStringAsFixed(2)} / ${tau.toStringAsFixed(2)})) = ${multiplier.toStringAsFixed(4)}");

        maxLogitShift = multiplier * _config.maxLogitShift;
        _log.v("Effective max logit shift: ${multiplier.toStringAsFixed(4)} × ${_config.maxLogitShift.toStringAsFixed(2)} = ${maxLogitShift.toStringAsFixed(4)}");
      }

      final rawProbability = wager.probability.rawProbability;
      final logitProbability = log(rawProbability / (1 - rawProbability));
      final minProbability = 1 / (1 + exp(-(logitProbability - maxLogitShift)));
      final maxProbability = 1 / (1 + exp(-(logitProbability + maxLogitShift)));

      final worstProbability = PredictionProbability.fromRawProbability(
        maxProbability,
        bestPossibleOdds: bestPossibleOdds,
        worstPossibleOdds: worstPossibleOdds,
        houseEdge: houseEdge,
      );
      final bestProbability = PredictionProbability.fromRawProbability(
        minProbability,
        bestPossibleOdds: bestPossibleOdds,
        worstPossibleOdds: worstPossibleOdds,
        houseEdge: houseEdge,
      );

      actualWorstOdds = max(worstPossibleOdds ?? PredictionProbability.worstPossibleOddsDefault, worstProbability.decimalOdds);
      actualBestOdds = min(bestPossibleOdds ?? PredictionProbability.bestPossibleOddsDefault, bestProbability.decimalOdds);

      _log.v("Clamp of ${maxLogitShift.toStringAsFixed(2)} logits allows true odds between ${worstProbability.rawMoneylineOdds} and ${bestProbability.rawMoneylineOdds}");
      _log.v("House edge adjusted odds between ${worstProbability.moneylineOdds} and ${bestProbability.moneylineOdds}");
    }

    if(prediction is PlacePrediction) {
      _log.i("Bayesian odds shift from model for place prediction is ${subjectDelta.toStringAsFixed(2)}");
      final oldMoneyline = wager.probability.moneylineOdds;

      wager.recalculateProbabilityWithDelta(
        targetSimulation: subjectMonteCarlo,
        underdogSimulation: null,
        targetDelta: subjectDelta,
        underdogDelta: null,
        bestPossibleOdds: actualBestOdds,
        worstPossibleOdds: actualWorstOdds,
        houseEdge: houseEdge,
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
        bestPossibleOdds: actualBestOdds,
        worstPossibleOdds: actualWorstOdds,
        houseEdge: houseEdge,
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
        bestPossibleOdds: actualBestOdds,
        worstPossibleOdds: actualWorstOdds,
        houseEdge: houseEdge,
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
  Future<_DeltaResult> _calculateDeltaForSubject({
    required PredictionGameManager gm,
    required PredictionGamePlayer bettor,
    required BayesianOddsConfig config,
    required Wager incomingWager,
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
    final incomingScoringGroup = incomingWager.prediction.effectiveScoringGroup;
    var wagersForSubject = wagersForMatch.where((w) =>
      w.legs.any((l) => l.type.isCompatibleWith(targetType)) &&
      w.subjectMemberNumbers.intersects(subjectRating.knownMemberNumbers) &&
      w.status != DbWagerStatus.voided &&
      w.scoringGroup.value?.uuid == incomingScoringGroup.uuid
    ).toList();

    if(wagersForSubject.isEmpty) {
      return _DeltaResult(delta: 0.0, betWeights: []);
    }

    final dates = wagersForSubject.map((w) => w.created).sorted((a, b) => b.compareTo(a));
    final latestBetTimestamp = dates.first;

    double modelPlace = 0.0;
    if(targetType == DbPredictionType.place) {
      modelPlace = subjectMonteCarlo.places.average;
    }

    final cachedDelta = await db.getBayesianDelta(
      gameId: gm.predictionGame.id,
      memberNumber: subjectRating.memberNumber,
      predictionSetId: predictionSet.id,
      type: targetType,
      validAfter: latestBetTimestamp,
      configHash: _config.configHash,
    );

    List<DbWager> excludedWagers = [];
    // If the bettor has prior wagers for the given subject, we exclude them from the calculation
    // when they are sufficiently dissimilar to the current prediction.
    if(_excludeWagers) {
      for(var wager in wagersForSubject) {
        if(wager.user.value?.id == bettor.id) {
          // The prior wager was made by the bettor.

          if(!_wagersAreSimilar(
            incomingWager: incomingWager,
            wager: wager,
            modelPlace: modelPlace,
            subject: subjectRating,
          )) {
            _log.v("Current player's prior wager ${wager.descriptiveString} excluded for conflict with incoming wager ${incomingWager.descriptiveString}");
            excludedWagers.add(wager);
          }
        }
      }
    }

    if(_useCache && cachedDelta != null) {
      if(excludedWagers.isEmpty) {
        return _DeltaResult(delta: cachedDelta.delta, betWeights: cachedDelta.betWeights);
      }
    }

    if(excludedWagers.isNotEmpty) {
      _log.i("Skipping cache: ${bettor.nickname ?? bettor.serverUser.value?.displayName ?? bettor.id} has ${excludedWagers.length} excluded wagers");

      wagersForSubject = wagersForSubject.where((w) => !excludedWagers.contains(w)).toList();
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
      subjectScoringGroup: incomingScoringGroup,
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
      return _DeltaResult(delta: 0.0, betWeights: []);
    }

    _log.v("Bayesian odds shift calculation result:");
    _log.v(result.log);

    var betWeights = priorSubjectWagers.map((w) => w.calculateWeight(config)).toList();
    if(excludedWagers.isEmpty) {
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
        betWeights: betWeights,
      ));
    }

    return _DeltaResult(delta: result.delta, betWeights: betWeights);
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
    required RatingGroup subjectScoringGroup,
    required MonteCarloSimulationResult subjectMonteCarlo,
    IMonteCarloCache? cache,
    Map<ShooterRating, AlgorithmPrediction>? shootersToPredictions,
  }) async {
    List<BayesianOddsWager> priorWagers = [];
    final subject = DbPredictionTarget.fromShooterRating(subjectRating);
    for(var wager in wagers) {
      Map<DbPrediction, MonteCarloSimulationResult> spreadFavoriteMonteCarloResults = {};
      Map<DbPrediction, MonteCarloSimulationResult> spreadUnderdogMonteCarloResults = {};

      if(wager.scoringGroup.value?.uuid != subjectScoringGroup.uuid) {
        _log.i("Skipping wager ${wager.descriptiveString} because ${wager.scoringGroup.value?.name} != ${subjectScoringGroup.name}");
      }

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
            scoringGroupUuid: subjectScoringGroup.uuid,
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

  /// Returns true if [incomingWager] is in the same direction of a player's
  /// prior wager [wager], i.e. we can keep [wager] when calculating a Bayesian
  /// odds shift.
  bool _wagersAreSimilar({
    required Wager incomingWager,
    required Shooter subject,
    required DbWager wager,
    required double modelPlace,
  }) {
    var incomingType = switch(incomingWager.prediction) {
      PlacePrediction() => DbPredictionType.place,
      PercentagePrediction() => DbPredictionType.percentage,
      PercentageSpreadPrediction() => DbPredictionType.spread,
      _ => throw ArgumentError("Unsupported prediction type: ${incomingWager.prediction.runtimeType}"),
    };

    bool isSimilar = true;
    for(var leg in wager.legs) {
      if(!leg.type.isCompatibleWith(incomingType)) {
        // Incompatible legs don't matter—we only care about legs
        // that are compatible with the incoming wager.
        continue;
      }

      // Otherwise, all compatible legs must be in the same direction to include this wager.
      if(leg.type == DbPredictionType.place && incomingType == DbPredictionType.place) {
        var placePrediction = incomingWager.prediction as PlacePrediction;
        var incomingCenterPlace = (placePrediction.bestPlace + placePrediction.worstPlace) / 2;
        var wagerCenterPlace = (leg.bestPlace! + leg.worstPlace!) / 2;

        int incomingSign = incomingCenterPlace >= modelPlace ? 1 : -1;
        int wagerSign = wagerCenterPlace >= modelPlace ? 1 : -1;
        if(incomingSign != wagerSign) {
          isSimilar = false;
          break;
        }
      }
      else if(incomingType == DbPredictionType.percentage) {
        var incomingAbove = (incomingWager.prediction as PercentagePrediction).above;

        if(leg.type == DbPredictionType.percentage) {
          var wagerAbove = leg.abovePercentage;
          if(incomingAbove != wagerAbove) {
            isSimilar = false;
            break;
          }
        }
        else if(leg.type == DbPredictionType.spread) { // leg is spread
          bool isFavorite = leg.target.matchesShooterSync(db, subject);
          bool spreadSignalUp = isFavorite ? leg.favoriteCovers : !leg.favoriteCovers;

          if(incomingAbove != spreadSignalUp) {
            isSimilar = false;
            break;
          }
        }
        else {
          throw StateError("Unsupported prediction type: ${leg.type}");
        }
      }
      else if(incomingType == DbPredictionType.spread) {
        // For spreads, we have two subjects, but we'll just look at the favorite for
        // 'is similar' purposes.
        var spreadPrediction = incomingWager.prediction as PercentageSpreadPrediction;
        bool isFavorite = subject.equalsShooter(spreadPrediction.favorite, allPossibleMemberNumbers: true);
        bool incomingSpreadSignalUp = isFavorite ? spreadPrediction.favoriteCovers : !spreadPrediction.favoriteCovers;

        if(leg.type == DbPredictionType.percentage) {
          var wagerAbove = leg.abovePercentage;
          if(incomingSpreadSignalUp != wagerAbove) {
            isSimilar = false;
            break;
          }
        }
        else if(leg.type == DbPredictionType.spread) { // leg is spread
          bool isFavorite = leg.target.matchesShooterSync(db, subject);
          bool spreadSignalUp = isFavorite ? leg.favoriteCovers : !leg.favoriteCovers;

          if(incomingSpreadSignalUp != spreadSignalUp) {
            isSimilar = false;
            break;
          }
        }
        else {
          throw StateError("Unsupported prediction type: ${leg.type}");
        }
      }
      else {
        throw StateError("Unsupported prediction type: ${leg.type}");
      }
    }
    return isSimilar;
  }
}

class _DeltaResult {
  double delta;
  List<double> betWeights;

  _DeltaResult({
    required this.delta,
    required this.betWeights,
  });
}