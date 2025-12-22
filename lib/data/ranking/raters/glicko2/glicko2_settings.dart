/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math' show pow, sqrt;

import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_score_functions.dart';

class Glicko2Settings extends RaterSettings {

  static const _byStageKey = "g2ByStage";
  static const _initialRatingKey = "g2InitialRating";
  static const _maximumRDKey = "g2MaximumRD";
  static const _tauKey = "g2Tau";
  static const _pseudoRatingPeriodLengthKey = "g2PseudoRatingPeriodLength";
  static const _opponentSelectionModeKey = "g2OpponentSelectionMode";
  static const _initialVolatilityKey = "g2InitialVolatility";
  static const _startingRDKey = "g2StartingRD";
  static const _maximumRatingDeltaKey = "g2MaximumRatingDelta";
  static const _scoreFunctionTypeKey = "g2ScoreFunctionType";
  static const _perfectVictoryDifferenceKey = "g2PerfectVictoryDifference";
  static const _linearRegionKey = "g2LinearRegion";
  static const _marginOfVictoryInflationKey = "g2MarginOfVictoryInflation";
  static const _maximumOpponentCountForNewKey = "g2MaximumOpponentCount";
  static const _maximumOpponentCountForExistingKey = "g2MaximumOpponentCountForExisting";
  static const _limitOpponentsModeKey = "g2LimitOpponentsMode";
  static const _useInitialVolatilityForPriorKey = "g2UseInitialVolatilityForPrior";

  Glicko2Settings({
    this.byStage = false,
    this.initialRating = defaultInitialRating,
    this.startingRD = defaultStartingRD,
    this.maximumRD = defaultMaximumRD,
    this.tau = defaultTau,
    this.pseudoRatingPeriodLength = defaultPseudoRatingPeriodLength,
    this.initialVolatility = defaultInitialVolatility,
    this.opponentSelectionMode = OpponentSelectionMode.topAndNearby,
    this.maximumRatingDelta = defaultMaximumRatingDelta,
    this.scoreFunctionType = ScoreFunctionType.linearMarginOfVictory,
    this.perfectVictoryDifference = defaultPerfectVictoryDifference,
    this.eLinearRegion = defaultLinearRegion,
    this.marginOfVictoryInflation = defaultMarginOfVictoryInflation,
    this.maximumOpponentCountForNew = defaultMaximumOpponentCount,
    this.maximumOpponentCountForExisting = defaultMaximumOpponentCountForExisting,
    this.limitOpponentsMode = LimitOpponentsMode.rating,
    this.useInitialVolatilityForPrior = true,
  });

  /// The default default rating for Glicko-2, in display units.
  static const defaultInitialRating = 1500.0;
  /// The 1500pt-center Glicko-2 scaling factor.
  static const defaultScalingFactor = 173.7178;
  /// The maximum RD to allow, in display units.
  static const defaultMaximumRD = 400.0;
  /// The default tau value for Glicko-2.
  static const defaultTau = 0.8;
  /// The length of a pseudo-rating-period for the purposes of
  /// increasing RD over time, in days.
  static const defaultPseudoRatingPeriodLength = 7;
  /// The default initial volatility for Glicko-2.
  static const defaultInitialVolatility = 0.06;
  /// The default starting RD for Glicko-2.
  static const defaultStartingRD = 350.0;
  /// The default maximum rating delta to allow per match.
  static const defaultMaximumRatingDelta = 750.0;
  /// The default perfect victory difference for Glicko-2's linear margin of victory score function.
  static const defaultPerfectVictoryDifference = 0.25;
  /// The default linear region for the score function in predictions, measured in from 0 and 1.
  static const defaultLinearRegion = 0.125;
  /// The default margin of victory inflation factor for predictions.
  static const defaultMarginOfVictoryInflation = 1.00;
  /// The default maximum number of opponents to consider when calculating rating updates for new players.
  static const defaultMaximumOpponentCount = 20;
  /// The default maximum number of opponents to consider when calculating rating updates for existing players.
  static const int? defaultMaximumOpponentCountForExisting = null;
  /// The default maximum volatility to allow, in display units.
  static const defaultMaximumVolatility = 0.15;

  /// Whether to calculate and update ratings by stage (true) or by match (false).
  ///
  /// By match is the default, the standard behavior, and the most sturdily tested.
  bool byStage;

  /// The default initial rating for Glicko-2, in display units.
  double initialRating;

