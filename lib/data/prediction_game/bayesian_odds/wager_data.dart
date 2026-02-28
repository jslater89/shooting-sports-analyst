import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/config.dart';
import 'package:shooting_sports_analyst/data/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("BayesianOddsWager");

/// A prior wager for Bayesian odds calculation.
class BayesianOddsWager {
  /// The raw amount of the wager.
  final double amount;

  /// The maximum wager the player could make at the time this wager was placed.
  /// This is the lowest of the player's bankroll, the player's tier-specific maximum wager,
  /// and any time-based wager limits for distance from the match.
  ///
  /// Null if not available.
  final double? maxWager;

  /// The sharpness of the player's betting history.
  final double sharpness;

  /// The number of resolved wagers the player has made.
  final int resolvedPlayerWagers;

  /// The distance from the match in days.
  final double daysUntilMatch;

  /// Whether to use the underdog results when evaluating this wager.
  final bool useUnderdogResults;

  /// The actual prediction.
  final BayesianOddsPrediction prediction;

  double? _weight;

  BayesianOddsWager({
    required this.amount,
    required this.maxWager,
    required this.sharpness,
    required this.resolvedPlayerWagers,
    required this.daysUntilMatch,
    required DbPrediction prediction,
    this.useUnderdogResults = false,
  }) : prediction = BayesianOddsPrediction.fromDbPrediction(prediction);

  double calculateWeight(BayesianOddsConfig config, {bool logComponents = false}) {
    if(_weight != null) {
      return _weight!;
    }

    // If maxWager is not available, conviction = 1.0.
    final double rawConviction;
    if(maxWager != null) {
      rawConviction = amount / maxWager!;
    }
    else {
      rawConviction = config.defaultConviction;
    }
    double conviction = log(1 + rawConviction * config.convictionLogK) / log(1 + config.convictionLogK);
    conviction = max(conviction, config.convictionFloor);

    double skillMultiplier = 1.0;
    if(resolvedPlayerWagers >= config.minSharpnessBets) {
      skillMultiplier = sharpness.clamp(config.sharpnessClampMin, config.sharpnessClampMax);
    }

    double timeDecay = exp(-config.lambda * daysUntilMatch);

    if(logComponents) {
      _log.v("Weight -> conviction: ${conviction.toStringAsFixed(4)} (raw: ${rawConviction.toStringAsFixed(4)})");
      _log.v("Weight -> skill multiplier: ${skillMultiplier.toStringAsFixed(4)}");
      _log.v("Weight -> time decay: ${timeDecay.toStringAsFixed(4)}");
    }

    _weight = conviction * skillMultiplier * timeDecay * config.baseWeight;
    return _weight!;
  }

  double evaluateAgainstSimulation({
    double delta = 0.0,
    required DbPredictionType type,
    required MonteCarloSimulationResult subjectMonteCarlo,
  }) {
    if(type == DbPredictionType.place) {
      return evaluatePlaceAgainstSimulation(delta: delta, monteCarlo: subjectMonteCarlo);
    }
    else if(type == DbPredictionType.percentage) {
      return evaluatePercentAgainstSimulation(delta: delta, monteCarlo: subjectMonteCarlo);
    }
    else {
      throw ArgumentError("Unsupported prediction type: ${type}");
    }
  }

  /// Evaluate the wager given Monte Carlo samples for the subject and
  /// a delta. Recall that we decompose spread wagers into a pair of
  /// percentage wagers, one for the subject and one for the underdog.
  ///
  /// Returns the probability of the wager hitting on the given Monte
  /// Carlo sample.
  ///
  /// [delta] is the amount to add to each sample in the Monte Carlo result.
  /// Note that [delta] is always signed such that a positive value is a better
  /// result. For place wagers, we subtract delta from the sample place. For
  /// percentage wagers, we add delta to the sample ratio.
  ///
  /// [monteCarlo] is the Monte Carlo simulation results to evaluate the wager against.
  double evaluatePlaceAgainstSimulation({
    double delta = 0.0,
    required MonteCarloSimulationResult monteCarlo,
  }) {
    if (prediction.type != DbPredictionType.place) {
      throw ArgumentError("Wager is not a place wager.");
    }

    final bestPlace = prediction.bestPlace!;
    final worstPlace = prediction.worstPlace!;

    int hits = 0;
    int trials = monteCarlo.percentages.length;

    for(int i = 0; i < trials; i++) {
      var sampleOutput = monteCarlo.places[i] - delta;
      if(sampleOutput < 0.5) {
        sampleOutput = 0.5;
      }

      var bestPlaceThreshold = bestPlace - 0.5;
      var worstPlaceThreshold = worstPlace + 0.5;
      if(sampleOutput >= bestPlaceThreshold && sampleOutput <= worstPlaceThreshold) {
        hits++;
      }
    }

    return hits / trials;
  }

