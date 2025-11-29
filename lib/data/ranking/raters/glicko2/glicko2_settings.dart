/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math' show pow, sqrt;

import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';

class Glicko2Settings extends RaterSettings {

  static const _initialRatingKey = "g2InitialRating";
  static const _maximumRDKey = "g2MaximumRD";
  static const _tauKey = "g2Tau";
  static const _pseudoRatingPeriodLengthKey = "g2PseudoRatingPeriodLength";

  Glicko2Settings({
    this.initialRating = defaultInitialRating,
    this.startingRD = defaultStartingRD,
    this.maximumRD = defaultMaximumRD,
    this.tau = defaultTau,
    this.pseudoRatingPeriodLength = defaultPseudoRatingPeriodLength,
    this.initialVolatility = defaultInitialVolatility,
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

  /// The starting RD for Glicko-2, in display units.
  double startingRD;

  double scaleToInternal(double number, {double? offset}) => (number - (offset ?? 0)) / scalingFactor;
  double scaleToDisplay(double number, {double? offset}) => (number * scalingFactor) + (offset ?? 0);

  /// Converts volatility to display units showing the RD increase per rating period.
  ///
  /// Calculates the actual RD increase using the formula: sqrt(referenceRD^2 + volatility^2) - referenceRD,
  /// where referenceRD is 50 (an active/well-known competitor) in internal units according to default scaling.
  /// This shows how much RD increases per rating period for a shooter at that RD.
  double volatilityToDisplay(double volatility) {
    final referenceRDInternal = 50 / defaultScalingFactor;
    final newRDInternal = sqrt(pow(referenceRDInternal, 2) + pow(volatility, 2));
    final rdIncreaseInternal = newRDInternal - referenceRDInternal;
    return scaleToDisplay(rdIncreaseInternal);
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
    json[_initialRatingKey] = initialRating;
    json[_maximumRDKey] = maximumRD;
    json[_tauKey] = tau;
    json[_pseudoRatingPeriodLengthKey] = pseudoRatingPeriodLength;
  }

  @override
  void loadFromJson(Map<String, dynamic> json) {
    initialRating = (json[_initialRatingKey] ?? defaultInitialRating) as double;
    maximumRD = (json[_maximumRDKey] ?? defaultMaximumRD) as double;
    tau = (json[_tauKey] ?? defaultTau) as double;
    pseudoRatingPeriodLength = (json[_pseudoRatingPeriodLengthKey] ?? defaultPseudoRatingPeriodLength) as int;
  }
}