  /// The scaling factor to convert from small-float internal ratings to display ratings and RDs.
  ///
  /// Derived from the initial rating and default initial rating; will always scale to standard
  /// Glicko-2 internal units.
  double get scalingFactor => initialRating / defaultInitialRating * defaultScalingFactor;

  /// The initial volatility for Glicko-2.
  ///
  /// Volatility is a non-scaled property.
  double initialVolatility;

  /// True if the prior volatility should be the initial volatility or the current volatility.
  bool useInitialVolatilityForPrior;

  /// The starting RD for Glicko-2, in display units.
  double startingRD;

  /// The method to use for selecting opponents when calculating rating updates.
  OpponentSelectionMode opponentSelectionMode;

  /// The maximum rating delta to allow per match, in display units. Maximum rating delta
  /// is a safety valve; generally, Glicko-2 will perform well without it, but this serves
  /// to catch some occasional numerical instability before it can become too big a problem.
  double maximumRatingDelta;

  /// The maximum rating delta to allow per match, in internal units.
  double get internalMaximumRatingDelta => scaleToInternal(maximumRatingDelta);

  /// The score function type to use for calculating match scores.
  ScoreFunctionType scoreFunctionType;

  Glicko2ScoreFunction get scoreFunction => switch(scoreFunctionType) {
    ScoreFunctionType.allOrNothing => AllOrNothingScoreFunction(),
    ScoreFunctionType.linearMarginOfVictory => LinearMarginOfVictoryScoreFunction(perfectVictoryDifference: perfectVictoryDifference),
  };

  /// The perfect victory difference for Glicko-2's linear margin of victory score function.
  double perfectVictoryDifference;

  /// The linear region for the expected score function in predictions, measured in from 0 and 1.
  ///
  /// e.g. 0.175 means the linear region is between 0.175 and 1 - 0.175 = 0.825.
  double eLinearRegion;

  /// The margin of victory inflation factor for predictions, which can help reduce
  /// numerical instability/compression from repeated applications of the score function.
  ///
  /// e.g. 1.05 means the margin of victory predicted by the expected score is inflated by 5%.
  double marginOfVictoryInflation;

  /// The maximum number of opponents to consider when calculating rating updates for new players.
  ///
  /// When opponent selection modes produce more opponents than this limit, opponents are
  /// prioritized by rating proximity (closer ratings first). This helps prevent excessive
  /// rating changes for new competitors joining mature rating sets, where comparing against
  /// many opponents with large rating gaps can cause deltaSum to accumulate to problematic values.
  int maximumOpponentCountForNew;

  /// The maximum number of opponents to consider when calculating rating updates for existing players.
  ///
  /// When opponent selection modes produce more opponents than this limit, opponents are
  /// prioritized by rating proximity (closer ratings first).
  int? maximumOpponentCountForExisting;

  /// The method to use for selecting opponents when calculating rating updates for existing players.
  LimitOpponentsMode limitOpponentsMode;

  double scaleToInternal(double number, {double? offset}) => (number - (offset ?? 0)) / scalingFactor;
  double scaleToDisplay(double number, {double? offset}) => (number * scalingFactor) + (offset ?? 0);

  /// Converts volatility to display units showing the RD increase per rating period.
  ///
  /// Calculates the actual RD increase using the formula: sqrt(referenceRD^2 + volatility^2) - referenceRD,
  /// where referenceRD is 25 (an active/well-known competitor) in internal units according to default scaling.
  /// This shows how much RD increases per rating period for a shooter at that RD.
  double volatilityToDisplay(double volatility) {
    final referenceRDInternal = 25 / defaultScalingFactor;
    final newRDInternal = sqrt(pow(referenceRDInternal, 2) + pow(volatility, 2));
    final rdIncreaseInternal = newRDInternal - referenceRDInternal;
    return scaleToDisplay(rdIncreaseInternal);
  }

  /// Converts volatility to an alternate representation showing how far above or below default the competitor is.
  double volatilityToAlternateDisplay(double volatility) {
    // scale volatility to a number between (some negative value) and 1000, where
    // 0 is the initial volatility and 1000 is the maximum volatility.
    var percentageDifference = (volatility - initialVolatility) / (defaultMaximumVolatility - initialVolatility);
    var scaleFactor = (defaultMaximumVolatility - initialVolatility) / initialVolatility * 1000;
    return percentageDifference * scaleFactor;
  }

  /// The maximum RD to allow, in display units.
  double maximumRD;