  double evaluatePercentAgainstSimulation({
    double delta = 0.0,
    required MonteCarloSimulationResult monteCarlo,
  }) {
    if (prediction.type != DbPredictionType.percentage) {
      throw ArgumentError("Wager is not a percentage wager.");
    }

    final percentage = prediction.percentage!;
    final abovePercentage = prediction.abovePercentage!;

    int hits = 0;
    int trials = monteCarlo.percentages.length;

    for(int i = 0; i < trials; i++) {
      var sampleOutput = monteCarlo.percentages[i] + delta;

      if(sampleOutput < 0.0) {
        sampleOutput = 0.0;
      }
      else if(sampleOutput > 1.0) {
        sampleOutput = 1.0;
      }

      if(abovePercentage) {
        if(sampleOutput >= percentage) {
          hits++;
        }
      }
      else {
        if(sampleOutput <= percentage) {
          hits++;
        }
      }
    }

    return hits / trials;
  }

  /// Return the Bayesian odds wagers for a given DbWager.
  ///
  /// If DbWager is a parlay or spread, the list will have multiple
  /// elements.
  ///
  /// [subject] is the individual comeptitor for whom the odds update
  /// is being calculated.
  ///
  /// [gm] is the [PredictionGameManager] for the prediction game in
  /// question.
  ///
  /// [dbWager] is the [DbWager] to convert to Bayesian odds wagers.
  static Future<List<BayesianOddsWager>> fromDbWager({
    required DbPredictionTarget subject,
    required PredictionGameManager gm,
    required DbWager dbWager,

    /// The Monte Carlo simulation results for the subject. Required
    /// only if the wager contains a spread leg.
    MonteCarloSimulationResult? subjectMonteCarlo,

    /// The Monte Carlo simulation results for the underdog. Required
    /// only if the wager contains a spread leg.
    MonteCarloSimulationResult? underdogMonteCarlo,
  }) async {
    var wagers = <BayesianOddsWager>[];

    // Calculate the sharpness of the player.
    double sharpness = 1.0;

    await dbWager.user.load();
    var user = dbWager.user.value!;

    double? maxWager;
    if(dbWager.maximumWager != null) {
      maxWager = dbWager.maximumWager!;
    }

    final playerWagers = await gm.getWagers(player: user);
    final resolvedWagers = playerWagers.where((w) => w.status == DbWagerStatus.won || w.status == DbWagerStatus.lost).toList();
    sharpness = PredictionLeaderboardEntry.fromPlayer(user, LeaderboardSortMode.sharpness, preloadedWagers: resolvedWagers).value;

    // Calculate the days until the match.
    await dbWager.matchPrep.load();
    var matchPrep = dbWager.matchPrep.value!;
    final daysUntilMatch = matchPrep.matchDate.difference(dbWager.created).inHours / 24.0;

    final perLeg = dbWager.amount / dbWager.legs.length;
    final maxPerLeg = maxWager != null ? maxWager / dbWager.legs.length : null;

    // If this is a multi-leg wager, some legs may not be relevant to the subject.
    for(var leg in dbWager.legs) {
      if(leg.type == DbPredictionType.spread) {
        if(subjectMonteCarlo == null || underdogMonteCarlo == null) {
          _log.w("Missing Monte Carlo simulation results for spread leg ${leg.descriptiveString}");
          continue;
        }

        if(leg.target.isSameAs(subject) || leg.underdog!.isSameAs(subject)) {
          wagers.add(_decomposeSpreadLeg(
            leg,
            subject: BayesianOddsTarget.fromDbPredictionTarget(subject),
            perLeg: perLeg,
            maxWager: maxPerLeg,
            sharpness: sharpness,
            resolvedPlayerWagers: resolvedWagers.length,
            daysUntilMatch: daysUntilMatch,
            subjectMonteCarlo: subjectMonteCarlo,
            underdogMonteCarlo: underdogMonteCarlo,
          ));
        }
      }
      else {
        if(leg.target.isSameAs(subject)) {
          wagers.add(
            BayesianOddsWager(
              amount: perLeg,
              maxWager: maxPerLeg,
              sharpness: sharpness,
              resolvedPlayerWagers: resolvedWagers.length,
              daysUntilMatch: daysUntilMatch,
              prediction: leg,
            ),
          );
        }
      }
    }

    return wagers;
  }