  /// The maximum RD to allow, in internal units.
  double get internalMaximumRD => scaleToInternal(maximumRD);

  /// The tau value for Glicko-2, which controls the rate of volatility change.
  double tau;

  /// The length of a pseudo-rating-period for the purposes of
  /// increasing volatility over time, in days.
  int pseudoRatingPeriodLength;

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[_byStageKey] = byStage;
    json[_initialRatingKey] = initialRating;
    json[_maximumRDKey] = maximumRD;
    json[_tauKey] = tau;
    json[_pseudoRatingPeriodLengthKey] = pseudoRatingPeriodLength;
    json[_opponentSelectionModeKey] = opponentSelectionMode.name;
    json[_initialVolatilityKey] = initialVolatility;
    json[_startingRDKey] = startingRD;
    json[_maximumRatingDeltaKey] = maximumRatingDelta;
    json[_scoreFunctionTypeKey] = scoreFunctionType.name;
    json[_perfectVictoryDifferenceKey] = perfectVictoryDifference;
    json[_linearRegionKey] = eLinearRegion;
    json[_marginOfVictoryInflationKey] = marginOfVictoryInflation;
    json[_maximumOpponentCountForNewKey] = maximumOpponentCountForNew;
    json[_maximumOpponentCountForExistingKey] = maximumOpponentCountForExisting;
    json[_limitOpponentsModeKey] = limitOpponentsMode.name;
    json[_useInitialVolatilityForPriorKey] = useInitialVolatilityForPrior;
  }

  @override
  void loadFromJson(Map<String, dynamic> json) {
    byStage = (json[_byStageKey] ?? false) as bool;
    initialRating = (json[_initialRatingKey] ?? defaultInitialRating) as double;
    maximumRD = (json[_maximumRDKey] ?? defaultMaximumRD) as double;
    tau = (json[_tauKey] ?? defaultTau) as double;
    pseudoRatingPeriodLength = (json[_pseudoRatingPeriodLengthKey] ?? defaultPseudoRatingPeriodLength) as int;
    opponentSelectionMode = OpponentSelectionMode.values.byName(json[_opponentSelectionModeKey] ?? OpponentSelectionMode.all.name);
    initialVolatility = (json[_initialVolatilityKey] ?? defaultInitialVolatility) as double;
    startingRD = (json[_startingRDKey] ?? defaultStartingRD) as double;
    maximumRatingDelta = (json[_maximumRatingDeltaKey] ?? defaultMaximumRatingDelta) as double;
    scoreFunctionType = ScoreFunctionType.values.byName(json[_scoreFunctionTypeKey] ?? ScoreFunctionType.linearMarginOfVictory.name);
    perfectVictoryDifference = (json[_perfectVictoryDifferenceKey] ?? defaultPerfectVictoryDifference) as double;
    eLinearRegion = (json[_linearRegionKey] ?? defaultLinearRegion) as double;
    marginOfVictoryInflation = (json[_marginOfVictoryInflationKey] ?? defaultMarginOfVictoryInflation) as double;
    maximumOpponentCountForNew = (json[_maximumOpponentCountForNewKey] ?? defaultMaximumOpponentCount) as int;
    maximumOpponentCountForExisting = (json[_maximumOpponentCountForExistingKey] ?? defaultMaximumOpponentCountForExisting) as int?;
    limitOpponentsMode = LimitOpponentsMode.values.byName(json[_limitOpponentsModeKey] ?? LimitOpponentsMode.rating.name);
    useInitialVolatilityForPrior = (json[_useInitialVolatilityForPriorKey] ?? false) as bool;
  }
}

enum OpponentSelectionMode {
  /// Use all opponents in the match.
  all,
  /// Use only the top 10% of opponents in the match, both by rating and by match finish
  top10Pct,
  /// Use only nearby opponents (within initialRD of the shooter rating or within 10% match finish)
  nearby,
  /// Use both top and nearby opponents.
  topAndNearby,
}

enum LimitOpponentsMode {
  /// Use opponents closest in rating.
  rating,
  /// Use opponents closest in match finish.
  finish;

  String get uiLabel {
    switch(this) {
      case LimitOpponentsMode.rating:
        return "Rating";
      case LimitOpponentsMode.finish:
        return "Match finish";
    }
  }

  String get tooltip {
    switch(this) {
      case LimitOpponentsMode.rating:
        return "Use opponents closest in rating.";
      case LimitOpponentsMode.finish:
        return "Use opponents closest in match finish.";
    }
  }
}