  /// Return the Bayesian odds data for a given spread leg, returning either
  /// the target or underdog virtual bet based on the identity of subject.
  static BayesianOddsWager _decomposeSpreadLeg(DbPrediction leg, {
    required BayesianOddsTarget subject,
    required double perLeg,
    required double? maxWager,
    required double sharpness,
    required int resolvedPlayerWagers,
    required double daysUntilMatch,
    required MonteCarloSimulationResult subjectMonteCarlo,
    required MonteCarloSimulationResult underdogMonteCarlo,
  }) {
    final meanA = subjectMonteCarlo.percentages.average;
    final meanB = underdogMonteCarlo.percentages.average;
    final modelGap = meanA - meanB;

    double excess;
    if(leg.favoriteCovers) {
      excess = leg.percentage! - modelGap;
    }
    else {
      excess = modelGap - leg.percentage!;
    }

    final thresholdA = meanA + excess / 2;
    final thresholdB = meanB - excess / 2;

    if(subject.isSameAs(leg.target)) {
      final predictionA = DbPrediction.fromBayesianOddsWager(
        percentage: thresholdA,
        abovePercentage: leg.favoriteCovers,
        target: leg.target,
      );

      return BayesianOddsWager(
        amount: perLeg / 2,
        maxWager: maxWager != null ? maxWager / 2 : null,
        sharpness: sharpness,
        resolvedPlayerWagers: resolvedPlayerWagers,
        daysUntilMatch: daysUntilMatch,
        prediction: predictionA,
      );
    }
    else if(subject.isSameAs(leg.underdog!)) {
      final predictionB = DbPrediction.fromBayesianOddsWager(
        percentage: thresholdB,
        abovePercentage: !leg.favoriteCovers,
        target: leg.underdog!,
      );


      return BayesianOddsWager(
        amount: perLeg / 2,
        maxWager: maxWager != null ? maxWager / 2 : null,
        sharpness: sharpness,
        resolvedPlayerWagers: resolvedPlayerWagers,
        daysUntilMatch: daysUntilMatch,
        prediction: predictionB,
        useUnderdogResults: true,
      );
    }
    else {
      throw ArgumentError("Subject ${subject.name} does not match either the target ${leg.target.name} or the underdog ${leg.underdog!.name}.");
    }
  }

  @override
  String toString() {
    return "${prediction.toString()}\n"
      "\tamount: ${amount.toStringAsFixed(2)}\n"
      "\tmaxWager: ${maxWager?.toStringAsFixed(2) ?? "N/A"}\n"
      "\tsharpness: ${sharpness.toStringAsFixed(3)}\n"
      "\tresolvedPlayerWagers: ${resolvedPlayerWagers}\n"
      "\tdaysUntilMatch: ${daysUntilMatch.toStringAsFixed(1)}\n";
  }
}

class BayesianOddsTarget {
  int projectId;
  String groupUuid;
  String firstName;
  String lastName;
  String memberNumber;
  List<String> knownMemberNumbers;

  String get name => "${firstName} ${lastName}";

  BayesianOddsTarget({
    required this.projectId,
    required this.groupUuid,
    required this.firstName,
    required this.lastName,
    required this.memberNumber,
    required this.knownMemberNumbers,
  });

  factory BayesianOddsTarget.fromDbPredictionTarget(DbPredictionTarget target) {
    return BayesianOddsTarget(
      projectId: target.projectId,
      groupUuid: target.groupUuid,
      firstName: target.firstName,
      lastName: target.lastName,
      memberNumber: target.memberNumber,
      knownMemberNumbers: target.knownMemberNumbers,
    );
  }

  @override
  String toString() {
    return "$name (${memberNumber})";
  }

  bool isSameAs(Object? other) {
    if(other == null) {
      return false;
    }
    if(other is BayesianOddsTarget) {
      if(projectId != other.projectId) {
        return false;
      }
      if(groupUuid != other.groupUuid) {
        return false;
      }
      return knownMemberNumbers.intersects(other.knownMemberNumbers);
    }
    if(other is DbPredictionTarget) {
      return isSameAs(BayesianOddsTarget.fromDbPredictionTarget(other));
    }
    return false;
  }
}

class BayesianOddsPrediction {
  DbPredictionType type;
  int? bestPlace;
  int? worstPlace;
  double? percentage;
  bool? abovePercentage;
  BayesianOddsTarget target;
  BayesianOddsTarget? underdog;

  BayesianOddsPrediction({
    required this.type,
    required this.bestPlace,
    required this.worstPlace,
    required this.percentage,
    required this.abovePercentage,
    required this.target,
    required this.underdog,
  });

  factory BayesianOddsPrediction.fromDbPrediction(DbPrediction prediction) {
    return BayesianOddsPrediction(
      type: prediction.type,
      bestPlace: prediction.bestPlace,
      worstPlace: prediction.worstPlace,
      percentage: prediction.percentage,
      abovePercentage: prediction.abovePercentage,
      target: BayesianOddsTarget.fromDbPredictionTarget(prediction.target),
      underdog: prediction.underdog != null ? BayesianOddsTarget.fromDbPredictionTarget(prediction.underdog!) : null,
    );
  }

  @override
  String toString() {
    if(type == DbPredictionType.place) {
      return "${target.name} ${bestPlace!.ordinalPlace}-${worstPlace!.ordinalPlace}";
    }
    else if(type == DbPredictionType.percentage) {
      return "${target.name} ${abovePercentage! ? "≥" : "≤"} ${percentage!.asPercentage(decimals: 2, includePercent: true)}";
    }
    return "unsupported prediction type: $type";
  }
}